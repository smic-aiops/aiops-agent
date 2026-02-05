import base64
import json
import os


NAME_PREFIX = os.environ.get("NAME_PREFIX", "").strip("-")
ENABLED_SERVICES = set(json.loads(os.environ.get("ENABLED_SERVICES", "[]") or "[]"))

SERVICE_ATTR_KEYS = {
    "aws.ecs.service.name",
    "aws.ecs.task.definition.family",
    "ServiceName",
    "TaskDefinitionFamily",
    "service.name",
    "serviceName",
}
CANARY_ATTR_KEYS = {
    "aws.synthetics.canary.name",
    "CanaryName",
    "canary.name",
    "canary_name",
}
NAMESPACE_ATTR_KEYS = {
    "aws.namespace",
    "aws.cloudwatch.namespace",
    "aws.cloudwatch.metric.namespace",
}


def _build_allowed_service_names():
    allowed = set()
    for svc in ENABLED_SERVICES:
        if not svc:
            continue
        allowed.add(str(svc))
        if NAME_PREFIX:
            allowed.add(f"{NAME_PREFIX}-{svc}")
    return allowed


ALLOWED_SERVICE_NAMES = _build_allowed_service_names()
ALLOW_SYNTHETICS = (
    "synthetics" in ALLOWED_SERVICE_NAMES
    or (NAME_PREFIX and f"{NAME_PREFIX}-synthetics" in ALLOWED_SERVICE_NAMES)
)


def _attr_value(value):
    if not isinstance(value, dict):
        return None
    for key in ("stringValue", "string_value", "intValue", "doubleValue", "boolValue"):
        if key in value and value[key] not in (None, ""):
            return str(value[key])
    return None


def _extract_service_from_otlp(payload):
    resource_metrics = payload.get("resourceMetrics") or payload.get("resource_metrics") or []
    for resource_metric in resource_metrics:
        attrs = (resource_metric.get("resource") or {}).get("attributes") or []
        for attr in attrs:
            if attr.get("key") in SERVICE_ATTR_KEYS.union(CANARY_ATTR_KEYS):
                value = _attr_value(attr.get("value"))
                if value:
                    return value
    return None


def _extract_service_from_json(payload):
    dimensions = payload.get("dimensions")
    if isinstance(dimensions, dict):
        for key in (
            "ServiceName",
            "service",
            "serviceName",
            "TaskDefinitionFamily",
            "CanaryName",
            "canary_name",
            "canaryName",
        ):
            value = dimensions.get(key)
            if value:
                return str(value)
    return None


def _extract_service_name(payload):
    return _extract_service_from_otlp(payload) or _extract_service_from_json(payload)


def _extract_namespace_from_otlp(payload):
    resource_metrics = payload.get("resourceMetrics") or payload.get("resource_metrics") or []
    for resource_metric in resource_metrics:
        attrs = (resource_metric.get("resource") or {}).get("attributes") or []
        for attr in attrs:
            if attr.get("key") in NAMESPACE_ATTR_KEYS:
                value = _attr_value(attr.get("value"))
                if value:
                    return value
    return None


def _extract_namespace(payload):
    namespace = payload.get("namespace")
    if namespace:
        return str(namespace)
    return _extract_namespace_from_otlp(payload)


def _should_keep(service_name, namespace):
    if not ALLOWED_SERVICE_NAMES:
        return True
    if service_name in ALLOWED_SERVICE_NAMES:
        return True
    if ALLOW_SYNTHETICS and namespace == "CloudWatchSynthetics":
        return True
    return False


def handler(event, context):
    records_out = []
    for record in event.get("records", []):
        data = record.get("data")
        record_id = record.get("recordId", "unknown")
        if not data:
            records_out.append({"recordId": record_id, "result": "Dropped", "data": ""})
            continue
        try:
            payload = json.loads(base64.b64decode(data))
        except Exception:
            records_out.append({"recordId": record_id, "result": "Ok", "data": data})
            continue
        service_name = _extract_service_name(payload)
        namespace = _extract_namespace(payload)
        result = "Ok" if _should_keep(service_name, namespace) else "Dropped"
        records_out.append({"recordId": record_id, "result": result, "data": data})
    return {"records": records_out}
