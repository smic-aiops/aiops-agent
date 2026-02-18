#!/bin/bash
set -euo pipefail

# Backward-compat wrapper.
# Moved to: scripts/itsm/n8n/refresh_zulip_mess_bot.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

exec bash "${REPO_ROOT}/scripts/itsm/n8n/refresh_zulip_mess_bot.sh" "$@"
