import base64
import gzip
import io
import json


def _decode_record(data):
    raw = base64.b64decode(data)
    try:
        raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
    except OSError:
        pass
    return json.loads(raw.decode("utf-8"))


def _encode_events(payload):
    events = payload.get("logEvents") or []
    log_group = payload.get("logGroup")
    log_stream = payload.get("logStream")
    out = []
    for event in events:
        out.append(
            json.dumps(
                {
                    "timestamp": event.get("timestamp"),
                    "message": event.get("message"),
                    "log_group": log_group,
                    "log_stream": log_stream,
                }
            )
        )
    return ("\n".join(out) + "\n") if out else ""


def handler(event, context):
    output = []
    for record in event.get("records", []):
        try:
            payload = _decode_record(record["data"])
            data = _encode_events(payload)
            result = "Ok"
        except Exception:
            data = ""
            result = "ProcessingFailed"
        output.append(
            {
                "recordId": record["recordId"],
                "result": result,
                "data": base64.b64encode(data.encode("utf-8")).decode("utf-8"),
            }
        )
    return {"records": output}
