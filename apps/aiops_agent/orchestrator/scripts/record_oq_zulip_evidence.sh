#!/usr/bin/env bash
set -euo pipefail

EXECUTE=false
REALM=""
EVIDENCE_DIR=""
KIND=""
CONTENT=""
STREAM_NAME="${N8N_OQ_ZULIP_STREAM:-0perational Qualification}"
TOPIC_NAME="${N8N_OQ_ZULIP_TOPIC:-scenario-2}"

usage() {
  cat <<'USAGE'
Usage: record_oq_zulip_evidence.sh [options]

Default behavior is a dry-run and does not post to Zulip.

Options:
  --execute                 Post the message and save evidence
  --realm <realm>           Zulip realm
  --evidence-dir <path>     Evidence output directory
  --kind <name>             Evidence name, e.g. approval_request or completion
  --content <text>          Message body
  --stream <name>           Zulip stream name
  --topic <name>            Zulip topic name
  -h, --help                Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) EXECUTE=true; shift ;;
    --realm) REALM="$2"; shift 2 ;;
    --evidence-dir) EVIDENCE_DIR="$2"; shift 2 ;;
    --kind) KIND="$2"; shift 2 ;;
    --content) CONTENT="$2"; shift 2 ;;
    --stream) STREAM_NAME="$2"; shift 2 ;;
    --topic) TOPIC_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "${REALM}" || -z "${EVIDENCE_DIR}" || -z "${KIND}" || -z "${CONTENT}" ]]; then
  echo "--realm, --evidence-dir, --kind, and --content are required" >&2
  exit 2
fi
if [[ ! "${KIND}" =~ ^[a-z0-9_-]+$ ]]; then
  echo "--kind must contain only lowercase letters, numbers, underscore, or hyphen" >&2
  exit 2
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
RESOLVER="${REPO_ROOT}/scripts/itsm/zulip/resolve_zulip_env.sh"
OUTPUT_PATH="${EVIDENCE_DIR%/}/zulip_${KIND}.json"

if ! ${EXECUTE}; then
  printf '[dry-run] realm=%s stream=%s topic=%s evidence=%s\n' \
    "${REALM}" "${STREAM_NAME}" "${TOPIC_NAME}" "${OUTPUT_PATH}"
  exit 0
fi

mkdir -p "${EVIDENCE_DIR}"
response="$(${RESOLVER} --realm "${REALM}" --exec bash -c '
  set -euo pipefail
  stream="$1"
  topic="$2"
  content="$3"

  stream_response="$(curl -fsS -u "$ZULIP_BOT_EMAIL:$ZULIP_BOT_API_KEY" -G \
    "$ZULIP_BASE_URL/api/v1/get_stream_id" \
    --data-urlencode "stream=$stream")"
  stream_id="$(jq -r ".stream_id // empty" <<<"$stream_response")"
  test -n "$stream_id"

  send_response="$(curl -fsS -u "$ZULIP_BOT_EMAIL:$ZULIP_BOT_API_KEY" -X POST \
    "$ZULIP_BASE_URL/api/v1/messages" \
    --data-urlencode "type=stream" \
    --data-urlencode "to=$stream" \
    --data-urlencode "topic=$topic" \
    --data-urlencode "content=$content")"
  message_id="$(jq -r ".id // empty" <<<"$send_response")"
  test -n "$message_id"

  stream_slug="$(jq -rn --arg value "$stream" "\$value | gsub(\" \"; \"-\") | @uri")"
  topic_slug="$(jq -rn --arg value "$topic" "\$value | @uri")"
  message_url="${ZULIP_BASE_URL%/}/#narrow/channel/${stream_id}-${stream_slug}/topic/${topic_slug}/near/${message_id}"

  jq -nc \
    --arg message_id "$message_id" \
    --arg stream_id "$stream_id" \
    --arg stream "$stream" \
    --arg topic "$topic" \
    --arg content "$content" \
    --arg message_url "$message_url" \
    --argjson api_response "$send_response" \
    "{ok:true,message_id:(\$message_id|tonumber),stream_id:(\$stream_id|tonumber),stream:\$stream,topic:\$topic,content:\$content,message_url:\$message_url,api_response:\$api_response}"
' _ "${STREAM_NAME}" "${TOPIC_NAME}" "${CONTENT}")"

printf '%s\n' "${response}" | jq '.' >"${OUTPUT_PATH}"
jq -r '"ZULIP_MESSAGE_ID=\(.message_id)\nZULIP_MESSAGE_URL=\(.message_url)"' "${OUTPUT_PATH}"
