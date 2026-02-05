#!/usr/bin/env bash
set -euo pipefail

# Sync docs templates to GitLab Wiki pages.
#
# Required (when DRY_RUN is false):
#   GITLAB_API_BASE_URL (example: https://gitlab.example.com/api/v4)
#   GITLAB_TOKEN
#   GITLAB_PROJECT_ID or GITLAB_PROJECT_PATH (group/project)
#
# Optional:
#   DRY_RUN (default: false)
#   DOCS_ROOT (default: docs)
#   WIKI_SOURCE_DIRS (comma-separated; default: auto; prefers docs/wiki, then docs/wiki_index.md, else docs)
#   WIKI_BASE_PATH (prefix for wiki path; default: empty)
#   WIKI_TITLE_MODE (path|heading; default: path)  # affects injected H1 only; wiki slug is always path-based
#   WIKI_REWRITE_LINKS (default: true)             # rewrite relative links like ../foo.md -> ../foo
#   WIKI_ENSURE_HOME (default: true)               # create the Wiki "home" page if missing (GitLab wiki landing page)
#   WIKI_HOME_SLUG (default: home)                 # do not change unless you know what you're doing
#   WIKI_HOME_DISPLAY_TITLE (default: Home)        # used as the H1 in the generated home page

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "error: ${cmd} is required" >&2
    exit 1
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

urlencode() {
  jq -nr --arg v "${1}" '$v|@uri'
}

gitlab_api_call() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local url="${GITLAB_API_BASE_URL%/}${path}"
  local tmp
  tmp="$(mktemp)"
  local status
  local curl_args=(-sS)
  if [[ "${GITLAB_VERIFY_SSL:-true}" == "false" ]]; then
    curl_args+=(-k)
  fi
  curl_args+=(--connect-timeout "${GITLAB_CURL_CONNECT_TIMEOUT:-10}" --max-time "${GITLAB_CURL_MAX_TIME:-60}")

  if [ -n "${data}" ]; then
    status="$(curl "${curl_args[@]}" -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "${data}" \
      "${url}")"
  else
    status="$(curl "${curl_args[@]}" -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      "${url}")"
  fi

  printf '%s\n' "${status}" >"${tmp}.status"
  cat "${tmp}"
  rm -f "${tmp}" "${tmp}.status"
}

gitlab_list_wiki_pages() {
  local project_id="$1"
  local page=1
  while true; do
    local response
    response="$(gitlab_api_call GET "/projects/${project_id}/wikis?per_page=100&page=${page}")"
    local count
    count="$(jq -r 'length' <<<"${response}" 2>/dev/null || echo 0)"
    if [ "${count}" = "0" ]; then
      break
    fi
    echo "${response}"
    page=$((page + 1))
  done
}

gitlab_find_wiki_slug_by_title() {
  local project_id="$1"
  local title="$2"
  gitlab_list_wiki_pages "${project_id}" | jq -r --arg title "${title}" '.[] | select(.title == $title) | .slug' | head -n1
}

resolve_project_id() {
  local project_id="${GITLAB_PROJECT_ID:-}"
  if [ -n "${project_id}" ]; then
    printf '%s' "${project_id}"
    return
  fi

  if [ -z "${GITLAB_PROJECT_PATH:-}" ]; then
    return
  fi

  local encoded
  encoded="$(urlencode "${GITLAB_PROJECT_PATH}")"
  local response
  response="$(gitlab_api_call GET "/projects/${encoded}")"
  project_id="$(jq -r '.id // empty' <<<"${response}")"
  printf '%s' "${project_id}"
}

rewrite_markdown_for_gitlab_wiki() {
  local wiki_page_path="$1"
  local title_from_heading="$2"

  if ! is_truthy "${WIKI_REWRITE_LINKS:-true}"; then
    cat
    return
  fi

  python3 -c '
import os
import re
import sys

wiki_page_path = sys.argv[1]
title_from_heading = sys.argv[2] if len(sys.argv) > 2 else ""
text = sys.stdin.read()

def is_relative_target(url: str) -> bool:
  u = url.strip()
  if not u:
    return False
  if u.startswith("#") or u.startswith("/") or u.startswith("//"):
    return False
  if "{{" in u or "}}" in u:
    return False
  if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", u):
    return False
  return True

def strip_md_ext(url: str) -> str:
  m = re.match(r"^(.*?)(\.md(?:\.tpl)?)([?#].*)?$", url)
  if not m:
    return url
  base = m.group(1)
  suffix = m.group(3) or ""
  return f"{base}{suffix}"

def rewrite_url(url: str) -> str:
  if not is_relative_target(url):
    return url
  return strip_md_ext(url)

# 1) Inline links: [text](url "title")
inline = re.compile(r"\]\(([^)\s]+)(\s+\"[^\"]*\")?\)")
def inline_repl(m):
  url = m.group(1)
  opt = m.group(2) or ""
  return f"]({rewrite_url(url)}{opt})"
text = inline.sub(inline_repl, text)

# 2) Reference definitions: [id]: url
refdef = re.compile(r"^(\[[^\]]+\]:\s+)(\S+)(.*)$", re.MULTILINE)
def refdef_repl(m):
  prefix, url, rest = m.group(1), m.group(2), m.group(3)
  return f"{prefix}{rewrite_url(url)}{rest}"
text = refdef.sub(refdef_repl, text)

# 3) Autolinks: <url>
autolink = re.compile(r"<([^>\s]+)>")
def autolink_repl(m):
  url = m.group(1)
  rewritten = rewrite_url(url)
  return f"<{rewritten}>"
text = autolink.sub(autolink_repl, text)

# Optional: if user prefers heading titles and the page lacks a top-level heading, inject one.
inject = os.environ.get("WIKI_TITLE_MODE", "path").strip().lower() == "heading"
if inject and not re.search(r"^#\s+\S", text, flags=re.MULTILINE):
  h1 = title_from_heading.strip() or wiki_page_path.split("/")[-1]
  text = f"# {h1}\\n\\n{text}"

sys.stdout.write(text)
' "${wiki_page_path}" "${title_from_heading}"
}

file_to_wiki_path() {
  local file="$1"
  local rel wiki_path

  rel="${file#${DOCS_ROOT}/}"
  if [ "${rel}" = "${file}" ]; then
    rel="${file}"
  fi

  # When DOCS_ROOT points to a higher-level templates directory, allow paths like
  # "<domain>/docs/<category>/..." to map to wiki "<category>/..." (keeps existing wiki slugs).
  if [[ "${rel}" == */docs/* ]]; then
    rel="${rel#*/docs/}"
  fi

  wiki_path="${rel}"
  if [[ "${wiki_path}" == *.md.tpl ]]; then
    wiki_path="${wiki_path%.md.tpl}"
  elif [[ "${wiki_path}" == *.md ]]; then
    wiki_path="${wiki_path%.md}"
  fi

  if [ -n "${WIKI_BASE_PATH}" ]; then
    wiki_path="${WIKI_BASE_PATH}/${wiki_path}"
  fi

  printf '%s' "${wiki_path}"
}

DOCS_ROOT="${DOCS_ROOT:-docs}"
DRY_RUN="${DRY_RUN:-false}"
if [ -z "${WIKI_SOURCE_DIRS:-}" ]; then
  if [ -d "${DOCS_ROOT}/wiki" ]; then
    WIKI_SOURCE_DIRS="${DOCS_ROOT}/wiki"
  elif [ -f "${DOCS_ROOT}/wiki_index.md" ]; then
    WIKI_SOURCE_DIRS="${DOCS_ROOT}/wiki_index.md"
  else
    WIKI_SOURCE_DIRS="${DOCS_ROOT}"
  fi
fi
WIKI_BASE_PATH="${WIKI_BASE_PATH:-}"
WIKI_TITLE_MODE="${WIKI_TITLE_MODE:-path}"
WIKI_REWRITE_LINKS="${WIKI_REWRITE_LINKS:-true}"
WIKI_ENSURE_HOME="${WIKI_ENSURE_HOME:-true}"
WIKI_MIGRATE_BY_HEADING="${WIKI_MIGRATE_BY_HEADING:-true}"
WIKI_HOME_SLUG="${WIKI_HOME_SLUG:-home}"
WIKI_HOME_DISPLAY_TITLE="${WIKI_HOME_DISPLAY_TITLE:-Home}"

require_cmd "jq"
require_cmd "curl"
if is_truthy "${WIKI_REWRITE_LINKS}"; then
  require_cmd "python3"
fi

if [ ! -d "${DOCS_ROOT}" ]; then
  echo "error: docs root not found: ${DOCS_ROOT}" >&2
  exit 1
fi

IFS=',' read -r -a source_entries <<<"${WIKI_SOURCE_DIRS}"

files=()
for entry in "${source_entries[@]}"; do
  entry="${entry}"; entry="${entry#./}"
  if [ -f "${entry}" ]; then
    files+=("${entry}")
    continue
  fi
  if [[ "${entry}" == *.md ]] && [ -f "${entry}.tpl" ]; then
    files+=("${entry}.tpl")
    continue
  fi
  if [[ "${entry}" == *.md.tpl ]] && [ -f "${entry%.tpl}" ]; then
    files+=("${entry%.tpl}")
    continue
  fi
  if [ -d "${entry}" ]; then
    while IFS= read -r -d '' file; do
      files+=("${file}")
    done < <(find "${entry}" -type f \( -name '*.md' -o -name '*.md.tpl' \) -print0)
  fi
done

if [ "${#files[@]}" -eq 0 ]; then
  echo "error: no wiki source files found" >&2
  exit 1
fi

total_files="${#files[@]}"
if ! is_truthy "${DRY_RUN}"; then
  echo "[gitlab] Wiki template sync start: files=${total_files}"
fi

if ! is_truthy "${DRY_RUN}"; then
  if [ -z "${GITLAB_API_BASE_URL:-}" ] || [ -z "${GITLAB_TOKEN:-}" ]; then
    echo "error: GITLAB_API_BASE_URL and GITLAB_TOKEN are required" >&2
    exit 1
  fi

  GITLAB_PROJECT_ID="$(resolve_project_id)"
  if [ -z "${GITLAB_PROJECT_ID:-}" ]; then
    echo "error: GITLAB_PROJECT_ID or GITLAB_PROJECT_PATH is required" >&2
    exit 1
  fi
fi

created=0
updated=0
skipped=0
failed=0
processed=0

WIKI_BASE_PATH="${WIKI_BASE_PATH#/}"
WIKI_BASE_PATH="${WIKI_BASE_PATH%/}"

if ! is_truthy "${DRY_RUN}" && is_truthy "${WIKI_ENSURE_HOME}"; then
  home_slug="${WIKI_HOME_SLUG}"
  home_slug="${home_slug#/}"
  home_slug="${home_slug%/}"
  home_slug_encoded="$(urlencode "${home_slug}")"

  home_get="$(gitlab_api_call GET "/projects/${GITLAB_PROJECT_ID}/wikis/${home_slug_encoded}")"
  home_exists="$(jq -r '.slug // empty' <<<"${home_get}")"

  if [ -z "${home_exists}" ]; then
    index_paths=()
    practice_paths=()
    for file in "${files[@]}"; do
      candidate_path="$(file_to_wiki_path "${file}")"
      base="$(basename "${candidate_path}")"
      if [[ "${base}" == "wiki_index" || "${base}" == "index" ]]; then
        index_paths+=("${candidate_path}")
      fi
      if [[ "${base}" == "practice" ]]; then
        practice_paths+=("${candidate_path}")
      fi
    done
    if [ "${#index_paths[@]}" -eq 0 ]; then
      index_paths+=("$(file_to_wiki_path "${files[0]}")")
    fi

    home_content="# ${WIKI_HOME_DISPLAY_TITLE}\n\n"
    home_content="${home_content}このページは sync_wiki_from_templates.sh により自動作成されました（初回アクセス用）。\n\n"

    if [ "${#practice_paths[@]}" -gt 0 ]; then
      home_content="${home_content}## Practice Guide\n\n"
      home_content="${home_content}- [${practice_paths[0]}](${practice_paths[0]})\n\n"
    fi

    home_content="${home_content}## Index\n\n"
    for p in "${index_paths[@]}"; do
      home_content="${home_content}- [${p}](${p})\n"
    done

    home_payload="$(jq -n --arg title "${home_slug}" --arg content "$(printf '%b' "${home_content}")" '{title:$title,content:$content,format:"markdown"}')"
    home_post="$(gitlab_api_call POST "/projects/${GITLAB_PROJECT_ID}/wikis" "${home_payload}")"
    if jq -e '.slug' >/dev/null 2>&1 <<<"${home_post}"; then
      echo "[gitlab] Created wiki home page: ${home_slug}"
    else
      echo "error: failed to create wiki home page: ${home_slug}" >&2
      failed=$((failed + 1))
    fi
  fi
fi

for file in "${files[@]}"; do
  wiki_path="$(file_to_wiki_path "${file}")"
  echo "[gitlab] sync ${wiki_path} (${processed}/${total_files})"

  title_from_heading="$(awk '/^# / {sub(/^# /, ""); print; exit}' "${file}" || true)"
  if [ -z "${title_from_heading}" ]; then
    title_from_heading="$(basename "${wiki_path}")"
  fi

  # Keep slugs stable by always using a path-based title for the GitLab Wiki API.
  # (GitLab derives the slug from title; we cannot set slug directly.)
  wiki_title="${wiki_path}"

  if is_truthy "${DRY_RUN}"; then
    echo "[dry-run] sync ${file} -> wiki:${wiki_path} (title: ${wiki_title})"
    continue
  fi

  slug_encoded="$(urlencode "${wiki_path}")"
  response="$(gitlab_api_call GET "/projects/${GITLAB_PROJECT_ID}/wikis/${slug_encoded}")"
  page_exists="$(jq -r '.slug // empty' <<<"${response}")"
  content="$(rewrite_markdown_for_gitlab_wiki "${wiki_path}" "${title_from_heading}" <"${file}")"

  payload="$(jq -n --arg title "${wiki_title}" --arg content "${content}" '{title:$title,content:$content,format:"markdown"}')"

  # Prefer stable path-based slug; if the page doesn't exist under the expected slug,
  # try to migrate an older page by matching its previous title (first H1 heading).
  put_target_slug="${wiki_path}"
  if is_truthy "${WIKI_MIGRATE_BY_HEADING}" && [ -z "${page_exists}" ] && [ -n "${title_from_heading}" ]; then
    existing_slug_by_heading="$(gitlab_find_wiki_slug_by_title "${GITLAB_PROJECT_ID}" "${title_from_heading}")"
    if [ -n "${existing_slug_by_heading}" ] && [ "${existing_slug_by_heading}" != "null" ]; then
      put_target_slug="${existing_slug_by_heading}"
    fi
  fi

  if [ -n "${page_exists}" ] || [ "${put_target_slug}" != "${wiki_path}" ]; then
    put_target_encoded="$(urlencode "${put_target_slug}")"
    put_response="$(gitlab_api_call PUT "/projects/${GITLAB_PROJECT_ID}/wikis/${put_target_encoded}" "${payload}")"
    if jq -e '.slug' >/dev/null 2>&1 <<<"${put_response}"; then
      updated=$((updated + 1))
    else
      echo "error: failed to update ${wiki_path}" >&2
      failed=$((failed + 1))
    fi
  else
    post_response="$(gitlab_api_call POST "/projects/${GITLAB_PROJECT_ID}/wikis" "${payload}")"
    if is_truthy "${WIKI_MIGRATE_BY_HEADING}" && jq -e '.message.base[]? | contains(\"Duplicate page\")' >/dev/null 2>&1 <<<"${post_response}"; then
      existing_slug="$(gitlab_find_wiki_slug_by_title "${GITLAB_PROJECT_ID}" "${wiki_title}")"
      if [ -n "${existing_slug}" ] && [ "${existing_slug}" != "null" ]; then
        existing_slug_encoded="$(urlencode "${existing_slug}")"
        put_response="$(gitlab_api_call PUT "/projects/${GITLAB_PROJECT_ID}/wikis/${existing_slug_encoded}" "${payload}")"
        if jq -e '.slug' >/dev/null 2>&1 <<<"${put_response}"; then
          updated=$((updated + 1))
          continue
        fi
      fi
    fi
    if jq -e '.slug' >/dev/null 2>&1 <<<"${post_response}"; then
      created=$((created + 1))
    else
      echo "error: failed to create ${wiki_path}" >&2
      failed=$((failed + 1))
    fi
  fi

  processed=$((processed + 1))
  if ((processed % 20 == 0)); then
    echo "[gitlab] Wiki template sync progress: ${processed}/${total_files}"
  fi
done

if ! is_truthy "${DRY_RUN}"; then
  echo "sync complete: created=${created} updated=${updated} skipped=${skipped} failed=${failed}"
fi
