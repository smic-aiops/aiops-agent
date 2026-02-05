#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/apps/create_oq_evidence_run_md.sh --app <app> [options]

Options:
  --app <app>           Target app name under apps/ (required)
  --date <YYYY-MM-DD>   Evidence date (default: today)
  --force               Overwrite if file already exists
  -n, --dry-run          Print planned actions only (no writes)
  -h, --help             Show this help

Output:
  apps/<app>/docs/oq/evidence/evidence_run_<YYYY-MM-DD>.md
USAGE
}

APP=""
DATE_STR=""
FORCE="false"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="${2:-}"; shift 2 ;;
    --date) DATE_STR="${2:-}"; shift 2 ;;
    --force) FORCE="true"; shift ;;
    -n|--dry-run) DRY_RUN="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${APP}" ]]; then
  echo "ERROR: --app is required" >&2
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ -z "${DATE_STR}" ]]; then
  DATE_STR="$(date +%F)"
fi

if [[ ! "${DATE_STR}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "ERROR: --date must be YYYY-MM-DD (got: ${DATE_STR})" >&2
  exit 2
fi

APP_DIR="${REPO_ROOT}/apps/${APP}"
OQ_DIR="${APP_DIR}/docs/oq"
EVIDENCE_DIR="${OQ_DIR}/evidence"
OUT_PATH="${EVIDENCE_DIR}/evidence_run_${DATE_STR}.md"

if [[ ! -d "${APP_DIR}" ]]; then
  echo "ERROR: app not found: apps/${APP}" >&2
  exit 1
fi

if [[ ! -d "${OQ_DIR}" ]]; then
  echo "ERROR: OQ docs dir not found: apps/${APP}/docs/oq" >&2
  exit 1
fi

mkdir_cmd() {
  local dir="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[dry-run] mkdir -p ${dir#${REPO_ROOT}/}"
    return 0
  fi
  mkdir -p "${dir}"
}

write_file() {
  local path="$1"
  local content="$2"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[dry-run] write ${path#${REPO_ROOT}/}"
    return 0
  fi
  printf '%s' "${content}" >"${path}"
}

if [[ -f "${OUT_PATH}" && "${FORCE}" != "true" ]]; then
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[dry-run] already exists (use --force to overwrite): ${OUT_PATH#${REPO_ROOT}/}" >&2
    echo "${OUT_PATH#${REPO_ROOT}/}"
    exit 0
  fi
  echo "ERROR: already exists (use --force to overwrite): ${OUT_PATH#${REPO_ROOT}/}" >&2
  exit 1
fi

mkdir_cmd "${EVIDENCE_DIR}"

template="$(
  cat <<EOF
# 証跡: system.md 実行（${APP}）

> 保存先（規約）: \`apps/${APP}/docs/oq/evidence/evidence_run_YYYY-MM-DD.md\`

## 実施日時
- ${DATE_STR}

## 対象
- アプリ: \`apps/${APP}\`
- 対象 realm:

## 実施内容サマリ（結果）

## 重要な観測（ブロッカー）

## 次アクション（提案）

## 証跡パス
- \`evidence/<app>/<timestamp>/...\`
EOF
)"

write_file "${OUT_PATH}" "${template}"
echo "${OUT_PATH#${REPO_ROOT}/}"
