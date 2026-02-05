#!/usr/bin/env python3
import argparse
import json
import os
import sys
import time
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib import request, error


def read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def repo_root() -> Path:
    # __file__ = apps/aiops_agent/scripts/run_dq_scenarios.py
    # parents[3] = repo root
    return Path(__file__).resolve().parents[3]


def default_scenarios_path() -> Path:
    return repo_root() / "apps" / "aiops_agent" / "data" / "default" / "dq" / "scenarios" / "representative_scenarios.json"


def policy_dir() -> Path:
    # Prefer the SSoT under apps/aiops_agent/data/default/policy/.
    # Keep backward compatibility if a legacy apps/aiops_agent/policy/ exists.
    legacy = repo_root() / "apps" / "aiops_agent" / "policy"
    if legacy.exists():
        return legacy
    return repo_root() / "apps" / "aiops_agent" / "data" / "default" / "policy"


def build_policy_context() -> Dict[str, Any]:
    root = policy_dir()
    decision = read_json(root / "decision_policy_ja.json")
    approval = read_json(root / "approval_policy_ja.json")
    grammar = read_json(root / "interaction_grammar_ja.json")
    ingest = read_json(root / "ingest_policy_ja.json")
    source_caps = read_json(root / "source_capabilities_ja.json")

    ctx = dict(decision)
    ctx["interaction_grammar"] = grammar
    ctx["approval_policy_doc"] = approval
    ctx["ingest_policy"] = ingest
    ctx["source_capabilities"] = source_caps

    if "approval_policy" not in ctx:
        defaults = ctx.get("defaults") if isinstance(ctx.get("defaults"), dict) else {}
        if isinstance(defaults, dict) and defaults.get("approval_policy"):
            ctx["approval_policy"] = defaults.get("approval_policy")

    return ctx


def ensure_context_id(payload: Dict[str, Any]) -> None:
    context_id = payload.get("context_id")
    if context_id in (None, "", "auto"):
        payload["context_id"] = str(uuid.uuid4())


def ensure_trace_id(payload: Dict[str, Any]) -> None:
    event = payload.get("normalized_event")
    if not isinstance(event, dict):
        return
    trace_id = event.get("trace_id")
    if trace_id in (None, "", "auto"):
        event["trace_id"] = str(uuid.uuid4())


def scrub_sensitive(value: Any, keys: Optional[set] = None) -> Any:
    if keys is None:
        keys = {
            "approval_token",
            "token_nonce",
            "token",
            "api_key",
            "password",
            "secret",
            "authorization",
        }
    if isinstance(value, dict):
        scrubbed = {}
        for k, v in value.items():
            if str(k).lower() in keys:
                scrubbed[k] = "(masked)"
            else:
                scrubbed[k] = scrub_sensitive(v, keys)
        return scrubbed
    if isinstance(value, list):
        return [scrub_sensitive(v, keys) for v in value]
    return value


def post_json(url: str, payload: Dict[str, Any], timeout: float) -> Dict[str, Any]:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    with request.urlopen(req, timeout=timeout) as resp:
        data = resp.read()
        try:
            parsed = json.loads(data.decode("utf-8"))
        except Exception:
            parsed = {"_raw": data.decode("utf-8", errors="replace")}
        return {"status": resp.status, "body": parsed}


def validate_scenario(scenario: Dict[str, Any], allowed_next_actions: List[str]) -> List[str]:
    errors = []
    for key in ("id", "severity", "endpoint", "input", "expect"):
        if key not in scenario:
            errors.append(f"missing:{key}")
    expect = scenario.get("expect") if isinstance(scenario.get("expect"), dict) else {}
    allowed = expect.get("allowed_next_actions")
    if isinstance(allowed, list):
        invalid = [a for a in allowed if a not in allowed_next_actions]
        if invalid:
            errors.append("invalid_next_action:" + ",".join(invalid))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="DQ representative scenario runner")
    parser.add_argument(
        "--scenarios",
        default=str(default_scenarios_path()),
        help="Path to scenario JSON",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not call HTTP endpoints; print the request payloads that would be sent.",
    )
    parser.add_argument(
        "--mode",
        choices=["validate", "preview"],
        default="validate",
        help="validate: only schema checks, preview: call jobs/preview",
    )
    parser.add_argument("--output", help="JSONL output path (optional)")
    parser.add_argument("--orchestrator-base-url", help="Base URL for /jobs/preview (e.g. https://n8n.example.com/webhook)")
    parser.add_argument("--timeout", type=float, default=20.0, help="HTTP timeout seconds")

    args = parser.parse_args()

    scenarios_doc = read_json(Path(args.scenarios))
    scenarios = scenarios_doc.get("scenarios")
    if not isinstance(scenarios, list):
        print("ERROR: scenarios must be a list", file=sys.stderr)
        return 2

    policy_context = build_policy_context()
    allowed_next_actions = policy_context.get("taxonomy", {}).get("next_action_vocab", [])
    if not isinstance(allowed_next_actions, list):
        allowed_next_actions = []

    base_url = (
        args.orchestrator_base_url
        or os.getenv("N8N_ORCHESTRATOR_BASE_URL")
    )
    if not base_url:
        base_url = os.getenv("N8N_WEBHOOK_BASE_URL")
    if not base_url:
        n8n_base = os.getenv("N8N_API_BASE_URL") or os.getenv("N8N_PUBLIC_API_BASE_URL")
        if n8n_base:
            base_url = n8n_base.rstrip("/") + "/webhook"

    results = []

    for scenario in scenarios:
        start = time.time()
        sid = scenario.get("id", "unknown")
        endpoint = scenario.get("endpoint")
        payload = scenario.get("input") if isinstance(scenario.get("input"), dict) else {}

        # Validate structure
        errors = validate_scenario(scenario, allowed_next_actions)

        if payload.get("policy_context") == "auto" or "policy_context" not in payload:
            payload["policy_context"] = policy_context

        ensure_context_id(payload)
        ensure_trace_id(payload)

        status = "pass"
        response_body = None
        http_status = None

        if errors:
            status = "fail"
        elif args.mode == "preview":
            if endpoint != "jobs/preview":
                status = "skip"
            else:
                if args.dry_run:
                    if base_url:
                        url = base_url.rstrip("/") + "/" + endpoint.lstrip("/")
                    else:
                        url = ""
                    response_body = {
                        "dry_run": True,
                        "url": url,
                        "payload": scrub_sensitive(payload),
                    }
                    status = "skip"
                    errors.append("dry_run")
                    if not base_url:
                        errors.append("missing_base_url")
                elif not base_url:
                    status = "skip"
                    errors.append("missing_base_url")
                else:
                    url = base_url.rstrip("/") + "/" + endpoint.lstrip("/")
                    try:
                        response = post_json(url, payload, args.timeout)
                        http_status = response.get("status")
                        response_body = response.get("body")
                    except error.HTTPError as exc:
                        http_status = exc.code
                        response_body = {"_http_error": str(exc)}
                        status = "fail"
                    except Exception as exc:
                        response_body = {"_error": str(exc)}
                        status = "fail"

                if status != "fail" and not args.dry_run:
                    expect = scenario.get("expect") if isinstance(scenario.get("expect"), dict) else {}
                    must_have = expect.get("must_have_keys") if isinstance(expect.get("must_have_keys"), list) else []
                    missing = [k for k in must_have if not (isinstance(response_body, dict) and k in response_body)]
                    if missing:
                        errors.append("missing_keys:" + ",".join(missing))
                    allowed = expect.get("allowed_next_actions")
                    if isinstance(allowed, list) and isinstance(response_body, dict):
                        next_action = response_body.get("next_action")
                        if next_action and next_action not in allowed:
                            errors.append("next_action_unexpected:" + str(next_action))

                    if isinstance(response_body, dict):
                        preview_facts = response_body.get("preview_facts")
                        expected_source = expect.get("preview_facts_candidate_source")
                        if expected_source and isinstance(preview_facts, dict):
                            actual_source = preview_facts.get("candidate_source")
                            if actual_source != expected_source:
                                errors.append(
                                    "preview_candidate_source_unexpected:"
                                    + str(actual_source)
                                )

                        expected_rag_mode = expect.get("preview_facts_rag_mode")
                        if expected_rag_mode and isinstance(preview_facts, dict):
                            rag_context = preview_facts.get("rag_context") or {}
                            actual_mode = rag_context.get("mode")
                            if actual_mode != expected_rag_mode:
                                errors.append(
                                    "preview_rag_mode_unexpected:" + str(actual_mode)
                                )

                    if errors:
                        status = "fail"

        duration_ms = int((time.time() - start) * 1000)
        result = {
            "id": sid,
            "status": status,
            "mode": args.mode,
            "duration_ms": duration_ms,
            "errors": errors,
        }
        if http_status is not None:
            result["http_status"] = http_status
        if response_body is not None:
            result["response"] = scrub_sensitive(response_body)

        results.append(result)

    if args.output:
        out_path = Path(args.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open("w", encoding="utf-8") as f:
            for item in results:
                f.write(json.dumps(item, ensure_ascii=False) + "\n")
    else:
        print(json.dumps({"results": results}, ensure_ascii=False, indent=2))

    failed = [r for r in results if r["status"] == "fail"]
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
