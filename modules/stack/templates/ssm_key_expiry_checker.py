import json
import os
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

import boto3


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name, "")
    if not raw:
        return default
    try:
        return int(raw)
    except Exception:
        return default


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name, "")
    if not raw:
        return default
    return raw.lower() in ("1", "true", "yes", "y", "on")


def _parse_iso_date(raw: str) -> date | None:
    raw = (raw or "").strip()
    if not raw:
        return None
    for fmt in ("%Y-%m-%d", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S"):
        try:
            dt = datetime.strptime(raw, fmt)
            return dt.date()
        except Exception:
            continue
    return None


def _parse_iso_datetime(raw: str) -> datetime | None:
    raw = (raw or "").strip()
    if not raw:
        return None
    parsed_date = _parse_iso_date(raw)
    if parsed_date is not None and raw == parsed_date.isoformat():
        return datetime(parsed_date.year, parsed_date.month, parsed_date.day, tzinfo=UTC)
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S"):
        try:
            dt = datetime.strptime(raw, fmt)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=UTC)
            return dt.astimezone(UTC)
        except Exception:
            continue
    return None


def _describe_parameters_by_path(ssm, path_prefix: str) -> list[dict]:
    params: list[dict] = []
    next_token: str | None = None
    while True:
        kwargs = {
            "ParameterFilters": [
                {"Key": "Path", "Option": "Recursive", "Values": [path_prefix]},
            ],
            "MaxResults": 50,
        }
        if next_token:
            kwargs["NextToken"] = next_token
        resp = ssm.describe_parameters(**kwargs)
        params.extend(resp.get("Parameters", []))
        next_token = resp.get("NextToken")
        if not next_token:
            break
    return params


def _get_expires_at_tag(ssm, name: str, tag_key: str) -> str | None:
    try:
        resp = ssm.list_tags_for_resource(ResourceType="Parameter", ResourceId=name)
    except Exception:
        return None
    for tag in resp.get("TagList", []) or []:
        if tag.get("Key") == tag_key:
            return tag.get("Value")
    return None


def _set_expires_at_tag(ssm, name: str, tag_key: str, expires_at: date) -> None:
    ssm.add_tags_to_resource(
        ResourceType="Parameter",
        ResourceId=name,
        Tags=[{"Key": tag_key, "Value": expires_at.isoformat()}],
    )


def handler(event, context):
    path_prefix = os.environ.get("SSM_PATH_PREFIX", "").strip()
    topic_arn = os.environ.get("SNS_TOPIC_ARN", "").strip()
    tag_key = os.environ.get("EXPIRES_AT_TAG_KEY", "expires_at").strip() or "expires_at"

    max_age_days = _env_int("MAX_AGE_DAYS", 90)
    warn_days = _env_int("WARN_DAYS", 30)
    manage_tag = _env_bool("MANAGE_EXPIRES_AT_TAG", True)

    if not path_prefix:
        raise RuntimeError("SSM_PATH_PREFIX is required")
    if not topic_arn:
        raise RuntimeError("SNS_TOPIC_ARN is required")
    if max_age_days <= 0:
        raise RuntimeError("MAX_AGE_DAYS must be positive")
    if warn_days < 0:
        raise RuntimeError("WARN_DAYS must be >= 0")

    ssm = boto3.client("ssm")
    sns = boto3.client("sns")

    now = datetime.now(UTC)
    warn_cutoff = now + timedelta(days=warn_days)
    tokyo = ZoneInfo("Asia/Tokyo")

    errors: list[str] = []
    candidates = _describe_parameters_by_path(ssm, path_prefix)

    items: list[dict] = []
    updated_tags = 0

    for p in candidates:
        name = p.get("Name") or ""
        if not name:
            continue
        ptype = (p.get("Type") or "").strip()
        # Only SecureString are considered "keys/secrets" here.
        if ptype != "SecureString":
            continue

        last_modified: datetime | None = p.get("LastModifiedDate")
        if not isinstance(last_modified, datetime):
            continue
        if last_modified.tzinfo is None:
            last_modified = last_modified.replace(tzinfo=UTC)

        desired_expires_at_dt = last_modified.astimezone(UTC) + timedelta(days=max_age_days)

        tag_raw = _get_expires_at_tag(ssm, name, tag_key)
        expires_at_dt = _parse_iso_datetime(tag_raw) or desired_expires_at_dt

        if manage_tag and _parse_iso_datetime(tag_raw) is None:
            try:
                _set_expires_at_tag(ssm, name, tag_key, expires_at_dt.date())
                updated_tags += 1
            except Exception as e:
                errors.append(f"tag_update_failed {name}: {type(e).__name__}: {e}")

        if expires_at_dt <= warn_cutoff:
            seconds_left = int((expires_at_dt - now).total_seconds())
            days_left = seconds_left // 86400
            items.append(
                {
                    "name": name,
                    "expires_at": expires_at_dt.astimezone(UTC).isoformat(),
                    "expires_at_jst": expires_at_dt.astimezone(tokyo).strftime("%Y/%m/%d %H:%M:%S"),
                    "days_left": days_left,
                    "last_modified": last_modified.astimezone(UTC).isoformat(),
                }
            )

    items.sort(key=lambda x: (x["expires_at"], x["name"]))

    summary = {
        "path_prefix": path_prefix,
        "max_age_days": max_age_days,
        "warn_days": warn_days,
        "checked_securestring_count": len([p for p in candidates if (p.get("Type") or "") == "SecureString"]),
        "near_expiry_count": len(items),
        "updated_expires_at_tags": updated_tags,
        "errors_count": len(errors),
        "generated_at": now.isoformat(),
    }

    should_notify = len(items) > 0 or len(errors) > 0
    if should_notify:
        lines: list[str] = []
        subject = "[重要] キーの有効期限が切れます"
        lines.append("管理者様")
        lines.append("キーの有効限がまもなく切れます。")
        lines.append("")
        if items:
            for it in items:
                lines.append(f"有効期限： {it['expires_at_jst']}")
                lines.append(f"SSMパラメータ： {it['name']}")
                lines.append("")
        else:
            subject = "[重要] キー有効期限チェックでエラー"

        if errors:
            lines.append("エラー:")
            for e in errors[:50]:
                lines.append(f"- {e}")
            if len(errors) > 50:
                lines.append(f"- ... ({len(errors) - 50} more)")
            lines.append("")

        lines.append("以下のコマンドを実行してリフレッシュしてください。")
        lines.append("% ./scripts/itsm/refresh_all_secure.sh")
        lines.append("% ./scripts/plan_apply_all_tfvars.sh")
        lines.append("")

        lines.append("Summary JSON:")
        lines.append(json.dumps(summary, ensure_ascii=False, separators=(",", ":")))

        sns.publish(TopicArn=topic_arn, Subject=subject[:100], Message="\n".join(lines))

    return {"ok": True, "summary": summary, "near_expiry": items, "errors": errors}
