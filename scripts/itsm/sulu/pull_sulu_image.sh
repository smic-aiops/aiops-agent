#!/usr/bin/env bash
set -euo pipefail

if [[ "${N8N_SULU_PULL_DEBUG:-}" == "1" || "${N8N_SULU_PULL_DEBUG:-}" == "true" ]]; then
  set -x
fi

# Resolve repo root so this script can be run from any working directory.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

tf_output_raw() {
  local output
  if output="$(terraform -chdir="${REPO_ROOT}" output -raw "$1" 2>/dev/null)"; then
    printf '%s' "${output}"
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'USAGE'
Usage:
  scripts/itsm/sulu/pull_sulu_image.sh [--dry-run]

Options:
  -n, --dry-run   Print planned actions only (no docker/network writes).
  -h, --help      Show this help.

Notes:
  - DRY_RUN=true is also supported (back-compat: N8N_DRY_RUN=true).
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

while [[ "${#}" -gt 0 ]]; do
  case "${1}" in
    -n|--dry-run)
      DRY_RUN="true"
      shift
      ;;
    *)
      echo "ERROR: Unknown argument: ${1}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

PRESERVE_CACHE="${N8N_PRESERVE_PULL_CACHE:-false}"
CLEAN_CACHE="${N8N_CLEAN_PULL_CACHE:-false}"
DRY_RUN="${DRY_RUN:-${N8N_DRY_RUN:-false}}"
APPLY_SULU_ADMIN_THEME_PATCH="${N8N_APPLY_SULU_ADMIN_THEME_PATCH:-true}"
APPLY_SULU_N8N_PATCH="${APPLY_SULU_N8N_PATCH:-true}"
# pull_* は「取得（pull）/キャッシュ」用途が主で、ビルド系処理は `run_all_build.sh` 側に寄せる。
# 初回の npm/composer が重い環境でも `run_all_pull.sh` が 10 分程度で完走しやすいように、
# ここではデフォルトで admin assets ビルドをスキップする（必要なら N8N_BUILD_ADMIN_ASSETS=true）。
BUILD_ADMIN_ASSETS="${N8N_BUILD_ADMIN_ASSETS:-false}"
ADMIN_ASSETS_BUILD_IMAGE="${N8N_ADMIN_ASSETS_BUILD_IMAGE:-node:20-bookworm}"

# composer install は Dockerfile 側で実施しているため、pull フェーズではデフォルトでスキップする。
# 必要なら SKIP_SULU_COMPOSER_INSTALL=false で有効化できる。
SKIP_SULU_COMPOSER_INSTALL="${SKIP_SULU_COMPOSER_INSTALL:-true}"
COMPOSER_BIN="${COMPOSER_BIN:-composer}"
COMPOSER_INSTALL_ARGS="${COMPOSER_INSTALL_ARGS:---no-dev --no-interaction --prefer-dist --classmap-authoritative --no-progress}"
COMPOSER_PHAR_URL="${COMPOSER_PHAR_URL:-https://getcomposer.org/composer-stable.phar}"
COMPOSER_PHAR_PATH="${COMPOSER_PHAR_PATH:-${TMPDIR:-/tmp}/composer.phar}"
COMPOSER_DOCKER_IMAGE="${COMPOSER_DOCKER_IMAGE:-composer:2}"
COMPOSER_DOCKER_IGNORE_PLATFORM_REQS="${COMPOSER_DOCKER_IGNORE_PLATFORM_REQS:-true}"
COMPOSER_DOCKER_NO_SCRIPTS="${COMPOSER_DOCKER_NO_SCRIPTS:-true}"

SULU_THEME_BG="${SULU_THEME_BG:-#0b1020}"
SULU_THEME_ACCENT="${SULU_THEME_ACCENT:-#7c3aed}"
SULU_OLD_ADMIN_BG="${SULU_OLD_ADMIN_BG:-#112a46}"
SULU_OLD_ADMIN_ACCENT="${SULU_OLD_ADMIN_ACCENT:-#52b6ca}"

resolve_path() {
  local path="$1"
  if [[ "${path}" = /* ]]; then
    echo "${path}"
    return
  fi
  path="${path#./}"
  echo "${REPO_ROOT}/${path}"
}

SULU_VERSION="${SULU_VERSION:-$(tf_output_raw sulu_image_tag)}"
SULU_VERSION="${SULU_VERSION:-3.0.3}"
SULU_SOURCE_URL="${SULU_SOURCE_URL:-https://github.com/sulu/skeleton/archive/refs/tags/${SULU_VERSION}.tar.gz}"
SULU_CONTEXT="${SULU_CONTEXT:-./docker/sulu}"
SULU_CONTEXT="$(resolve_path "${SULU_CONTEXT}")"
SULU_TEMPLATE_CONTEXT="${SULU_TEMPLATE_CONTEXT:-./docker/sulu}"
SULU_TEMPLATE_CONTEXT="$(resolve_path "${SULU_TEMPLATE_CONTEXT}")"
SULU_SOURCE_DIR="${SULU_CONTEXT}/source"
N8N_HOMEPAGE_ASSETS_DIR="${N8N_HOMEPAGE_ASSETS_DIR:-${REPO_ROOT}/scripts/itsm/sulu/homepage_assets}"
N8N_ADMIN_MONITORING_ASSETS_DIR="${N8N_ADMIN_MONITORING_ASSETS_DIR:-${REPO_ROOT}/scripts/itsm/sulu/admin_monitoring_assets}"
N8N_SULU_SOURCE_OVERLAY_DIR="${N8N_SULU_SOURCE_OVERLAY_DIR:-${REPO_ROOT}/scripts/itsm/sulu/source_overrides}"

ensure_pages_json() {
  local pages_json="${N8N_HOMEPAGE_ASSETS_DIR}/content/pages.json"
  local pages_example="${N8N_HOMEPAGE_ASSETS_DIR}/content/pages.json.example"

  if [[ -f "${pages_json}" || ! -f "${pages_example}" ]]; then
    return 0
  fi

  if is_truthy "${DRY_RUN}"; then
    echo "[sulu] [dry-run] copy ${pages_example} -> ${pages_json}"
    return 0
  fi

  cp -a "${pages_example}" "${pages_json}"
}

download_source() {
  local dest="$1"
  echo "[sulu] Downloading ${SULU_SOURCE_URL}..."
  curl -fL "${SULU_SOURCE_URL}" -o "${dest}"
}

extract_source() {
  local archive="$1" workdir="$2"
  if is_truthy "${CLEAN_CACHE}"; then
    rm -rf "${SULU_SOURCE_DIR}"
  elif is_truthy "${PRESERVE_CACHE}" && [[ -d "${SULU_SOURCE_DIR}" ]] && [[ -n "$(ls -A "${SULU_SOURCE_DIR}" 2>/dev/null || true)" ]]; then
    echo "[sulu] Preserving existing source dir: ${SULU_SOURCE_DIR}"
    return 0
  fi
  rm -rf "${SULU_SOURCE_DIR}"
  mkdir -p "${workdir}"
  tar -xzf "${archive}" -C "${workdir}"
  local extracted
  extracted="$(find "${workdir}" -maxdepth 1 -mindepth 1 -type d | head -n1)"
  if [ -z "${extracted}" ]; then
    echo "[sulu] Failed to locate extracted directory" >&2
    exit 1
  fi
  mkdir -p "${SULU_SOURCE_DIR}"
  cp -a "${extracted}/." "${SULU_SOURCE_DIR}/"
  rm -rf "${SULU_SOURCE_DIR}/.git" "${SULU_SOURCE_DIR}/.github"
  # Stamp the pulled version so build scripts can verify source/build tag alignment.
  printf '%s\n' "${SULU_VERSION}" > "${SULU_SOURCE_DIR}/.aiops_sulu_version"
  printf '%s\n' "${SULU_SOURCE_URL}" > "${SULU_SOURCE_DIR}/.aiops_sulu_source_url"
  echo "[sulu] Extracted ${SULU_SOURCE_URL} to ${SULU_SOURCE_DIR}"
}

apply_webspace_overrides() {
  local webspace_file="${SULU_SOURCE_DIR}/config/webspaces/website.xml"
  if [[ ! -f "${webspace_file}" ]]; then
    echo "[sulu] website.xml missing; skipping webspace overrides." >&2
    return 0
  fi

  if ! grep -q 'language="ja"' "${webspace_file}"; then
    if command -v perl >/dev/null 2>&1; then
      perl -pi -e 's#<localization[[:space:]]+language="en"[[:space:]]+default="true"[[:space:]]*/>#<localization language="en" default="true"/>\n        <localization language="ja"/>#g' "${webspace_file}"
    else
      awk '
        {
          if ($0 ~ /<localization[[:space:]]+language="en"[[:space:]]+default="true"[[:space:]]*\/>/) {
            print "        <localization language=\"en\" default=\"true\"/>"
            print "        <localization language=\"ja\"/>"
            next
          }
          print
        }
      ' "${webspace_file}" > "${webspace_file}.tmp"
      mv "${webspace_file}.tmp" "${webspace_file}"
    fi
  fi

  # Ensure each portal URL block also lists a Japanese entry.
  if ! grep -q '<url language="ja">' "${webspace_file}"; then
    if command -v perl >/dev/null 2>&1; then
      perl -0pi -e 's|(<urls>\s*)(<url language="en">{host}</url>)|$1<url language="ja">{host}</url>\n        $2|g' "${webspace_file}"
    else
      awk '
        {
          if ($0 ~ /<url language="en">{host}<\/url>/ && prev ~ /<urls>/) {
            print "        <url language=\"ja\">{host}</url>"
          }
          print
          prev=$0
        }
      ' "${webspace_file}" > "${webspace_file}.tmp"
      mv "${webspace_file}.tmp" "${webspace_file}"
    fi
  fi

  # Ensure each portal URL block also lists an English entry.
  if ! grep -q '<url language="en">' "${webspace_file}"; then
    if command -v perl >/dev/null 2>&1; then
      perl -0pi -e 's|(<url language="ja">{host}</url>)|$1\n        <url language="en">{host}</url>|g' "${webspace_file}"
    else
      awk '
        {
          print
          if ($0 ~ /<url language="ja">{host}<\/url>/) {
            print "        <url language=\"en\">{host}</url>"
          }
        }
      ' "${webspace_file}" > "${webspace_file}.tmp"
      mv "${webspace_file}.tmp" "${webspace_file}"
    fi
  fi
}

replace_color_in_file() {
  local file="$1" from="$2" to="$3"
  if command -v perl >/dev/null 2>&1; then
    FROM="${from}" TO="${to}" perl -pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/ig' "${file}"
    return 0
  fi
  sed -i.bak "s|${from}|${to}|g" "${file}"
  rm -f "${file}.bak" 2>/dev/null || true
}

apply_admin_theme_patch() {
  if ! is_truthy "${APPLY_SULU_ADMIN_THEME_PATCH}"; then
    echo "[sulu] Skipping admin theme patch (N8N_APPLY_SULU_ADMIN_THEME_PATCH=${APPLY_SULU_ADMIN_THEME_PATCH})"
    return 0
  fi

  local manifest="${SULU_SOURCE_DIR}/public/build/admin/manifest.json"
  if [[ ! -f "${manifest}" ]]; then
    echo "[sulu] Admin manifest.json missing; skipping theme patch: ${manifest}" >&2
    return 0
  fi

  local css_rel css_path
  css_rel="$(awk -F '\"' '$2 == "main.css" {print $4; exit}' "${manifest}" 2>/dev/null || true)"
  if [[ -z "${css_rel}" ]]; then
    echo "[sulu] Could not resolve main.css from manifest.json; skipping theme patch." >&2
    return 0
  fi
  css_path="${SULU_SOURCE_DIR}/public${css_rel}"
  if [[ ! -f "${css_path}" ]]; then
    echo "[sulu] Admin CSS missing; skipping theme patch: ${css_path}" >&2
    return 0
  fi

  echo "[sulu] Patching admin theme CSS: ${css_rel}"
  replace_color_in_file "${css_path}" "${SULU_OLD_ADMIN_BG}" "${SULU_THEME_BG}"
  replace_color_in_file "${css_path}" "${SULU_OLD_ADMIN_ACCENT}" "${SULU_THEME_ACCENT}"
}

copy_file_optional() {
  local src="$1" dest="$2"
  if [[ ! -f "${src}" ]]; then
    echo "[sulu] WARN: Missing override file: ${src}" >&2
    return 0
  fi
  if is_truthy "${DRY_RUN}"; then
    echo "[sulu] [dry-run] copy ${src} -> ${dest}"
    return 0
  fi
  mkdir -p "$(dirname "${dest}")"
  cp -a "${src}" "${dest}"
}

copy_dir_optional() {
  local src="$1" dest="$2"
  if [[ ! -d "${src}" ]]; then
    echo "[sulu] WARN: Missing override dir: ${src}" >&2
    return 0
  fi
  if is_truthy "${DRY_RUN}"; then
    echo "[sulu] [dry-run] copy ${src}/ -> ${dest}/"
    return 0
  fi
  mkdir -p "${dest}"
  cp -a "${src}/." "${dest}/"
}

apply_aiops_overrides() {
  if ! is_truthy "${APPLY_SULU_N8N_PATCH}"; then
    echo "[sulu] Skipping AIOps overrides (APPLY_SULU_N8N_PATCH=${APPLY_SULU_N8N_PATCH})"
    return 0
  fi

  if [[ -d "${N8N_HOMEPAGE_ASSETS_DIR}" ]]; then
    ensure_pages_json
    copy_file_optional "${N8N_HOMEPAGE_ASSETS_DIR}/templates/pages/homepage.html.twig" \
      "${SULU_SOURCE_DIR}/templates/pages/homepage.html.twig"
    copy_file_optional "${N8N_HOMEPAGE_ASSETS_DIR}/templates/pages/default.html.twig" \
      "${SULU_SOURCE_DIR}/templates/pages/default.html.twig"
    copy_file_optional "${N8N_HOMEPAGE_ASSETS_DIR}/public/index.php" \
      "${SULU_SOURCE_DIR}/public/index.php"
    copy_file_optional "${N8N_HOMEPAGE_ASSETS_DIR}/bin/replace_sulu_pages.php" \
      "${SULU_SOURCE_DIR}/bin/replace_sulu_pages.php"
    copy_file_optional "${N8N_HOMEPAGE_ASSETS_DIR}/content/pages.json" \
      "${SULU_SOURCE_DIR}/content/pages.json"
    copy_file_optional "${N8N_HOMEPAGE_ASSETS_DIR}/public/build/itsm-home.css" \
      "${SULU_SOURCE_DIR}/public/build/itsm-home.css"
    copy_file_optional "${N8N_HOMEPAGE_ASSETS_DIR}/public/build/itsm-home.js" \
      "${SULU_SOURCE_DIR}/public/build/itsm-home.js"
  else
    echo "[sulu] WARN: AIOps homepage assets dir missing: ${N8N_HOMEPAGE_ASSETS_DIR}" >&2
  fi

  if [[ -d "${N8N_ADMIN_MONITORING_ASSETS_DIR}" ]]; then
    copy_file_optional "${N8N_ADMIN_MONITORING_ASSETS_DIR}/src/Admin/MonitoringAdmin.php" \
      "${SULU_SOURCE_DIR}/src/Admin/MonitoringAdmin.php"
    copy_file_optional "${N8N_ADMIN_MONITORING_ASSETS_DIR}/assets/admin/app.js" \
      "${SULU_SOURCE_DIR}/assets/admin/app.js"
    copy_file_optional "${N8N_ADMIN_MONITORING_ASSETS_DIR}/assets/admin/webpack.config.js" \
      "${SULU_SOURCE_DIR}/assets/admin/webpack.config.js"
    copy_dir_optional "${N8N_ADMIN_MONITORING_ASSETS_DIR}/assets/admin/views" \
      "${SULU_SOURCE_DIR}/assets/admin/views"
  else
    echo "[sulu] WARN: AIOps admin monitoring assets dir missing: ${N8N_ADMIN_MONITORING_ASSETS_DIR}" >&2
  fi

  patch_sulu_navigation_twig

  if [[ -d "${N8N_SULU_SOURCE_OVERLAY_DIR}" ]]; then
    copy_dir_optional "${N8N_SULU_SOURCE_OVERLAY_DIR}" "${SULU_SOURCE_DIR}"
  else
    echo "[sulu] WARN: Sulu override dir missing: ${N8N_SULU_SOURCE_OVERLAY_DIR}" >&2
  fi
}

build_admin_assets() {
  if ! is_truthy "${BUILD_ADMIN_ASSETS}"; then
    echo "[sulu] Skipping admin asset build (N8N_BUILD_ADMIN_ASSETS=${BUILD_ADMIN_ASSETS})"
    return 0
  fi

  local admin_dir="${SULU_SOURCE_DIR}/assets/admin"
  local package_json="${admin_dir}/package.json"

  if [[ ! -f "${package_json}" ]]; then
    echo "[sulu] Admin assets package.json missing; skipping build: ${package_json}" >&2
    return 0
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[sulu] [dry-run] would build admin assets in ${admin_dir}"
    echo "[sulu] [dry-run] npm install --no-audit --no-fund && npm run build"
    return 0
  fi

  echo "[sulu] Building admin assets..."
  if command -v npm >/dev/null 2>&1; then
    (cd "${admin_dir}" && npm install --no-audit --no-fund && npm run build)
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    docker run --rm \
      -u "$(id -u)":"$(id -g)" \
      -v "${SULU_SOURCE_DIR}:/app" \
      -w /app/assets/admin \
      "${ADMIN_ASSETS_BUILD_IMAGE}" \
      sh -lc "npm install --no-audit --no-fund && npm run build"
    return 0
  fi

  echo "[sulu] npm/docker not available; skipping admin asset build." >&2
  return 0
}

patch_sulu_navigation_twig() {
  local base_template="${SULU_SOURCE_DIR}/templates/base.html.twig"
  local homepage_template="${SULU_SOURCE_DIR}/templates/pages/homepage.html.twig"

  if [[ ! -f "${base_template}" && ! -f "${homepage_template}" ]]; then
    echo "[sulu] WARN: Twig templates missing; skipping navigation function patch." >&2
    return 0
  fi

  for template in "${base_template}" "${homepage_template}"; do
    if [[ -f "${template}" ]]; then
      replace_color_in_file "${template}" "sulu_navigation_root_tree" "sulu_page_navigation_root_tree"
    fi
  done
}

install_composer_dependencies() {
  local admin_bundle_pkg="${SULU_SOURCE_DIR}/vendor/sulu/sulu/src/Sulu/Bundle/AdminBundle/Resources/js/package.json"
  if is_truthy "${SKIP_SULU_COMPOSER_INSTALL}"; then
    # Admin asset build requires vendor/sulu/sulu to exist. If we are going to build assets, do not skip.
    if is_truthy "${BUILD_ADMIN_ASSETS}" && [[ ! -f "${admin_bundle_pkg}" ]]; then
      echo "[sulu] WARN: admin assets build requested but vendor is missing; forcing composer install (SKIP_SULU_COMPOSER_INSTALL=false)." >&2
    else
      echo "[sulu] SKIP_SULU_COMPOSER_INSTALL=true; skipping composer install."
      return 0
    fi
  fi
  if [[ ! -f "${SULU_SOURCE_DIR}/composer.json" ]]; then
    echo "[sulu] composer.json missing in ${SULU_SOURCE_DIR}; skipping composer install." >&2
    return 0
  fi
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[sulu] (dry-run) ${COMPOSER_BIN} install ${COMPOSER_INSTALL_ARGS}"
    return 0
  fi

  (
    cd "${SULU_SOURCE_DIR}"
    echo "[sulu] Running composer install to populate vendor/sulu/sulu ..."
    if ! run_composer_command install ${COMPOSER_INSTALL_ARGS}; then
      echo "[sulu] Composer install failed or composer binary unavailable; trying Docker fallback..." >&2
      if ! run_composer_docker install ${COMPOSER_INSTALL_ARGS}; then
        echo "[sulu] Composer install failed; skipping vendor install." >&2
        return 0
      fi
    fi
  )
}

ensure_composer_phar() {
  if [[ -f "${COMPOSER_PHAR_PATH}" ]]; then
    return
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${COMPOSER_PHAR_URL}" -o "${COMPOSER_PHAR_PATH}"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "${COMPOSER_PHAR_PATH}" "${COMPOSER_PHAR_URL}"
  else
    echo "[sulu] curl/wget missing; cannot download composer.phar" >&2
    return 1
  fi
  chmod +x "${COMPOSER_PHAR_PATH}"
}

run_composer_command() {
  local args=("$@")
  if command -v "${COMPOSER_BIN}" >/dev/null 2>&1; then
    COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_MEMORY_LIMIT=-1 "${COMPOSER_BIN}" "${args[@]}"
    return $?
  fi
  if ! command -v php >/dev/null 2>&1; then
    return 1
  fi
  if ! ensure_composer_phar; then
    return 1
  fi
  COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_MEMORY_LIMIT=-1 php "${COMPOSER_PHAR_PATH}" "${args[@]}"
}

run_composer_docker() {
  local args=("$@")
  local ignore_arg="--ignore-platform-req=ext-intl"
  local no_scripts_arg="--no-scripts"
  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi
  if is_truthy "${COMPOSER_DOCKER_IGNORE_PLATFORM_REQS}"; then
    if [[ " ${args[*]} " != *" ${ignore_arg} "* && " ${args[*]} " != *" --ignore-platform-reqs "* ]]; then
      args+=("${ignore_arg}")
    fi
  fi
  if is_truthy "${COMPOSER_DOCKER_NO_SCRIPTS}"; then
    if [[ " ${args[*]} " != *" ${no_scripts_arg} "* ]]; then
      args+=("${no_scripts_arg}")
    fi
  fi
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[sulu] (dry-run) docker run --rm -u $(id -u):$(id -g) -v ${SULU_SOURCE_DIR}:/app -w /app ${COMPOSER_DOCKER_IMAGE} ${args[*]}"
    return 0
  fi
  docker run --rm \
    -u "$(id -u)":"$(id -g)" \
    -e COMPOSER_ALLOW_SUPERUSER=1 \
    -e COMPOSER_MEMORY_LIMIT=-1 \
    -v "${SULU_SOURCE_DIR}:/app" \
    -w /app \
    "${COMPOSER_DOCKER_IMAGE}" \
    "${args[@]}"
}

apply_localization_overrides() {
  local services_file="${SULU_SOURCE_DIR}/config/services.yaml"
  local framework_file="${SULU_SOURCE_DIR}/config/packages/framework.yaml"
  local translation_file="${SULU_SOURCE_DIR}/config/packages/translation.yaml"
  local translations_dir="${SULU_SOURCE_DIR}/translations"

  if [[ -f "${services_file}" ]]; then
    if grep -Eq '^[[:space:]]*default_locale:' "${services_file}"; then
      sed -i.bak -E 's/^[[:space:]]*default_locale:.*/    default_locale: en/' "${services_file}"
      rm -f "${services_file}.bak"
    else
      printf '\nparameters:\n    default_locale: en\n' >> "${services_file}"
    fi
  else
    echo "[sulu] services.yaml missing; skipping default_locale override." >&2
  fi

  if [[ -f "${framework_file}" ]]; then
    if ! grep -Eq '^[[:space:]]*default_locale:' "${framework_file}"; then
      awk '
        BEGIN { inserted = 0 }
        {
          if (!inserted && $0 ~ /^[[:space:]]*framework:[[:space:]]*$/) {
            print
            print "    default_locale: \047%default_locale%\047"
            inserted = 1
            next
          }
          print
        }
        END {
          if (!inserted) {
            print "framework:"
            print "    default_locale: \047%default_locale%\047"
          }
        }
      ' "${framework_file}" > "${framework_file}.tmp"
      mv "${framework_file}.tmp" "${framework_file}"
    fi
  else
    echo "[sulu] framework.yaml missing; skipping framework.default_locale override." >&2
  fi

  if [[ -f "${translation_file}" ]]; then
    if ! grep -Eq '^[[:space:]]*fallbacks:' "${translation_file}"; then
      awk '
        !inserted {
          print
          if ($0 ~ /^[[:space:]]*providers:[[:space:]]*$/) {
            match($0, /^[[:space:]]*/)
            indent = substr($0, RSTART, RLENGTH)
            print indent "fallbacks: ['\''en'\'', '\''ja'\'']"
            inserted = 1
          }
          next
        }
        { print }
      ' "${translation_file}" > "${translation_file}.tmp"
      mv "${translation_file}.tmp" "${translation_file}"
    fi
  else
    echo "[sulu] translation.yaml missing; skipping translator fallbacks." >&2
  fi

  mkdir -p "${translations_dir}"
  cat >"${translations_dir}/sulu_admin.ja.yaml" <<'EOF'
app.monitoring: 'モニタリング'
app.monitoring.ai_nodes: 'AI ノード'
app.monitoring.filter.realm: 'レルム（任意）'
app.monitoring.filter.workflow: 'ワークフロー（任意）'
app.monitoring.filter.node: 'ノード（任意）'
app.monitoring.apply: '適用'
app.monitoring.status.ok: 'OK'
app.monitoring.status.error: 'エラー'
app.monitoring.status.loading: '読み込み中...'
app.monitoring.table.id: 'ID'
app.monitoring.table.received: '受信時刻'
app.monitoring.table.realm: 'レルム'
app.monitoring.table.workflow: 'ワークフロー'
app.monitoring.table.node: 'ノード'
app.monitoring.table.execution: '実行'
app.monitoring.table.summary: 'サマリ'
app.monitoring.table.payload: '入出力'

sulu_admin.add: '追加'
sulu_admin.add_block: 'ブロックを追加'
sulu_admin.paste_blocks: '{count} 件のブロックを貼り付け'
sulu_admin.delete: '削除'
sulu_admin.delete_selected: '選択した項目を削除'
sulu_admin.delete_locale: '現在のローカライズを削除'
sulu_admin.move: '移動'
sulu_admin.move_items: '項目を移動'
sulu_admin.copy: 'コピー'
sulu_admin.cut: '切り取り'
sulu_admin.duplicate: '複製'
sulu_admin.order: '並び替え'
sulu_admin.of: 'の'
sulu_admin.page: 'ページ'
sulu_admin.per_page: 'ページあたりの件数'
sulu_admin.save: '保存'
sulu_admin.save_draft: '下書きとして保存'
sulu_admin.save_publish: '保存して公開'
sulu_admin.publish: '公開'
sulu_admin.create: '作成'
sulu_admin.edit: '編集'
sulu_admin.object: 'オブジェクト'
sulu_admin.objects: 'オブジェクト一覧'
sulu_admin.reached_end_of_list: '一覧の末尾に到達しました'
sulu_admin.confirm: '確認'
sulu_admin.ok: 'OK'
sulu_admin.cancel: 'キャンセル'
sulu_admin.apply: '適用'
sulu_admin.yes: 'はい'
sulu_admin.no: 'いいえ'
sulu_admin.type: 'タイプ'
sulu_admin.default: '既定値'
sulu_admin.language: '言語'
sulu_admin.error_required: 'この項目は入力必須です'
sulu_admin.error_minlength: '入力の最小文字数に達していません'
sulu_admin.error_maxlength: '入力の最大文字数を超えています'
sulu_admin.error_minitems: '選択数が少なすぎます'
sulu_admin.error_maxitems: '選択数が多すぎます'
sulu_admin.error_minimum: '最小値を下回っています'
sulu_admin.error_maximum: '最大値を超えています'
sulu_admin.error_multipleof: '条件に一致しません'
sulu_admin.error_pattern: '指定されたパターンに一致しません'
sulu_admin.error_format: '指定された形式に一致しません'
sulu_admin.welcome: 'ようこそ'
sulu_admin.reset_password: 'パスワードをリセット'
sulu_admin.reset_password_error: 'パスワードが一致しません'
sulu_admin.reset_password_pattern_error: 'セキュリティ要件を満たしていません'
sulu_admin.back_to_website: 'ウェブサイトに戻る'
sulu_admin.username_or_email: 'ユーザー名またはメールアドレス'
sulu_admin.password: 'パスワード'
sulu_admin.repeat_password: 'パスワード（再入力）'
sulu_admin.login: 'ログイン'
sulu_admin.logout: 'ログアウト'
sulu_admin.login_error: 'メールアドレス／パスワードの組み合わせが正しくありません。再度お試しください。'
sulu_admin.to_login: 'ログインする'
sulu_admin.back_to_login: 'ログイン画面に戻る'
sulu_admin.reset: 'リセット'
sulu_admin.reset_resend: '再送信'
sulu_admin.forgot_password: 'パスワードをお忘れですか？'
sulu_admin.forgot_password_success: 'アカウントが見つかった場合、パスワードリセット手順を記載したメールを送信しました'
sulu_admin.list_search_placeholder: '検索…'
sulu_admin.error: 'エラー'
sulu_admin.warning: '警告'
sulu_admin.info: '情報'
sulu_admin.success: '成功'
sulu_admin.close: '閉じる'
sulu_admin.id: 'ID'
sulu_admin.key: 'キー'
sulu_admin.title: 'タイトル'
sulu_admin.name: '名称'
sulu_admin.description: '説明'
sulu_admin.timestamp: 'タイムスタンプ'
sulu_admin.resource: 'リソース'
sulu_admin.url: 'URL'
sulu_admin.creator: '作成者'
sulu_admin.created: '作成日時'
sulu_admin.changer: '更新者'
sulu_admin.changed: '更新日時'
sulu_admin.published: '公開日時'
sulu_admin.authored: '著者日時'
sulu_admin.author: '著者'
sulu_admin.delete_warning_title: '削除しますか？'
sulu_admin.delete_warning_text: 'この操作はデータを完全に削除し、元には戻せません。本当に続行しますか？'
sulu_admin.delete_locale_warning_title: '現在のローカライズを削除しますか？'
sulu_admin.delete_locale_warning_text: 'この操作は現在のローカライズのすべてのデータを削除し、元には戻せません。本当に続行しますか？'
sulu_admin.delete_linked_warning_title: '削除を確認'
sulu_admin.delete_linked_warning_text: 'この項目は次の項目から参照されています。削除してもよろしいですか？'
sulu_admin.delete_selection_warning_text: '{count} 件の項目を削除し、この操作は元に戻せません。本当に続行しますか？'
sulu_admin.item_not_deletable: 'この項目は削除できません'
sulu_admin.delete_linked_abort_text: 'この項目はサブ項目が存在するため削除できません。以下のサブ項目を削除するか、関連を解除してください。'
sulu_admin.delete_element_dependant_warning_title: '{1}依存する要素を1件削除しますか？|]1,Inf[%count% 件の依存要素を削除しますか？'
sulu_admin.delete_element_dependant_warning_detail: '{1}1つの依存要素も削除してよろしいですか？|]1,Inf[%count% 件の依存要素も削除してよろしいですか？'
sulu_admin.delete_dependants_progress_text: '{count} 件の依存要素が削除されました'
sulu_admin.ghost_dialog_title: '他言語からコピーしますか？'
sulu_admin.ghost_dialog_description: 'このページはこの言語には存在しません。他の言語のコンテンツをコピーしますか？'
sulu_admin.choose_language: '言語を選択'
sulu_admin.characters_left: '残り {count} 文字'
sulu_admin.segments_left: '残り {count} セグメント'
sulu_admin.create_copy: 'コピーを作成'
sulu_admin.copy_dialog_description: '現在の項目のコピーを作成します。続行しますか？'
sulu_admin.copy_locale: 'ロケールをコピー'
sulu_admin.choose_target_locale: 'ターゲットロケールを選択'
sulu_admin.copy_locale_dialog_description: '* 新しいロケールが作成されます'
sulu_admin.move_copy_overlay_title: '親ページを選択'
sulu_admin.filter_overlay_title: '{fieldLabel} を設定'
sulu_admin.data_source: 'ソースを選択'
sulu_admin.choose_data_source: 'ソースを選択'
sulu_admin.include_sub_elements: 'サブ要素を含める'
sulu_admin.filter_by_categories: 'カテゴリで絞り込む'
sulu_admin.any_category_description: 'いずれかのカテゴリを使う'
sulu_admin.all_categories_description: 'すべてのカテゴリを使う'
sulu_admin.choose_categories: 'カテゴリを選択'
sulu_admin.filter_by_tags: 'タグで絞り込む'
sulu_admin.any_tag_description: 'いずれかのタグを使う'
sulu_admin.all_tags_description: 'すべてのタグを使う'
sulu_admin.filter_by_types: 'タイプで絞り込む'
sulu_admin.all_types: 'すべてのタイプが選択されています'
sulu_admin.no_types: 'タイプが選択されていません'
sulu_admin.target_groups: '対象グループ'
sulu_admin.use_target_groups: '対象グループを使用'
sulu_admin.sort_by: '並び順'
sulu_admin.ascending: '昇順'
sulu_admin.descending: '降順'
sulu_admin.present_as: '表示形式'
sulu_admin.limit_result_to: '結果を制限'
sulu_admin.smart_content_label: '{count} 件の要素が選択されています'
sulu_admin.smart_content_block_preview: 'スマートコンテンツ（最大 {limit} 件表示）'
sulu_admin.order_warning_title: '要素を並び替えます'
sulu_admin.order_warning_text: 'この操作により要素の順序が変更されます。'
sulu_admin.activate_all: 'すべて有効にする'
sulu_admin.deactivate_all: 'すべて無効にする'
sulu_admin.all_selected: 'すべて選択済み'
sulu_admin.none_selected: '選択なし'
sulu_admin.please_choose: '選択してください'
sulu_admin.column_options: '列のオプション'
sulu_admin.changelog_line_changer: '{changed} に {changer} が最後に変更'
sulu_admin.changelog_line_creator: '{created} に {creator} が作成'
sulu_admin.settings: '設定'
sulu_admin.move_selected: '選択項目を移動'
sulu_admin.details: '詳細'
sulu_admin.edit_entries: 'エントリを編集'
sulu_admin.paragraph: '段落'
sulu_admin.heading1: '見出し 1'
sulu_admin.heading2: '見出し 2'
sulu_admin.heading3: '見出し 3'
sulu_admin.heading4: '見出し 4'
sulu_admin.heading5: '見出し 5'
sulu_admin.heading6: '見出し 6'
sulu_admin.dirty_warning_dialog_title: 'フォームを離れますか？'
sulu_admin.dirty_warning_dialog_text: '保存されていない変更が失われます。'
sulu_admin.change_type_dirty_warning_dialog_title: 'テンプレートを変更しますか？'
sulu_admin.export: 'エクスポート'
sulu_admin.export_overlay_title: 'データ形式を設定'
sulu_admin.delimiter: '区切り文字'
sulu_admin.enclosure: '囲い文字'
sulu_admin.escape: 'エスケープ文字'
sulu_admin.new_line: '改行'
sulu_admin.delimiter_description: '列の区切り文字です。'
sulu_admin.enclosure_description: '複数単語の値を囲います。'
sulu_admin.escape_description: '特殊文字の追加設定です。'
sulu_admin.new_line_description: '改行文字です。'
sulu_admin.delimiter_tab: 'タブ'
sulu_admin.enclosure_nothing: 'なし'
sulu_admin.link: 'リンク'
sulu_admin.link_title: '代替タイトル'
sulu_admin.link_target: 'リンクのターゲット'
sulu_admin.link_url: 'リンク URL'
sulu_admin.link_query: 'クエリ文字列'
sulu_admin.link_anchor: 'アンカー'
sulu_admin.single_icon_selection.select: 'アイコンを選択'
sulu_admin.mail_subject: 'メール件名'
sulu_admin.mail_body: 'メール本文'
sulu_admin.show_history: '履歴を表示'
sulu_admin.history: '履歴'
sulu_admin.resource_locator_history_delete_warning: 'URL は下書き・公開バージョンすべてから削除されます。元に戻せません。続行しますか？'
sulu_admin.has_changed_warning_dialog_title: '内容が上書きされます！'
sulu_admin.has_changed_warning_dialog_text: '他のユーザーが編集済みです。保存すると現在のデータは失われます。'
sulu_admin.edit_profile: 'プロフィールを編集'
sulu_admin.no_follow: 'nofollow'
sulu_admin.no_permissions: '権限がありません'
sulu_admin.not_found: '見つかりません'
sulu_admin.unexpected_error: '予期せぬエラー'
sulu_admin.no_options_available: '利用可能なオプションがありません'
sulu_admin.form_contains_invalid_values: 'フォームに無効な値が含まれています'
sulu_admin.form_save_server_error: 'フォーム保存時にエラーが発生しました'
sulu_admin.form_used_by: 'このフォームは次の用途で使用されています'
sulu_admin.refresh_url: 'URL を更新'
sulu_admin.from: '開始'
sulu_admin.until: '終了'
sulu_admin.external_link: '外部リンク'
sulu_admin.internal_link: '内部リンク'
sulu_admin.block_settings: 'ブロック設定'
sulu_admin.hide_block: 'このブロックをウェブサイトに表示しない'
sulu_admin.segment: 'セグメント'
sulu_admin.missing_type_dialog_title: '新しいテンプレートを選択'
sulu_admin.missing_type_dialog_description: 'コピーしたページのテンプレートがこのウェブスペースに存在しません。'
sulu_admin.upload: 'アップロード'
sulu_admin.unexpected_upload_error: '{fileName, select, undefined{ファイル} other{{fileName}}} のアップロード中に予期せぬエラーが発生しました。'
sulu_admin.dropzone_error_file-invalid-type: '{fileName, select, undefined{ファイル} other{{fileName}}} は許可されていないタイプです{allowedTypes, select, undefined{} other{。許可されているタイプ: ({allowedTypes})}}'
sulu_admin.dropzone_error_file-too-large: '{fileName, select, undefined{ファイル} other{{fileName}}} は {maxSize, select, undefined{大きすぎます} other{最大 {maxSize} より大きいです}}'
sulu_admin.dropzone_error_file-too-small: '{fileName, select, undefined{ファイル} other{{fileName}}} は {minSize, select, undefined{小さすぎます} other{最小 {minSize} 未満です}}'
sulu_admin.dropzone_error_too-many-files: 'ファイルが多すぎます{maxFiles, select, undefined{} other{。最大 {maxFiles} 件までです}}'
sulu_admin.weekly: '週次'
sulu_admin.fixed: '固定期間'
sulu_admin.weekdays: '平日'
sulu_admin.monday: '月曜日'
sulu_admin.tuesday: '火曜日'
sulu_admin.wednesday: '水曜日'
sulu_admin.thursday: '木曜日'
sulu_admin.friday: '金曜日'
sulu_admin.saturday: '土曜日'
sulu_admin.sunday: '日曜日'
sulu_admin.start: '開始'
sulu_admin.end: '終了'
sulu_admin.preview_date_time: 'プレビュー日時'
sulu_admin.preview_date_time_description: '入力を空にすると現在日時が使用されます。'
sulu_admin.lastDay: '昨日'
sulu_admin.nextDay: '明日'
sulu_admin.sameDay: '今日'
sulu_admin.activity: 'アクティビティ'
sulu_admin.versions: 'バージョン'
sulu_admin.activity_versions: 'アクティビティとバージョン'
sulu_admin.insights: 'インサイト'
sulu_admin.insufficient_descendant_permissions: '{count} 件の子要素に対する権限が不足しています。'
sulu_admin.unexpected_delete_server_error: '削除中に予期せぬエラーが発生しました。'
sulu_admin.two_factor_authentication: '二要素認証'
sulu_admin.two_factor_authentication_failed: '認証コードが無効です。再度お試しください。'
sulu_admin.two_factor_verification_code: '認証コード'
sulu_admin.two_factor_trust_device: 'このデバイスを信用する'
sulu_admin.two_factor_email_subject: '認証コード'
sulu_admin.two_factor_email_text: '本人確認のため、次のコードを入力してください: %codeLength% 桁'
sulu_admin.verify: '認証'
sulu_admin.%count%_selected: '{count} 件選択済み'
sulu_admin.select_all: 'すべて選択'
sulu_admin.deselect_all: 'すべて選択解除'
sulu_admin.select_multiple_blocks: '複数のブロックを選択'
sulu_admin.collapse_all_blocks: 'すべてのブロックを折りたたむ'
sulu_admin.expand_all_blocks: 'すべてのブロックを展開'
sulu_admin.%count%_blocks_copied: '{count} 件のブロックをクリップボードにコピーしました。'
sulu_admin.%count%_blocks_duplicated: '{count} 件のブロックを複製しました。'
sulu_admin.%count%_blocks_removed: '{count} 件のブロックを削除しました。'
sulu_admin.%count%_blocks_cut: '{count} 件のブロックを切り取りました。'
sulu_admin.%count%_blocks_pasted: '{count} 件のブロックを貼り付けました。'
sulu_admin.writing_assistant: 'ライティングアシスタント'
sulu_admin.insert: '挿入'
sulu_admin.writing_assistant_prompt_placeholder: 'Sulu に何を手伝ってほしいですか？'
sulu_admin.sucessfully_copied_to_clipboard: 'クリップボードにコピーしました'
sulu_admin.selected_text: '選択テキスト'
sulu_admin.predefined_prompts: '定型プロンプト'
sulu_admin.translator: '翻訳'
sulu_admin.detected: '検出されました'
sulu_admin.translator_error: '翻訳中に問題が発生しました'
sulu_admin.send_feedback: 'フィードバックを送信'
sulu_admin.feedback: 'フィードバック'
sulu_admin.send: '送信'
sulu_admin.link_target_blank: '_blank'
sulu_admin.link_target_self: '_self'
sulu_admin.link_target_parent: '_parent'
sulu_admin.link_target_top: '_top'
EOF

  cat >"${translations_dir}/sulu_admin.en.yaml" <<'EOF'
app.monitoring: 'Monitoring'
app.monitoring.ai_nodes: 'AI Nodes'
app.monitoring.filter.realm: 'realm (optional)'
app.monitoring.filter.workflow: 'workflow (optional)'
app.monitoring.filter.node: 'node (optional)'
app.monitoring.apply: 'Apply'
app.monitoring.status.ok: 'OK'
app.monitoring.status.error: 'ERROR'
app.monitoring.status.loading: 'loading...'
app.monitoring.table.id: 'ID'
app.monitoring.table.received: 'Received'
app.monitoring.table.realm: 'Realm'
app.monitoring.table.workflow: 'Workflow'
app.monitoring.table.node: 'Node'
app.monitoring.table.execution: 'Execution'
app.monitoring.table.summary: 'Summary'
app.monitoring.table.payload: 'Input/Output'
EOF
}

ensure_sulu_dockerfile_template() {
  local dockerfile="$1"
  if [ -f "${dockerfile}" ]; then
    return 0
  fi
  if is_truthy "${DRY_RUN}"; then
    echo "[sulu] [dry-run] would restore missing Dockerfile at ${dockerfile}"
    return 0
  fi

  mkdir -p "$(dirname "${dockerfile}")"
  # Keep this template in sync with docker/sulu/Dockerfile.
  cat > "${dockerfile}" <<'EOF'
ARG SULU_VERSION=3.0.0
ARG PHP_IMAGE=php:8.4-fpm
ARG PHP_CLI_IMAGE=php:8.4-cli
ARG COMMON_PACKAGES="ca-certificates git curl unzip zip libpq-dev libzip-dev libicu-dev libonig-dev libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev gnupg libvips-dev libffi-dev pkg-config build-essential autoconf"
ARG NODE_SETUP_SCRIPT=https://deb.nodesource.com/setup_20.x

FROM ${PHP_CLI_IMAGE} AS composer
ARG COMMON_PACKAGES
ARG NODE_SETUP_SCRIPT
RUN set -eux;     mkdir -p /etc/apt;     codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-bookworm}")";     if [ ! -f /etc/apt/sources.list ]; then       echo "deb https://deb.debian.org/debian ${codename} main" > /etc/apt/sources.list;       echo "deb https://deb.debian.org/debian ${codename}-updates main" >> /etc/apt/sources.list;       echo "deb https://security.debian.org/debian-security ${codename}-security main" >> /etc/apt/sources.list;     else       sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list;       sed -i 's|http://security.debian.org|https://security.debian.org|g' /etc/apt/sources.list;     fi;     apt-get update;     apt-get install -y --no-install-recommends ${COMMON_PACKAGES};     curl -fsSL ${NODE_SETUP_SCRIPT} | bash -;     apt-get install -y --no-install-recommends nodejs;     npm install -g yarn@1.22.19;     curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer;     printf "\n" | pecl install vips;     docker-php-ext-enable vips;     docker-php-ext-configure ffi --with-ffi;     docker-php-ext-configure intl;     docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp;     docker-php-ext-install intl gd pdo pdo_pgsql zip ffi;     rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY source/ /app/
COPY init-db.sh /app/docker/init-db.sh
COPY init-db.php /app/docker/init-db.php
ENV COMPOSER_ALLOW_SUPERUSER=1
ENV COMPOSER_MEMORY_LIMIT=-1
RUN composer install --no-dev --no-interaction --prefer-dist --classmap-authoritative --no-progress

FROM ${PHP_IMAGE} AS runtime
ARG SULU_VERSION
ARG COMMON_PACKAGES
ARG NODE_SETUP_SCRIPT
ARG APPLY_SULU_ADMIN_THEME_PATCH=true
ARG THEME_BG_HEX=0b1020
ARG THEME_ACCENT_HEX=7c3aed
ARG OLD_ADMIN_BG_HEX=112a46
ARG OLD_ADMIN_ACCENT_HEX=52b6ca
RUN set -eux;     mkdir -p /etc/apt;     codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-bookworm}")";     if [ ! -f /etc/apt/sources.list ]; then       echo "deb https://deb.debian.org/debian ${codename} main" > /etc/apt/sources.list;       echo "deb https://deb.debian.org/debian ${codename}-updates main" >> /etc/apt/sources.list;       echo "deb https://security.debian.org/debian-security ${codename}-security main" >> /etc/apt/sources.list;     else       sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list;       sed -i 's|http://security.debian.org|https://security.debian.org|g' /etc/apt/sources.list;     fi;     apt-get update;     apt-get install -y --no-install-recommends ${COMMON_PACKAGES};     curl -fsSL ${NODE_SETUP_SCRIPT} | bash -;     apt-get install -y --no-install-recommends nodejs;     npm install -g yarn@1.22.19;     printf "\n" | pecl install vips;     docker-php-ext-enable vips;     docker-php-ext-configure ffi --with-ffi;     docker-php-ext-configure intl;     docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp;     docker-php-ext-install intl gd pdo pdo_pgsql zip ffi;     rm -rf /var/lib/apt/lists/*
WORKDIR /var/www/html
COPY --from=composer /app /var/www/html
COPY --chown=www-data:www-data config/ config/
COPY --chown=www-data:www-data hooks/ hooks/
RUN set -eux; \
    if [ "${APPLY_SULU_ADMIN_THEME_PATCH}" = "true" ] && [ -f public/build/admin/manifest.json ]; then \
      css_rel="$(php -r '$m=json_decode(@file_get_contents("public/build/admin/manifest.json"), true); echo is_array($m)&&isset($m["main.css"])?$m["main.css"]:"";')"; \
      if [ -n "${css_rel}" ] && [ -f "public${css_rel}" ]; then \
        css_path="public${css_rel}"; \
        old_bg="#${OLD_ADMIN_BG_HEX}"; old_accent="#${OLD_ADMIN_ACCENT_HEX}"; \
        theme_bg="#${THEME_BG_HEX}"; theme_accent="#${THEME_ACCENT_HEX}"; \
        sed -i "s|${old_bg}|${theme_bg}|g" "${css_path}"; \
        sed -i "s|${old_accent}|${theme_accent}|g" "${css_path}"; \
      fi; \
    fi
RUN set -eux;     chown -R www-data:www-data /var/www/html
RUN chmod +x /var/www/html/hooks/onready/*.sh
RUN chmod +x /var/www/html/docker/init-db.sh
LABEL org.opencontainers.image.title="Sulu PHP"       org.opencontainers.image.version="3.0.0"       org.opencontainers.image.vendor="aiops-agent"       org.opencontainers.image.source="https://github.com/sulu/skeleton"
USER www-data
EOF
  echo "[sulu] Restored missing Dockerfile: ${dockerfile}"
}

sync_context_files() {
  local src="$1" dest="$2"
  local items=(Dockerfile init-db.sh init-db.php hooks config nginx)
  local item

  ensure_sulu_dockerfile_template "${src}/Dockerfile"
  for item in "${items[@]}"; do
    if [ ! -e "${src}/${item}" ]; then
      echo "[sulu] Required context file missing in template: ${src}/${item}" >&2
      exit 1
    fi
  done

  if [ "${src}" = "${dest}" ]; then
    return
  fi

  mkdir -p "${dest}"
  for item in "${items[@]}"; do
    if is_truthy "${PRESERVE_CACHE}" && [[ -e "${dest}/${item}" ]]; then
      echo "[sulu] Preserving existing context item: ${dest}/${item}"
      continue
    fi
    rm -rf "${dest:?}/${item}"
    cp -a "${src}/${item}" "${dest}/${item}"
  done
  echo "[sulu] Synced build context files from ${src} to ${dest}"
}

ensure_composer_memory_limit() {
  local dockerfile="${SULU_CONTEXT}/Dockerfile"
  if [ ! -f "${dockerfile}" ]; then
    echo "[sulu] Dockerfile missing at ${dockerfile}; skipping COMPOSER_MEMORY_LIMIT update." >&2
    return
  fi

  if grep -q '^ENV COMPOSER_MEMORY_LIMIT=' "${dockerfile}"; then
    return
  fi

  awk '
    BEGIN { inserted = 0 }
    {
      print
      if (!inserted && $0 == "ENV COMPOSER_ALLOW_SUPERUSER=1") {
        print "ENV COMPOSER_MEMORY_LIMIT=-1"
        inserted = 1
      }
    }
    END {
      if (!inserted) {
        print "ENV COMPOSER_MEMORY_LIMIT=-1"
      }
    }
  ' "${dockerfile}" > "${dockerfile}.tmp"
  mv "${dockerfile}.tmp" "${dockerfile}"
}

main() {
  if is_truthy "${DRY_RUN}"; then
    echo "[sulu] Dry run enabled; no changes will be made."
    echo "[sulu] [dry-run] would download: ${SULU_SOURCE_URL}"
    echo "[sulu] [dry-run] would extract into: ${SULU_SOURCE_DIR}"
    echo "[sulu] [dry-run] would run ${COMPOSER_BIN} install ${COMPOSER_INSTALL_ARGS}"
    echo "[sulu] [dry-run] would apply localization overrides (default_locale=en, framework.default_locale, translation fallbacks, ja translations)"
    echo "[sulu] [dry-run] would apply webspace overrides (website.xml localization + url language=ja)"
    echo "[sulu] [dry-run] would apply AIOps overrides (homepage + admin monitoring + source overlay)"
    echo "[sulu] [dry-run] would build admin assets (npm install + npm run build)"
    echo "[sulu] [dry-run] would patch admin theme CSS (${SULU_OLD_ADMIN_BG}/${SULU_OLD_ADMIN_ACCENT} -> ${SULU_THEME_BG}/${SULU_THEME_ACCENT})"
    echo "[sulu] [dry-run] would sync docker context: ${SULU_TEMPLATE_CONTEXT} -> ${SULU_CONTEXT}"
    echo "[sulu] [dry-run] would ensure COMPOSER_MEMORY_LIMIT in Dockerfiles"
    apply_aiops_overrides
    echo "[sulu] Done (dry-run)."
    return 0
  fi
  local archive workdir
  archive="$(mktemp)"
  workdir="$(mktemp -d)"
  trap 'rm -rf "${archive:-}" "${workdir:-}"' EXIT

  download_source "${archive}"
  extract_source "${archive}" "${workdir}"
  install_composer_dependencies
  apply_localization_overrides
  apply_webspace_overrides
  apply_aiops_overrides
  build_admin_assets
  apply_admin_theme_patch
  sync_context_files "${SULU_TEMPLATE_CONTEXT}" "${SULU_CONTEXT}"
  ensure_composer_memory_limit
}

main "$@"
