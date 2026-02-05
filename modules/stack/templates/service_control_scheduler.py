import json
import math
import os
from datetime import date, datetime, timedelta, timezone

import boto3

ecs = boto3.client("ecs")
ssm = boto3.client("ssm")
cloudwatch = boto3.client("cloudwatch")

CLUSTER_ARN = os.environ["CLUSTER_ARN"]
SERVICE_CONTROL_SERVICE_KEYS = json.loads(os.environ.get("SERVICE_CONTROL_SERVICE_KEYS", "[]"))
SERVICE_CONTROL_SCHEDULE_SERVICES = json.loads(os.environ.get("SERVICE_CONTROL_SCHEDULE_SERVICES", "[]"))
SERVICE_CONTROL_NAME_PREFIX = os.environ.get("SERVICE_CONTROL_NAME_PREFIX", "")
SERVICE_CONTROL_SSM_PATH = os.environ.get("SERVICE_CONTROL_SSM_PATH", "")
SERVICE_ARNS_SSM_PARAMETER = os.environ.get("SERVICE_ARNS_SSM_PARAMETER", "")
AUTOSTOP_ALARMS_SSM_PARAMETER = os.environ.get("SERVICE_CONTROL_AUTOSTOP_ALARMS_SSM_PARAMETER", "")
SERVICE_CONTROL_AUTOSTOP_POLICY_ARNS_RAW = json.loads(os.environ.get("SERVICE_CONTROL_AUTOSTOP_POLICY_ARNS") or "{}")
START_DESIRED = int(os.environ.get("START_DESIRED", "1"))
JST_OFFSET = int(os.environ.get("SERVICE_CONTROL_SCHEDULE_TIMEZONE_OFFSET", "9"))
SERVICE_CONTROL_AUTOSTOP_ALARM_REGION = os.environ.get("SERVICE_CONTROL_AUTOSTOP_ALARM_REGION", "")
SERVICE_CONTROL_AUTOSTOP_WAF_NAME = os.environ.get("SERVICE_CONTROL_AUTOSTOP_WAF_NAME", "")
SERVICE_CONTROL_AUTOSTOP_ALARM_PERIOD_SECONDS = int(os.environ.get("SERVICE_CONTROL_AUTOSTOP_ALARM_PERIOD_SECONDS", "300"))
SERVICE_CONTROL_AUTOSTOP_ALARM_PERIOD_MINUTES = SERVICE_CONTROL_AUTOSTOP_ALARM_PERIOD_SECONDS / 60
SERVICE_CONTROL_AUTOSTOP_ALARM_NAMESPACE = os.environ.get("SERVICE_CONTROL_AUTOSTOP_ALARM_NAMESPACE", "AWS/WAFV2")
SERVICE_CONTROL_AUTOSTOP_ALARM_METRIC_NAME = os.environ.get("SERVICE_CONTROL_AUTOSTOP_ALARM_METRIC_NAME", "CountedRequests")
SERVICE_CONTROL_AUTOSTOP_ALARM_STATISTIC = os.environ.get("SERVICE_CONTROL_AUTOSTOP_ALARM_STATISTIC", "Sum")
SERVICE_CONTROL_AUTOSTOP_ALARM_COMPARISON_OPERATOR = os.environ.get("SERVICE_CONTROL_AUTOSTOP_ALARM_COMPARISON_OPERATOR", "LessThanOrEqualToThreshold")
SERVICE_CONTROL_AUTOSTOP_ALARM_THRESHOLD = float(os.environ.get("SERVICE_CONTROL_AUTOSTOP_ALARM_THRESHOLD", "0"))
SERVICE_CONTROL_AUTOSTOP_ALARM_TREAT_MISSING_DATA = os.environ.get("SERVICE_CONTROL_AUTOSTOP_ALARM_TREAT_MISSING_DATA", "breaching")
HOLIDAY_CACHE = {}


def _parse_cluster_arn(cluster_arn):
    try:
        parts = cluster_arn.split(":")
        region = parts[3] if len(parts) > 3 else ""
        account = parts[4] if len(parts) > 4 else ""
        cluster = parts[5].split("/", 1)[1] if len(parts) > 5 and "/" in parts[5] else parts[5] if len(parts) > 5 else ""
        return region, account, cluster
    except Exception:  # pylint: disable=broad-except
        return "", "", ""


REGION, ACCOUNT_ID, CLUSTER_NAME = _parse_cluster_arn(CLUSTER_ARN)
NAME_PREFIX = (
    SERVICE_CONTROL_NAME_PREFIX
    or (CLUSTER_NAME[:-4] if CLUSTER_NAME.endswith("-ecs") else CLUSTER_NAME)
).strip("-")


def _service_arn(service_key):
    if not REGION or not ACCOUNT_ID or not CLUSTER_NAME or not service_key:
        return ""
    return f"arn:aws:ecs:{REGION}:{ACCOUNT_ID}:service/{CLUSTER_NAME}/{NAME_PREFIX}-{service_key}"


def _load_service_arns():
    if SERVICE_ARNS_SSM_PARAMETER:
        try:
            resp = ssm.get_parameter(Name=SERVICE_ARNS_SSM_PARAMETER)
            return json.loads(resp["Parameter"]["Value"])
        except ssm.exceptions.ParameterNotFound:
            print({"warning": "service arns parameter not found", "parameter": SERVICE_ARNS_SSM_PARAMETER})
        except Exception as exc:  # pylint: disable=broad-except
            print({"warning": "failed to load service arns", "parameter": SERVICE_ARNS_SSM_PARAMETER, "error": str(exc)})
    keys = SERVICE_CONTROL_SERVICE_KEYS or SERVICE_CONTROL_SCHEDULE_SERVICES
    return {svc: _service_arn(svc) for svc in keys}


def _load_autostop_policies():
    if SERVICE_CONTROL_AUTOSTOP_POLICY_ARNS_RAW:
        return SERVICE_CONTROL_AUTOSTOP_POLICY_ARNS_RAW
    if AUTOSTOP_ALARMS_SSM_PARAMETER:
        try:
            resp = ssm.get_parameter(Name=AUTOSTOP_ALARMS_SSM_PARAMETER)
            raw = json.loads(resp["Parameter"]["Value"])
            return {svc: cfg.get("policy_arn") for svc, cfg in raw.items() if cfg.get("policy_arn")}
        except ssm.exceptions.ParameterNotFound:
            print({"warning": "autostop alarms parameter not found", "parameter": AUTOSTOP_ALARMS_SSM_PARAMETER})
        except Exception as exc:  # pylint: disable=broad-except
            print({"warning": "failed to load autostop alarms", "parameter": AUTOSTOP_ALARMS_SSM_PARAMETER, "error": str(exc)})
    return {}


SERVICE_ARNS = _load_service_arns()
SERVICE_CONTROL_AUTOSTOP_POLICIES = _load_autostop_policies()


DEFAULT_SCHEDULE = {
    "enabled": False,
    "start_time": "17:00",
    "stop_time": "22:00",
    "weekday_start_time": "17:00",
    "weekday_stop_time": "22:00",
    "holiday_start_time": "08:00",
    "holiday_stop_time": "23:00",
    "idle_minutes": 60,
}
DEFAULT_START_MINUTES = 17 * 60
DEFAULT_STOP_MINUTES = 22 * 60


def _nth_weekday(year, month, weekday, nth):
    first = date(year, month, 1)
    offset = (weekday - first.weekday() + 7) % 7
    return first + timedelta(days=offset + 7 * (nth - 1))


def _japan_equinox(year, spring=True):
    base = 20.8431 if spring else 23.2488
    day = math.floor(base + 0.242194 * (year - 1980) - math.floor((year - 1980) / 4))
    month = 3 if spring else 9
    return date(year, month, day)


def _base_japan_holidays(year):
    holidays = {
        date(year, 1, 1),
        date(year, 2, 11),
        _japan_equinox(year, True),
        date(year, 4, 29),
        date(year, 5, 3),
        date(year, 5, 4),
        date(year, 5, 5),
        _japan_equinox(year, False),
        date(year, 11, 3),
        date(year, 11, 23),
    }
    holidays.add(_nth_weekday(year, 1, 0, 2) if year >= 2000 else date(year, 1, 15))
    if year >= 2020:
        holidays.add(date(year, 2, 23))
    elif 1989 <= year <= 2018:
        holidays.add(date(year, 12, 23))
    if year >= 2003:
        holidays.add(_nth_weekday(year, 7, 0, 3))
    elif year >= 1996:
        holidays.add(date(year, 7, 20))
    if year >= 2016:
        holidays.add(date(year, 8, 11))
    if year >= 2003:
        holidays.add(_nth_weekday(year, 9, 0, 3))
    elif year >= 1966:
        holidays.add(date(year, 9, 15))
    holidays.add(_nth_weekday(year, 10, 0, 2) if year >= 2000 else date(year, 10, 10))
    return holidays


def _apply_substitute_holidays(holidays):
    substitutes = set()
    for holiday in sorted(holidays):
        if holiday.weekday() != 6:
            continue
        candidate = holiday + timedelta(days=1)
        while candidate in holidays or candidate in substitutes:
            candidate += timedelta(days=1)
        substitutes.add(candidate)
    return substitutes


def _apply_bridge_holidays(holidays):
    bridges = set()
    for holiday in holidays:
        candidate = holiday + timedelta(days=1)
        if candidate in holidays or candidate.weekday() >= 5:
            continue
        if candidate + timedelta(days=1) in holidays:
            bridges.add(candidate)
    return bridges


def _japan_holidays(year):
    if year in HOLIDAY_CACHE:
        return HOLIDAY_CACHE[year]
    holidays = _base_japan_holidays(year)
    holidays |= _apply_substitute_holidays(holidays)
    holidays |= _apply_bridge_holidays(holidays)
    holidays |= _apply_substitute_holidays(holidays)
    HOLIDAY_CACHE[year] = holidays
    return holidays


def _is_off_day(local_date):
    if local_date.weekday() >= 5:
        return True
    return local_date in _japan_holidays(local_date.year)



def _schedule_parameter_name(service_key):
    return f"{SERVICE_CONTROL_SSM_PATH.rstrip('/')}/{service_key}/schedule"


def _parse_time(value, fallback):
    try:
        parts = value.split(":")
        if len(parts) != 2:
            raise ValueError
        hours = int(parts[0])
        minutes = int(parts[1])
        return hours * 60 + minutes
    except Exception:
        return fallback


def _get_schedule(service_key):
    if not SERVICE_CONTROL_SSM_PATH:
        return None
    try:
        resp = ssm.get_parameter(Name=_schedule_parameter_name(service_key))
        return json.loads(resp["Parameter"]["Value"])
    except ssm.exceptions.ParameterNotFound:
        return None
    except Exception:
        return None


def _put_schedule(service_key, schedule):
    if not SERVICE_CONTROL_SSM_PATH:
        return
    ssm.put_parameter(
        Name=_schedule_parameter_name(service_key),
        Value=json.dumps(schedule),
        Type="String",
        Overwrite=True,
    )


def _ensure_schedule(service_key):
    schedule = _get_schedule(service_key)
    if not schedule:
        schedule = dict(DEFAULT_SCHEDULE)
        _put_schedule(service_key, schedule)
        return schedule
    required_keys = [
        "start_time",
        "stop_time",
        "weekday_start_time",
        "weekday_stop_time",
        "holiday_start_time",
        "holiday_stop_time",
        "idle_minutes",
    ]
    needs_update = any(key not in schedule for key in required_keys)
    normalized = {**DEFAULT_SCHEDULE, **schedule}
    if needs_update:
        _put_schedule(service_key, normalized)
    return normalized


def _current_local_datetime():
    return datetime.now(timezone.utc) + timedelta(hours=JST_OFFSET)


def _time_window(schedule, local_dt):
    base_start_raw = schedule.get("start_time", DEFAULT_SCHEDULE["start_time"])
    base_stop_raw = schedule.get("stop_time", DEFAULT_SCHEDULE["stop_time"])
    base_start = _parse_time(base_start_raw, DEFAULT_START_MINUTES)
    base_stop = _parse_time(base_stop_raw, DEFAULT_STOP_MINUTES)
    if _is_off_day(local_dt.date()):
        start_raw = schedule.get("holiday_start_time") or base_start_raw
        stop_raw = schedule.get("holiday_stop_time") or base_stop_raw
    else:
        start_raw = schedule.get("weekday_start_time") or base_start_raw
        stop_raw = schedule.get("weekday_stop_time") or base_stop_raw
    start = _parse_time(start_raw, base_start)
    stop = _parse_time(stop_raw, base_stop)
    return start, stop


def _should_be_active(schedule, local_dt):
    if not schedule or not schedule.get("enabled"):
        return False
    current_minutes = local_dt.hour * 60 + local_dt.minute
    start, stop = _time_window(schedule, local_dt)
    if start <= stop:
        return start <= current_minutes < stop
    return current_minutes >= start or current_minutes < stop


def _describe_current_desired(service_arn):
    resp = ecs.describe_services(cluster=CLUSTER_ARN, services=[service_arn])
    services = resp.get("services") or []
    if not services:
        return None
    return services[0].get("desiredCount", 0)


def _update_desired(service_arn, desired):
    ecs.update_service(cluster=CLUSTER_ARN, service=service_arn, desiredCount=desired)


def _alarm_details(service_key):
    alarm_name = f"{NAME_PREFIX}-{service_key}-idle" if NAME_PREFIX else f"{service_key}-idle"
    rule_name = f"count-jp-{service_key}"
    return alarm_name, rule_name


def _update_idle_alarm(service_key, schedule, active):
    policy_arn = SERVICE_CONTROL_AUTOSTOP_POLICIES.get(service_key)
    if not policy_arn:
        return
    if not SERVICE_CONTROL_AUTOSTOP_WAF_NAME or not SERVICE_CONTROL_AUTOSTOP_ALARM_REGION:
        return
    alarm_name, rule_name = _alarm_details(service_key)
    idle_minutes = schedule.get("idle_minutes") if schedule else DEFAULT_SCHEDULE["idle_minutes"]
    try:
        idle_value = float(idle_minutes)
    except (TypeError, ValueError):
        idle_value = DEFAULT_SCHEDULE["idle_minutes"]
    evaluation_periods = max(1, math.ceil(idle_value / SERVICE_CONTROL_AUTOSTOP_ALARM_PERIOD_MINUTES))
    try:
        # WAF "CountedRequests" may not emit datapoints when there is no traffic.
        # When datapoints are missing, CloudWatch alarms can transition to ALARM (TreatMissingData),
        # but Application Auto Scaling may fail to execute the scaling action with:
        #   "Metric data points must be provided"
        # Use metric math to fill missing datapoints with 0 so the alarm always has data.
        metrics = [
            {
                "Id": "m1",
                "MetricStat": {
                    "Metric": {
                        "Namespace": SERVICE_CONTROL_AUTOSTOP_ALARM_NAMESPACE,
                        "MetricName": SERVICE_CONTROL_AUTOSTOP_ALARM_METRIC_NAME,
                        "Dimensions": [
                            {"Name": "WebACL", "Value": SERVICE_CONTROL_AUTOSTOP_WAF_NAME},
                            {"Name": "Rule", "Value": rule_name},
                            {"Name": "Region", "Value": SERVICE_CONTROL_AUTOSTOP_ALARM_REGION},
                        ],
                    },
                    "Period": SERVICE_CONTROL_AUTOSTOP_ALARM_PERIOD_SECONDS,
                    "Stat": SERVICE_CONTROL_AUTOSTOP_ALARM_STATISTIC,
                },
                "ReturnData": False,
            },
            {
                "Id": "e1",
                "Expression": "FILL(m1, 0)",
                "Label": "CountedRequestsFilled",
                "ReturnData": True,
            },
        ]
        cloudwatch.put_metric_alarm(
            AlarmName=alarm_name,
            ComparisonOperator=SERVICE_CONTROL_AUTOSTOP_ALARM_COMPARISON_OPERATOR,
            EvaluationPeriods=evaluation_periods,
            Metrics=metrics,
            Threshold=SERVICE_CONTROL_AUTOSTOP_ALARM_THRESHOLD,
            TreatMissingData=SERVICE_CONTROL_AUTOSTOP_ALARM_TREAT_MISSING_DATA,
            ActionsEnabled=not active,
            AlarmActions=[policy_arn],
        )
    except Exception as exc:  # pylint: disable=broad-except
        print({"service": service_key, "alarm": alarm_name, "error": str(exc)})


def handler(event, context):
    local_now = _current_local_datetime()
    for service_key in SERVICE_CONTROL_SCHEDULE_SERVICES:
        service_arn = SERVICE_ARNS.get(service_key)
        if not service_arn:
            continue
        schedule = _ensure_schedule(service_key)
        active = _should_be_active(schedule, local_now)
        _update_idle_alarm(service_key, schedule, active)
        if not active:
            continue
        service_arns = (
            list(service_arn.values())
            if isinstance(service_arn, dict)
            else [service_arn]
        )
        for actual_service_arn in service_arns:
            if not actual_service_arn:
                continue
            desired = START_DESIRED
            current = _describe_current_desired(actual_service_arn)
            if current is None:
                continue
            if current != desired:
                try:
                    _update_desired(actual_service_arn, desired)
                except Exception as exc:  # pylint: disable=broad-except
                    print({"service": service_key, "error": str(exc)})
    return {"status": "ok", "timestamp": datetime.now(timezone.utc).isoformat()}
