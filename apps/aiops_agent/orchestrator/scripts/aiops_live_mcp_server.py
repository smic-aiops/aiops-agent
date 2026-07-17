#!/usr/bin/env python3
import json, os, subprocess, sys, time, urllib.parse, urllib.request

REPO = os.environ.get("AIOPS_REPO", "/Users/goro-asahina/smic/smic-aiops/aiops-agent")
BASE = os.environ.get("AIOPS_N8N_URL", "https://aiops.n8n.smic-aiops.jp").rstrip("/")
_TOKEN_CACHE = None
_TRANSPORT = "jsonl"

def token():
    global _TOKEN_CACHE
    if _TOKEN_CACHE: return _TOKEN_CACHE
    value = os.environ.get("AIOPS_WORKFLOWS_TOKEN", "")
    if not value:
        value = subprocess.check_output(["terraform", "output", "-raw", "N8N_WORKFLOWS_TOKEN"], cwd=REPO, text=True).strip()
    _TOKEN_CACHE = value
    return value

def call(method, path, body=None, query=None):
    url = BASE + "/webhook/" + path
    if query: url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"Authorization":"Bearer "+token(), "Content-Type":"application/json"})
    with urllib.request.urlopen(req, timeout=30) as response:
        raw = response.read()
        if not raw.strip():
            return {"ok": False, "empty": True, "status_code": response.status}
        try:
            return json.loads(raw)
        except json.JSONDecodeError as exc:
            preview = raw[:200].decode("utf-8", "replace")
            raise RuntimeError(f"n8n returned non-JSON HTTP {response.status}: {preview!r}") from exc

def send(obj):
    raw=json.dumps(obj, ensure_ascii=False).encode()
    if _TRANSPORT == "content-length":
        sys.stdout.buffer.write(f"Content-Length: {len(raw)}\r\n\r\n".encode()+raw)
    else:
        sys.stdout.buffer.write(raw+b"\n")
    sys.stdout.buffer.flush()

def result(req_id, value): send({"jsonrpc":"2.0","id":req_id,"result":value})

def progress(progress_token, value, message):
    if progress_token is not None:
        send({"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":progress_token,"progress":value,"message":message}})

def run_aiops(args, progress_token):
    trace=str(args.get("trace_id") or "").strip()
    request=str(args.get("request") or "").strip()
    if not trace:
        if not request: raise ValueError("request is required when trace_id is not provided")
        started=call("POST","aiops/ui/start",{"request":request,"realm":args.get("realm","aiops")})
        trace=started["trace_id"]
    after=max(0,int(args.get("after",0)))
    events=[]
    timeout_seconds=max(0,int(args.get("timeout_seconds",0)))
    deadline=time.monotonic()+timeout_seconds if timeout_seconds else None
    heartbeat_seconds=min(max(int(args.get("heartbeat_seconds",15)),5),60)
    next_heartbeat=time.monotonic()+heartbeat_seconds
    transient_errors=0
    progress_value=after
    progress(progress_token,progress_value,f"AIOps trace {trace} の監視を開始しました")
    while deadline is None or time.monotonic()<deadline:
        try:
            batch=call("GET","aiops/ui/events",query={"trace_id":trace,"after":after}).get("events",[])
            for event in batch:
                after=max(after,int(event["event_id"])); events.append(event); progress_value=max(progress_value+1,after)
                progress(progress_token,progress_value,event["message"])
            state=call("GET","aiops/ui/result",query={"trace_id":trace})
            transient_errors=0
        except Exception as exc:
            transient_errors+=1; progress_value+=1
            progress(progress_token,progress_value,f"一時的な取得エラーです。再試行します ({transient_errors}/10): {exc}")
            if transient_errors>=10:
                return {"trace_id":trace,"status":"error","events":events,"error":f"progress polling failed after 10 retries: {exc}"}
            time.sleep(min(transient_errors,5))
            continue
        if not state.get("empty"):
            item=state.get("result") or {}
            if item.get("status") in ("success","completed","failed","error","cancelled","canceled"):
                return {"trace_id":trace,"status":item.get("status"),"events":events,"result":item}
        now=time.monotonic()
        if now>=next_heartbeat:
            progress_value+=1
            progress(progress_token,progress_value,f"AIOps trace {trace} は実行中です（新しいイベントを待機しています）")
            next_heartbeat=now+heartbeat_seconds
        time.sleep(1)
    return {"trace_id":trace,"status":"timeout","events":events,"timeout_seconds":timeout_seconds}

def monitor_aiops(args, progress_token):
    duration_seconds=max(0,int(args.get("duration_seconds",600)))
    replay_seconds=min(max(0,int(args.get("replay_seconds",60))),3600)
    heartbeat_seconds=min(max(int(args.get("heartbeat_seconds",15)),5),60)
    deadline=time.monotonic()+duration_seconds if duration_seconds else None
    next_heartbeat=time.monotonic()+heartbeat_seconds
    after=max(0,int(args.get("after",0)))
    events=[]
    progress_value=after
    transient_errors=0
    progress(progress_token,progress_value,"全AIノードとチャネル会話の監視を開始しました")
    while deadline is None or time.monotonic()<deadline:
        try:
            initial_replay=replay_seconds>0
            state=call("GET","aiops/ui/events",query={"scope":"all","after":after,"since_seconds":replay_seconds})
            batch=state.get("events",[])
            cursor=int(state.get("cursor",after) or after)
            latest_cursor=int(state.get("latest_cursor",cursor) or cursor)
            after=max(after,latest_cursor if initial_replay and not batch else cursor)
            replay_seconds=0
            for event in batch:
                if event.get("phase") not in ("ai_node","channel_message","workflow_error"):
                    continue
                events.append(event); progress_value=max(progress_value+1,int(event.get("event_id",0) or 0))
                progress(progress_token,progress_value,event.get("message") or "AIOpsイベント")
            transient_errors=0
        except Exception as exc:
            transient_errors+=1; progress_value+=1
            progress(progress_token,progress_value,f"監視イベントの取得エラーです。再試行します ({transient_errors}/10): {exc}")
            if transient_errors>=10:
                return {"status":"error","events":events,"cursor":after,"error":f"monitor polling failed after 10 retries: {exc}"}
            time.sleep(min(transient_errors,5))
            continue
        now=time.monotonic()
        if now>=next_heartbeat:
            progress_value+=1
            progress(progress_token,progress_value,f"AIOps監視は継続中です（取得イベント {len(events)} 件）")
            next_heartbeat=now+heartbeat_seconds
        time.sleep(1)
    return {"status":"completed","events":events,"cursor":after,"duration_seconds":duration_seconds}

def tool_definitions():
    return [
        {"name":"run_aiops","description":"Run n8n AIOps and stream auditable progress events to Codex. By default it waits until a terminal result without a time limit; pass trace_id to resume monitoring an existing run.","inputSchema":{"type":"object","properties":{"request":{"type":"string","description":"AIOps request. Required when starting a new trace."},"realm":{"type":"string","default":"aiops"},"trace_id":{"type":"string","description":"Existing trace to resume without starting a duplicate run."},"after":{"type":"integer","default":0,"minimum":0},"timeout_seconds":{"type":"integer","default":0,"minimum":0,"maximum":86400,"description":"0 waits indefinitely; a positive value enables an explicit timeout."},"heartbeat_seconds":{"type":"integer","default":15,"minimum":5,"maximum":60}},"anyOf":[{"required":["request"]},{"required":["trace_id"]}]}},
        {"name":"monitor_aiops","description":"Monitor all n8n AI nodes and external channel messages without starting a new AIOps run.","inputSchema":{"type":"object","properties":{"duration_seconds":{"type":"integer","default":600,"minimum":0,"maximum":86400,"description":"Monitoring duration; 0 waits indefinitely."},"replay_seconds":{"type":"integer","default":60,"minimum":0,"maximum":3600,"description":"Replay recent events when monitoring starts."},"after":{"type":"integer","default":0,"minimum":0},"heartbeat_seconds":{"type":"integer","default":15,"minimum":5,"maximum":60}}}},
    ]

def main():
    global _TRANSPORT
    while True:
        line=sys.stdin.buffer.readline()
        if not line: break
        if line.lower().startswith(b"content-length:"):
            _TRANSPORT="content-length"
            length=int(line.split(b":",1)[1]); sys.stdin.buffer.readline(); msg=json.loads(sys.stdin.buffer.read(length))
        else:
            _TRANSPORT="jsonl"
            if not line.strip(): continue
            msg=json.loads(line)
        method=msg.get("method"); rid=msg.get("id")
        try:
            if method=="initialize": result(rid,{"protocolVersion":"2025-03-26","capabilities":{"tools":{}},"serverInfo":{"name":"aiops-live","version":"0.1.0"}})
            elif method=="tools/list": result(rid,{"tools":tool_definitions()})
            elif method=="tools/call":
                p=msg.get("params",{}); name=p.get("name"); args=p.get("arguments",{}); token_value=(p.get("_meta") or {}).get("progressToken")
                if name=="monitor_aiops": value=monitor_aiops(args,token_value)
                else: value=run_aiops(args,token_value)
                result(rid,{"content":[{"type":"text","text":json.dumps(value,ensure_ascii=False)}],"isError":value.get("status") in ("failed","error","timeout","cancelled","canceled")})
            elif rid is not None: result(rid,{})
        except Exception as exc:
            send({"jsonrpc":"2.0","id":rid,"error":{"code":-32000,"message":str(exc)}})

def dry_run():
    print(json.dumps({
        "ok": True,
        "mode": "dry-run",
        "base_url": BASE,
        "repo": REPO,
        "default_timeout_seconds": 0,
        "heartbeat_seconds": 15,
        "resume_by_trace_id": True,
        "monitor_all_ai_nodes": True,
        "network_requested": False,
    }, ensure_ascii=False))

if __name__=="__main__":
    if "--dry-run" in sys.argv:
        dry_run()
    else:
        main()
