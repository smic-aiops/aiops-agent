import gzip
import io
import logging
import os
import shlex
import urllib.parse

import boto3
from botocore.exceptions import ClientError

s3 = boto3.client("s3")


def _normalize_prefix(prefix):
    prefix = (prefix or "").strip("/")
    return f"{prefix}/" if prefix else ""


SOURCE_PREFIX = _normalize_prefix(os.environ.get("SOURCE_PREFIX", "alb/realm/"))
TARGET_PREFIX = _normalize_prefix(os.environ.get("TARGET_PREFIX", "alb"))
DEFAULT_REALM = os.environ.get("DEFAULT_REALM", "").strip() or "default"
REALMS = [r.strip() for r in os.environ.get("REALMS", "").split(",") if r.strip()]
REALMS_SET = set(REALMS) if REALMS else {DEFAULT_REALM}
DELETE_SOURCE = os.environ.get("DELETE_SOURCE", "false").lower() in ("1", "true", "yes")

LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logging.basicConfig(level=LOG_LEVEL)
logger = logging.getLogger(__name__)


def _extract_host(line):
    try:
        parts = shlex.split(line)
    except ValueError:
        return None

    request_token = None
    for token in parts:
        if "http://" in token or "https://" in token:
            request_token = token
            break
    if not request_token:
        return None

    url = None
    for part in request_token.split():
        if part.startswith("http://") or part.startswith("https://"):
            url = part
            break
    if not url:
        return None

    try:
        parsed = urllib.parse.urlparse(url)
    except ValueError:
        return None
    host = parsed.hostname
    return host.lower() if host else None


def _realm_from_host(host):
    if not host:
        return DEFAULT_REALM
    candidate = host.split(".", 1)[0]
    return candidate if candidate in REALMS_SET else DEFAULT_REALM


def _target_key(source_key, realm):
    key = source_key
    if SOURCE_PREFIX and key.startswith(SOURCE_PREFIX):
        key = key[len(SOURCE_PREFIX) :]
    key = key.lstrip("/")
    if not key:
        return None

    parts = key.split("/", 1)
    if len(parts) > 1 and parts[0] == DEFAULT_REALM:
        key = parts[1]

    if TARGET_PREFIX:
        return f"{TARGET_PREFIX}{realm}/{key}"
    return f"{realm}/{key}"


def _iter_lines(body, is_gzip):
    if is_gzip:
        with gzip.GzipFile(fileobj=body) as gz:
            for line in gz:
                yield line
    else:
        for line in body.iter_lines():
            yield line + b"\n"


def _get_writer(buffers, realm):
    writer = buffers.get(realm)
    if writer:
        return writer
    raw = io.BytesIO()
    gz = gzip.GzipFile(fileobj=raw, mode="wb")
    writer = (raw, gz)
    buffers[realm] = writer
    return writer


def _split_by_realm(body, is_gzip):
    buffers = {}
    total_lines = 0
    for line_bytes in _iter_lines(body, is_gzip):
        total_lines += 1
        line = line_bytes.decode("utf-8", "replace")
        realm = _realm_from_host(_extract_host(line))
        _, gz = _get_writer(buffers, realm)
        gz.write(line_bytes)

    outputs = {}
    for realm, (raw, gz) in buffers.items():
        gz.close()
        outputs[realm] = raw.getvalue()
    return outputs, total_lines


def handler(event, context):
    records = event.get("Records") or []
    results = []

    for record in records:
        if record.get("eventSource") != "aws:s3":
            continue
        bucket = (record.get("s3") or {}).get("bucket", {}).get("name")
        key = (record.get("s3") or {}).get("object", {}).get("key")
        if not bucket or not key:
            continue
        key = urllib.parse.unquote_plus(key)
        if SOURCE_PREFIX and not key.startswith(SOURCE_PREFIX):
            continue

        try:
            resp = s3.get_object(Bucket=bucket, Key=key)
        except ClientError as exc:
            if exc.response.get("Error", {}).get("Code") == "NoSuchKey":
                logger.info("skip missing object: %s", key)
                continue
            raise

        is_gzip = key.endswith(".gz") or resp.get("ContentEncoding") == "gzip"
        outputs, total_lines = _split_by_realm(resp["Body"], is_gzip)
        written = 0
        for realm, data in outputs.items():
            target_key = _target_key(key, realm)
            if not target_key or not data:
                continue
            s3.put_object(
                Bucket=bucket,
                Key=target_key,
                Body=data,
                ContentType="text/plain",
                ContentEncoding="gzip",
            )
            written += 1

        if DELETE_SOURCE and written > 0:
            s3.delete_object(Bucket=bucket, Key=key)

        results.append(
            {
                "source": key,
                "bucket": bucket,
                "lines": total_lines,
                "outputs": written,
            }
        )

    return {"ok": True, "processed": len(results), "results": results}
