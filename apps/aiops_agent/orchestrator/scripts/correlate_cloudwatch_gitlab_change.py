#!/usr/bin/env python3
"""CloudWatch アラーム時刻を基準に GitLab の構成変更を相関する。"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib import parse, request


DESIRED_STATE_RE = re.compile(r"^\s*desired_state\s*:\s*([^\s#]+)", re.IGNORECASE)


def parse_timestamp(value: str) -> datetime:
    text = value.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def event_context(payload: dict[str, Any]) -> tuple[datetime, str]:
    if "body" in payload and "detail" not in payload:
        wrapped = payload.get("body")
        if isinstance(wrapped, str):
            payload = json.loads(wrapped)
        elif isinstance(wrapped, dict):
            payload = wrapped
    detail = payload.get("detail") if isinstance(payload.get("detail"), dict) else {}
    state = detail.get("state") if isinstance(detail.get("state"), dict) else {}
    timestamp = str(state.get("timestamp") or payload.get("time") or "").strip()
    if not timestamp:
        raise ValueError("CloudWatch event does not contain time or detail.state.timestamp")
    alarm_name = str(detail.get("alarmName") or "")
    return parse_timestamp(timestamp), alarm_name


def desired_state_change(diff_text: str) -> tuple[str | None, str | None]:
    before = None
    after = None
    for line in diff_text.splitlines():
        if line.startswith("-") and not line.startswith("---"):
            matched = DESIRED_STATE_RE.match(line[1:])
            if matched:
                before = matched.group(1).lower()
        elif line.startswith("+") and not line.startswith("+++"):
            matched = DESIRED_STATE_RE.match(line[1:])
            if matched:
                after = matched.group(1).lower()
    return before, after


@dataclass
class GitLabClient:
    api_base: str
    token: str
    timeout: int = 30

    def get(self, path: str, query: dict[str, str] | None = None) -> Any:
        url = f"{self.api_base.rstrip('/')}{path}"
        if query:
            url = f"{url}?{parse.urlencode(query)}"
        req = request.Request(url, headers={"PRIVATE-TOKEN": self.token, "Accept": "application/json"})
        with request.urlopen(req, timeout=self.timeout) as response:
            return json.loads(response.read().decode("utf-8"))


def correlate(
    client: GitLabClient,
    *,
    project: str,
    config_path: str,
    alarm_time: datetime,
    alarm_name: str,
    lookback_minutes: int,
) -> dict[str, Any]:
    encoded_project = parse.quote(project, safe="")
    since = alarm_time - timedelta(minutes=lookback_minutes)
    until = alarm_time + timedelta(minutes=5)
    commits = client.get(
        f"/projects/{encoded_project}/repository/commits",
        {
            "path": config_path,
            "all": "true",
            "since": since.isoformat().replace("+00:00", "Z"),
            "until": until.isoformat().replace("+00:00", "Z"),
            "per_page": "100",
        },
    )
    if not isinstance(commits, list):
        raise ValueError("GitLab commits response is not an array")

    candidates: list[dict[str, Any]] = []
    for commit in commits:
        commit_id = str(commit.get("id") or "")
        committed_at_raw = str(commit.get("committed_date") or commit.get("created_at") or "")
        if not commit_id or not committed_at_raw:
            continue
        committed_at = parse_timestamp(committed_at_raw)
        delta_seconds = abs((alarm_time - committed_at).total_seconds())
        diffs = client.get(f"/projects/{encoded_project}/repository/commits/{parse.quote(commit_id, safe='')}/diff")
        if not isinstance(diffs, list):
            continue
        for changed in diffs:
            new_path = str(changed.get("new_path") or "")
            old_path = str(changed.get("old_path") or "")
            if config_path not in {new_path, old_path}:
                continue
            before, after = desired_state_change(str(changed.get("diff") or ""))
            score = max(0, 60 - int(delta_seconds // 60))
            if before in (None, "up") and after == "down":
                score += 40
            if "sulu" in alarm_name.lower():
                score += 10
            candidates.append(
                {
                    "commit_id": commit_id,
                    "short_id": str(commit.get("short_id") or commit_id[:8]),
                    "title": str(commit.get("title") or ""),
                    "author_name": str(commit.get("author_name") or ""),
                    "committed_at": committed_at.isoformat().replace("+00:00", "Z"),
                    "delta_seconds": int(delta_seconds),
                    "path": config_path,
                    "desired_state": {"from": before, "to": after},
                    "score": score,
                }
            )

    candidates.sort(key=lambda item: (item["score"], -item["delta_seconds"]), reverse=True)
    selected = candidates[0] if candidates else None
    probable = bool(
        selected
        and selected["desired_state"].get("from") in (None, "up")
        and selected["desired_state"].get("to") == "down"
    )
    return {
        "ok": selected is not None,
        "source": "cloudwatch_gitlab_correlation",
        "alarm": {"name": alarm_name, "timestamp": alarm_time.isoformat().replace("+00:00", "Z")},
        "gitlab": {"project": project, "path": config_path, "lookback_minutes": lookback_minutes},
        "probable_cause_found": probable,
        "selected": selected,
        "candidates": candidates[:10],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-file", type=Path, required=True)
    parser.add_argument("--gitlab-api", required=True)
    parser.add_argument("--project", required=True)
    parser.add_argument("--config-path", default="demo/sulu-runtime.yml")
    parser.add_argument("--token-env", default="GITLAB_TOKEN")
    parser.add_argument("--lookback-minutes", type=int, default=30)
    parser.add_argument("--timeout-sec", type=int, default=30)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if args.lookback_minutes < 1:
        parser.error("--lookback-minutes must be >= 1")
    payload = json.loads(args.event_file.read_text(encoding="utf-8"))
    alarm_time, alarm_name = event_context(payload)
    if args.dry_run:
        result = {
            "ok": True,
            "dry_run": True,
            "planned_query": {
                "project": args.project,
                "path": args.config_path,
                "alarm_name": alarm_name,
                "alarm_timestamp": alarm_time.isoformat().replace("+00:00", "Z"),
                "lookback_minutes": args.lookback_minutes,
            },
        }
    else:
        token = os.environ.get(args.token_env, "")
        if not token:
            parser.error(f"environment variable {args.token_env} is required")
        result = correlate(
            GitLabClient(args.gitlab_api, token, args.timeout_sec),
            project=args.project,
            config_path=args.config_path,
            alarm_time=alarm_time,
            alarm_name=alarm_name,
            lookback_minutes=args.lookback_minutes,
        )
        if not result["probable_cause_found"]:
            result["error"] = "desired_state (missing/up) -> down change was not found in the correlation window"

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get("ok") and (args.dry_run or result.get("probable_cause_found")) else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"[correlation] error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
