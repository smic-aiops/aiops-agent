#!/usr/bin/env python3
import argparse
import hashlib
import hmac
import json
import os
import re
import sys
import time
import uuid
import zlib
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib import error, request


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def load_json_file(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def load_ingest_sources() -> List[str]:
    policy_path = repo_root() / "aiops_agent" / "policy" / "ingest_policy_ja.json"
    fallback = load_default_sources()
    if not policy_path.exists():
        return fallback

    doc = load_json_file(policy_path)
    sources = doc.get("sources", {})
    if not isinstance(sources, dict):
        return fallback

    out: List[str] = []
    for key in sources.keys():
        value = str(key).strip().lower()
        if value:
            out.append(value)
    return sorted(set(out)) or fallback


def load_stub_scenarios() -> Dict[str, Any]:
    scenarios_path = Path(__file__).resolve().parent / "stub_scenarios.json"
    if not scenarios_path.exists():
        raise FileNotFoundError(f"stub scenarios file not found: {scenarios_path}")
    return load_json_file(scenarios_path)


def load_stub_defaults(scenarios_doc: Dict[str, Any]) -> Dict[str, Any]:
    defaults = scenarios_doc.get("defaults")
    return defaults if isinstance(defaults, dict) else {}


def load_default_sources() -> List[str]:
    try:
        scenarios = load_stub_scenarios()
    except FileNotFoundError:
        return ["slack", "zulip", "mattermost", "teams", "cloudwatch", "feedback"]
    sources = scenarios.get("default_sources")
    if isinstance(sources, list):
        normalized = [str(item).strip().lower() for item in sources if str(item).strip()]
        if normalized:
            return sorted(set(normalized))
    return ["slack", "zulip", "mattermost", "teams", "cloudwatch", "feedback"]


def slugify(value: str, max_len: int = 80) -> str:
    safe = []
    for ch in value:
        if ch.isalnum() or ch in ("-", "_", "."):
            safe.append(ch)
        else:
            safe.append("_")
    return "".join(safe)[:max_len]


def build_url(base_url: str, path_template: str, source: str, tenant: Optional[str] = None) -> str:
    base = base_url.rstrip("/")
    if "{tenant}" in path_template and not tenant:
        raise ValueError("path_template uses {tenant} but no zulip tenant was provided.")
    path = path_template.format(source=source, tenant=tenant or "")
    if not path.startswith("/"):
        path = "/" + path
    return base + path


def env_or_arg(value: Optional[str], env_key: str) -> Optional[str]:
    if value is not None and value != "":
        return value
    env_val = os.getenv(env_key)
    return env_val if env_val not in (None, "") else None


def to_json_bytes(payload: Any) -> bytes:
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    return body.encode("utf-8")


def hmac_sha256_hex(secret: str, message: str) -> str:
    mac = hmac.new(secret.encode("utf-8"), msg=message.encode("utf-8"), digestmod=hashlib.sha256)
    return mac.hexdigest()


def validate_source_scenario(source: str, scenario: str, scenarios_doc: Dict[str, Any]) -> None:
    constraints = scenarios_doc.get("source_constraints", {})
    if not isinstance(constraints, dict):
        return
    rule = constraints.get(source)
    if not isinstance(rule, dict):
        return
    unsupported = rule.get("unsupported_scenarios")
    if not isinstance(unsupported, list):
        return
    unsupported_set = {str(v).strip().lower() for v in unsupported if str(v).strip()}
    if scenario in unsupported_set:
        raise ValueError(f"source={source} does not support scenario={scenario} by policy (stub_scenarios.json).")


def compute_zulip_message_id(event_id: str) -> int:
    # Zulip の message.id は数値のため、任意の event_id から安定した整数へ落とす。
    try:
        return int(event_id)
    except ValueError:
        return zlib.crc32(event_id.encode("utf-8")) & 0x7FFFFFFF


@dataclass(frozen=True)
class PreparedRequest:
    url: str
    headers: Dict[str, str]
    body_bytes: bytes
    body_text: str
    expected: str


def prepare_request(
    *,
    url: str,
    source: str,
    scenario: str,
    event_id: str,
    trace_id: str,
    expected: str,
    slack_signing_secret: Optional[str],
    zulip_token: Optional[str],
    zulip_tenant: Optional[str],
    mattermost_token: Optional[str],
    teams_test_token: Optional[str],
    cloudwatch_alarm_name: Optional[str] = None,
    message_text: Optional[str] = None,
    zulip_stream: Optional[str] = None,
    zulip_topic: Optional[str] = None,
    feedback_job_id: Optional[str] = None,
    feedback_resolved: Optional[bool] = None,
    feedback_smile_score: Optional[int] = None,
    feedback_comment: Optional[str] = None,
) -> PreparedRequest:
    headers: Dict[str, str] = {"Content-Type": "application/json; charset=utf-8", "X-AIOPS-TRACE-ID": trace_id}

    if source == "slack":
        now_ts = int(time.time())
        slack_text = message_text or "<@U_BOT> restart api"
        payload: Dict[str, Any] = {
            "type": "event_callback",
            "event_id": event_id,
            "event_time": now_ts,
            "team_id": "T_TEST",
            "event": {
                "type": "app_mention",
                "user": "U_TEST",
                "text": slack_text,
                "channel": "C_TEST",
                "ts": f"{now_ts}.000100",
                "event_ts": f"{now_ts}.000100",
            },
        }
        if scenario == "abnormal_schema":
            payload.pop("event_id", None)

        body_bytes = to_json_bytes(payload)
        body_text = body_bytes.decode("utf-8")

        headers["X-Slack-Request-Timestamp"] = str(now_ts)
        if scenario in ("normal", "duplicate"):
            if not slack_signing_secret:
                raise ValueError("Slack normal/duplicate requires --slack-signing-secret or N8N_SLACK_SIGNING_SECRET")
            sig_base = f"v0:{now_ts}:{body_text}"
            headers["X-Slack-Signature"] = "v0=" + hmac_sha256_hex(slack_signing_secret, sig_base)
        elif scenario == "abnormal_auth":
            headers["X-Slack-Signature"] = "v0=" + ("0" * 64)

        return PreparedRequest(url=url, headers=headers, body_bytes=body_bytes, body_text=body_text, expected=expected)

    if source == "zulip":
        now_ts = int(time.time())
        token = zulip_token if scenario in ("normal", "duplicate") else "INVALID_TOKEN"
        msg_id = compute_zulip_message_id(event_id)
        content = message_text or "@**AIOps エージェント** diagnose"
        payload = {
            "token": token,
            "tenant": zulip_tenant,
            "realm": zulip_tenant,
            "trigger": "mention",
            "message": {
                "id": msg_id,
                "type": "stream",
                "stream_id": 10,
                "display_recipient": zulip_stream or "0perational Qualification",
                "subject": zulip_topic or "ops",
                "content": content,
                "sender_email": "user@example.com",
                "sender_full_name": "Test User",
                "timestamp": now_ts,
            },
        }
        if scenario == "abnormal_schema":
            payload["message"].pop("id", None)

        if scenario in ("normal", "duplicate") and not zulip_token:
            raise ValueError("Zulip normal/duplicate requires --zulip-token or N8N_ZULIP_OUTGOING_TOKEN")

        body_bytes = to_json_bytes(payload)
        return PreparedRequest(
            url=url,
            headers=headers,
            body_bytes=body_bytes,
            body_text=body_bytes.decode("utf-8"),
            expected=expected,
        )

    if source == "mattermost":
        token = mattermost_token if scenario in ("normal", "duplicate") else "INVALID_TOKEN"
        payload = {
            "token": token,
            "team_id": "team_test",
            "channel_id": "channel_test",
            "user_id": "user_test",
            "user_name": "test-user",
            "post_id": event_id,
            "text": "aiops restart api",
            "trigger_word": "aiops",
        }
        if scenario == "abnormal_schema":
            payload.pop("post_id", None)

        if scenario in ("normal", "duplicate") and not mattermost_token:
            raise ValueError("Mattermost normal/duplicate requires --mattermost-token or N8N_MATTERMOST_OUTGOING_TOKEN")

        body_bytes = to_json_bytes(payload)
        return PreparedRequest(
            url=url,
            headers=headers,
            body_bytes=body_bytes,
            body_text=body_bytes.decode("utf-8"),
            expected=expected,
        )

    if source == "teams":
        if scenario in ("normal", "duplicate"):
            if not teams_test_token:
                raise ValueError("Teams normal/duplicate requires --teams-test-token or N8N_TEAMS_TEST_TOKEN")
            headers["X-AIOPS-TEST-TOKEN"] = teams_test_token
        elif scenario == "abnormal_auth":
            headers["X-AIOPS-TEST-TOKEN"] = "INVALID_TOKEN"

        payload = {
            "type": "message",
            "id": event_id,
            "timestamp": utc_now_iso(),
            "channelId": "msteams",
            "serviceUrl": "https://smba.trafficmanager.net/teams/",
            "from": {"id": "user_test", "name": "Test User"},
            "conversation": {"id": "conv_test"},
            "recipient": {"id": "bot_test", "name": "AIOps エージェント"},
            "text": "help",
        }
        if scenario == "abnormal_schema":
            payload.pop("conversation", None)

        body_bytes = to_json_bytes(payload)
        return PreparedRequest(
            url=url,
            headers=headers,
            body_bytes=body_bytes,
            body_text=body_bytes.decode("utf-8"),
            expected=expected,
        )

    if source == "cloudwatch":
        cloudwatch_webhook_token = os.environ.get("N8N_CLOUDWATCH_WEBHOOK_SECRET") or os.environ.get("N8N_CLOUDWATCH_WEBHOOK_TOKEN")
        if cloudwatch_webhook_token:
            headers["X-AIOPS-WEBHOOK-TOKEN"] = cloudwatch_webhook_token
        alarm_name = str(cloudwatch_alarm_name or "CloudWatch ALARM: ECS CPU High")
        payload: Dict[str, Any] = {
            "version": "0",
            "id": event_id,
            "detail-type": "CloudWatch Alarm State Change",
            "source": "aws.cloudwatch",
            "account": "123456789012",
            "time": utc_now_iso(),
            "region": "ap-northeast-1",
            "resources": [
                f"arn:aws:cloudwatch:ap-northeast-1:123456789012:alarm:{alarm_name}",
            ],
            "detail": {
                "alarmName": alarm_name,
                "state": {
                    "value": "ALARM",
                    "reason": "Threshold Crossed: ...",
                    "timestamp": utc_now_iso(),
                },
                "previousState": {"value": "OK"},
            },
        }
        if scenario == "abnormal_schema":
            payload.pop("detail-type", None)

        body_bytes = to_json_bytes(payload)
        return PreparedRequest(
            url=url,
            headers=headers,
            body_bytes=body_bytes,
            body_text=body_bytes.decode("utf-8"),
            expected=expected,
        )

    if source == "feedback":
        if scenario != "normal":
            raise ValueError("feedback source supports only scenario=normal (see stub_scenarios.json source_constraints).")
        if not feedback_job_id:
            raise ValueError("feedback requires --job-id")
        if feedback_resolved is None:
            raise ValueError("feedback requires --resolved (true/false)")
        if feedback_smile_score is None:
            raise ValueError("feedback requires --smile-score (integer)")

        payload = {
            "job_id": str(feedback_job_id),
            "resolved": bool(feedback_resolved),
            "smile_score": int(feedback_smile_score),
            "comment": str(feedback_comment or ""),
        }

        body_bytes = to_json_bytes(payload)
        return PreparedRequest(
            url=url,
            headers=headers,
            body_bytes=body_bytes,
            body_text=body_bytes.decode("utf-8"),
            expected=expected,
        )

    raise ValueError(f"unknown source: {source}")


def send_once(prepared: PreparedRequest, timeout_sec: float) -> Tuple[int, str, Dict[str, str], int]:
    started = time.perf_counter()
    req = request.Request(prepared.url, data=prepared.body_bytes, method="POST")
    for k, v in prepared.headers.items():
        req.add_header(k, v)

    try:
        with request.urlopen(req, timeout=timeout_sec) as resp:
            status = resp.getcode()
            headers = {k: v for k, v in resp.headers.items()}
            body = resp.read().decode("utf-8", errors="replace")
    except error.HTTPError as e:
        status = e.code
        headers = {k: v for k, v in (e.headers.items() if e.headers else [])}
        body = e.read().decode("utf-8", errors="replace")
    elapsed_ms = int((time.perf_counter() - started) * 1000)
    return status, body, headers, elapsed_ms


def check_expected(expected: str, status: int) -> Tuple[bool, str]:
    if expected == "2xx":
        ok = 200 <= status <= 299
        return ok, "2xx"

    if expected == "401/403":
        ok = status in (401, 403)
        return ok, "401/403"

    if expected == "4xx_except_404":
        ok = 400 <= status <= 499 and status != 404
        return ok, "4xx (except 404)"

    return False, "unknown"


def write_evidence(
    *,
    evidence_dir: Path,
    run_id: str,
    index: int,
    prepared: PreparedRequest,
    status: int,
    resp_body: str,
    resp_headers: Dict[str, str],
    elapsed_ms: int,
) -> None:
    def scrub_text_patterns(text: str) -> str:
        masked = text
        patterns = [
            (r"\bAKIA[0-9A-Z]{16}\b", "(masked)"),  # AWS access key id
            (r"\bxox[baprs]-[0-9A-Za-z-]{10,}\b", "(masked)"),  # Slack token
            (r"\bgh[pousr]_[A-Za-z0-9]{20,}\b", "(masked)"),  # GitHub token
            (r"\beyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\b", "(masked)"),  # JWT
            (r"(\bBearer\s+)([A-Za-z0-9._-]{10,})", r"\1(masked)"),  # Bearer token
        ]
        for pat, rep in patterns:
            masked = re.sub(pat, rep, masked)
        return masked

    def scrub_sensitive(value: Any, depth: int = 0) -> Any:
        if depth > 8:
            return "(max-depth)"
        if isinstance(value, str):
            return scrub_text_patterns(value)
        if isinstance(value, dict):
            out: Dict[str, Any] = {}
            for k, v in value.items():
                key_lower = str(k).lower()
                if (
                    key_lower in ("token", "api_key", "apikey", "password", "secret", "authorization", "cookie")
                    or "token" in key_lower
                    or "secret" in key_lower
                    or "password" in key_lower
                    or "authorization" in key_lower
                    or "cookie" in key_lower
                ):
                    out[k] = "(masked)"
                else:
                    out[k] = scrub_sensitive(v, depth + 1)
            return out
        if isinstance(value, list):
            return [scrub_sensitive(v, depth + 1) for v in value]
        return value

    def scrub_headers(headers: Dict[str, str]) -> Dict[str, str]:
        masked: Dict[str, str] = {}
        for k, v in headers.items():
            key_lower = str(k).lower()
            if (
                "authorization" in key_lower
                or "cookie" in key_lower
                or "signature" in key_lower
                or "token" in key_lower
                or "secret" in key_lower
                or "password" in key_lower
            ):
                masked[k] = "(masked)"
            else:
                masked[k] = scrub_text_patterns(v)
        return masked

    def scrub_body_text(body_text: str) -> str:
        try:
            parsed = json.loads(body_text)
        except Exception:
            return body_text
        return json.dumps(scrub_sensitive(parsed), ensure_ascii=False, separators=(",", ":"), sort_keys=True)

    evidence_dir.mkdir(parents=True, exist_ok=True)
    request_path = evidence_dir / f"{run_id}.request_{index}.json"
    response_path = evidence_dir / f"{run_id}.response_{index}.json"

    request_path.write_text(
        json.dumps(
            {
                "url": prepared.url,
                "headers": scrub_headers(prepared.headers),
                "body": scrub_body_text(prepared.body_text),
                "expected": prepared.expected,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    response_path.write_text(
        json.dumps(
            {
                "status": status,
                "headers": scrub_headers(resp_headers),
                "body": scrub_body_text(resp_body),
                "elapsed_ms": elapsed_ms,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def default_event_id(source: str) -> str:
    suffix = uuid.uuid4().hex[:8]
    if source == "slack":
        return f"Ev_oq_{suffix}"
    if source == "zulip":
        return str(int(time.time() * 1000))
    if source == "mattermost":
        return f"post_oq_{suffix}"
    if source == "teams":
        return f"teams_oq_{suffix}"
    if source == "cloudwatch":
        return f"cw_oq_{suffix}"
    return f"event_oq_{suffix}"


def main(argv: List[str]) -> int:
    scenarios_doc = load_stub_scenarios()
    scenarios = scenarios_doc.get("scenarios")
    if not isinstance(scenarios, dict) or not scenarios:
        raise ValueError("invalid stub_scenarios.json: scenarios is missing")

    sources = load_ingest_sources()
    scenario_choices = sorted({str(k).strip().lower() for k in scenarios.keys() if str(k).strip()})
    defaults = load_stub_defaults(scenarios_doc)
    default_path_template = str(defaults.get("path_template") or "/ingest/{source}")
    default_scenario = str(defaults.get("scenario") or "normal").strip().lower()
    default_timeout = float(defaults.get("timeout_sec") or 10.0)

    parser = argparse.ArgumentParser(description="AIOps ingest stub sender (OQ-ready evidence support).")
    parser.add_argument("--base-url", help="e.g. https://n8n.example.com (ignored when --url is given)")
    parser.add_argument("--path-template", default=default_path_template, help=f"default: {default_path_template}")
    parser.add_argument("--url", help="full ingest URL (overrides --base-url/--path-template)")
    parser.add_argument("--source", choices=sources, required=True)
    parser.add_argument("--scenario", choices=scenario_choices, default=default_scenario)
    parser.add_argument("--event-id", help="source event id (used for dedupe key)")
    parser.add_argument("--trace-id", help="trace id for log correlation")
    parser.add_argument("--timeout-sec", type=float, default=default_timeout)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--evidence-dir", help="write request/response evidence JSON files to this directory")

    parser.add_argument("--slack-signing-secret", help="Slack signing secret (or env N8N_SLACK_SIGNING_SECRET)")
    parser.add_argument("--zulip-token", help="Zulip outgoing token (or env N8N_ZULIP_OUTGOING_TOKEN)")
    parser.add_argument(
        "--zulip-tenant",
        help="Zulip tenant/realm (token map lookup / X-AIOPS-TENANT header etc; endpoint is usually /ingest/zulip)",
    )
    parser.add_argument("--mattermost-token", help="Mattermost outgoing token (or env N8N_MATTERMOST_OUTGOING_TOKEN)")
    parser.add_argument("--teams-test-token", help="Teams test token (or env N8N_TEAMS_TEST_TOKEN)")

    parser.add_argument("--cloudwatch-alarm-name", help="CloudWatch Alarm detail.alarmName override (default: ECS CPU High)")

    parser.add_argument("--text", help="override message text/content for slack/zulip/mattermost/teams (optional)")
    parser.add_argument("--zulip-stream", help="Zulip stream name (message.display_recipient). default: 0perational Qualification")
    parser.add_argument("--zulip-topic", help="Zulip topic (message.subject). default: ops")

    parser.add_argument("--feedback-endpoint", choices=["job", "preview"], default="job", help="feedback endpoint (default: job)")
    parser.add_argument("--job-id", help="feedback/job_id (required when --source feedback)")
    parser.add_argument(
        "--resolved",
        choices=["true", "false"],
        help="feedback/resolved (required when --source feedback)",
    )
    parser.add_argument("--smile-score", type=int, help="feedback/smile_score (required when --source feedback)")
    parser.add_argument("--comment", help="feedback/comment (optional)")

    args = parser.parse_args(argv)

    source = str(args.source).strip().lower()
    scenario = str(args.scenario).strip().lower()
    validate_source_scenario(source, scenario, scenarios_doc)

    scenario_def = scenarios.get(scenario)
    if not isinstance(scenario_def, dict):
        raise ValueError(f"scenario not found in stub_scenarios.json: {scenario}")
    expected = str(scenario_def.get("expected") or "").strip()
    if not expected:
        raise ValueError(f"invalid stub_scenarios.json: scenarios.{scenario}.expected is required")
    send_times = int(scenario_def.get("send_times") or 1)
    if send_times < 1:
        raise ValueError(f"invalid stub_scenarios.json: scenarios.{scenario}.send_times must be >= 1")

    zulip_tenant = env_or_arg(args.zulip_tenant, "N8N_ZULIP_TENANT")

    if not args.url:
        if not args.base_url:
            parser.error("--base-url is required when --url is not provided.")
        if source == "feedback":
            feedback_path = f"/feedback/{args.feedback_endpoint}"
            url = build_url(args.base_url, feedback_path, source)
        elif source == "zulip":
            url = build_url(args.base_url, args.path_template, source, tenant=zulip_tenant)
        else:
            url = build_url(args.base_url, args.path_template, source)
    else:
        url = args.url

    event_id = args.event_id or default_event_id(source)
    trace_id = args.trace_id or str(uuid.uuid4())

    slack_signing_secret = env_or_arg(args.slack_signing_secret, "N8N_SLACK_SIGNING_SECRET")
    zulip_token = env_or_arg(args.zulip_token, "N8N_ZULIP_OUTGOING_TOKEN")
    mattermost_token = env_or_arg(args.mattermost_token, "N8N_MATTERMOST_OUTGOING_TOKEN")
    teams_test_token = env_or_arg(args.teams_test_token, "N8N_TEAMS_TEST_TOKEN")

    feedback_resolved = None
    if args.resolved is not None:
        feedback_resolved = str(args.resolved).strip().lower() == "true"

    prepared = prepare_request(
        url=url,
        source=source,
        scenario=scenario,
        event_id=event_id,
        trace_id=trace_id,
        expected=expected,
        slack_signing_secret=slack_signing_secret,
        zulip_token=zulip_token,
        zulip_tenant=zulip_tenant,
        mattermost_token=mattermost_token,
        teams_test_token=teams_test_token,
        cloudwatch_alarm_name=args.cloudwatch_alarm_name,
        message_text=args.text,
        zulip_stream=args.zulip_stream,
        zulip_topic=args.zulip_topic,
        feedback_job_id=args.job_id,
        feedback_resolved=feedback_resolved,
        feedback_smile_score=args.smile_score,
        feedback_comment=args.comment,
    )

    run_id = f"{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}_{source}_{scenario}_{slugify(str(event_id))}"
    evidence_dir = Path(args.evidence_dir).resolve() if args.evidence_dir else None

    if args.dry_run:
        print(json.dumps({"url": prepared.url, "headers": prepared.headers, "body": json.loads(prepared.body_text)}, ensure_ascii=False, indent=2))
        return 0

    all_ok = True

    for idx in range(1, send_times + 1):
        status, resp_body, resp_headers, elapsed_ms = send_once(prepared, timeout_sec=args.timeout_sec)
        ok, expected_label = check_expected(expected, status)
        all_ok = all_ok and ok

        print(f"[{idx}/{send_times}] source={source} scenario={scenario} expected={expected_label} status={status} elapsed_ms={elapsed_ms}")
        if evidence_dir:
            write_evidence(
                evidence_dir=evidence_dir,
                run_id=run_id,
                index=idx,
                prepared=prepared,
                status=status,
                resp_body=resp_body,
                resp_headers=resp_headers,
                elapsed_ms=elapsed_ms,
            )

    return 0 if all_ok else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except Exception as e:
        print(f"[error] {e}", file=sys.stderr)
        raise SystemExit(1)
