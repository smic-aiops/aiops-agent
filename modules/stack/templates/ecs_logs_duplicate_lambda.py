import base64
import gzip
import json
import os

import boto3

logs = boto3.client("logs")

NAME_PREFIX = os.environ.get("NAME_PREFIX", "").strip("-")
MAX_EVENTS_PER_BATCH = int(os.environ.get("MAX_EVENTS_PER_BATCH", "1000") or "1000")

_sequence_tokens = {}


def _parse_log_group(log_group):
    # /aws/ecs/<realm>/<name_prefix>-<service>/<container>
    if not isinstance(log_group, str):
        return None
    parts = log_group.split("/")
    if len(parts) < 6:
        return None
    if parts[1] != "aws" or parts[2] != "ecs":
        return None
    realm = parts[3]
    service_name = parts[4]
    container = parts[5]
    if not realm or not service_name or not container:
        return None
    return realm, service_name, container


def _target_log_group(parsed):
    realm, service_name, _ = parsed
    return f"/aws/ecs/{realm}/{service_name}"


def _ensure_log_group(name):
    try:
        logs.create_log_group(logGroupName=name)
    except logs.exceptions.ResourceAlreadyExistsException:
        return


def _get_sequence_token(log_group, log_stream):
    key = f"{log_group}:{log_stream}"
    token = _sequence_tokens.get(key)
    if token is not None:
        return token
    resp = logs.describe_log_streams(
        logGroupName=log_group,
        logStreamNamePrefix=log_stream,
        limit=1,
    )
    for stream in resp.get("logStreams", []):
        if stream.get("logStreamName") == log_stream:
            token = stream.get("uploadSequenceToken")
            break
    _sequence_tokens[key] = token
    return token


def _ensure_log_stream(log_group, log_stream):
    try:
        logs.create_log_stream(logGroupName=log_group, logStreamName=log_stream)
    except logs.exceptions.ResourceAlreadyExistsException:
        pass
    return _get_sequence_token(log_group, log_stream)


def _put_log_events(log_group, log_stream, events):
    if not events:
        return
    key = f"{log_group}:{log_stream}"
    events_sorted = sorted(events, key=lambda e: e.get("timestamp", 0))
    token = _ensure_log_stream(log_group, log_stream)
    kwargs = {
        "logGroupName": log_group,
        "logStreamName": log_stream,
        "logEvents": events_sorted,
    }
    if token:
        kwargs["sequenceToken"] = token
    try:
        resp = logs.put_log_events(**kwargs)
    except (logs.exceptions.InvalidSequenceTokenException, logs.exceptions.DataAlreadyAcceptedException):
        token = _get_sequence_token(log_group, log_stream)
        if token:
            kwargs["sequenceToken"] = token
        else:
            kwargs.pop("sequenceToken", None)
        resp = logs.put_log_events(**kwargs)
    _sequence_tokens[key] = resp.get("nextSequenceToken")


def _chunks(items, size):
    for i in range(0, len(items), size):
        yield items[i : i + size]


def handler(event, context):
    data = (event.get("awslogs") or {}).get("data")
    if not data:
        return {"ok": True, "reason": "missing awslogs.data"}

    payload = json.loads(gzip.decompress(base64.b64decode(data)).decode("utf-8"))
    if payload.get("messageType") != "DATA_MESSAGE":
        return {"ok": True, "messageType": payload.get("messageType")}

    log_group = payload.get("logGroup")
    log_stream = payload.get("logStream")
    parsed = _parse_log_group(log_group)
    if not parsed:
        return {"ok": True, "skipped": True, "logGroup": log_group}

    realm, service_name, container = parsed
    if NAME_PREFIX and not service_name.startswith(f"{NAME_PREFIX}-"):
        return {"ok": True, "skipped": True, "logGroup": log_group}

    target_group = _target_log_group(parsed)
    _ensure_log_group(target_group)
    events = payload.get("logEvents") or []
    for batch in _chunks(events, max(1, MAX_EVENTS_PER_BATCH)):
        _put_log_events(target_group, log_stream, batch)

    return {
        "ok": True,
        "targetGroup": target_group,
        "events": len(events),
        "container": container,
        "realm": realm,
    }
