#!/usr/bin/env bash
set -euo pipefail

# Run ITSM bootstrap (projects/templates/labels/boards/wiki) for multiple realms (itsm_bootstrap_realms.sh).
#
# This script reuses the ITSM bootstrap functions implemented in ensure_realm_groups.sh, but provides
# a standalone entrypoint that can be executed independently for multiple realms.
#
# Requirements:
# - terraform, jq, curl, python3
# - GITLAB_TOKEN (Personal Access Token with group/project permissions; can be resolved via terraform output gitlab_admin_token)
#
# Optional environment variables (same as ensure_realm_groups.sh where applicable):
# - TERRAFORM_OUTPUT_NAME (default: service_control_web_monitoring_context)
# - REALMS (comma-separated; default: all realms from monitoring targets)
# - GITLAB_BASE_URL / GITLAB_API_BASE_URL (default: resolved from monitoring context)
# - GITLAB_PARENT_GROUP_ID (create/fork projects under this group path)
# - GITLAB_GROUP_VISIBILITY (default: private)
# - ITSM_BOOTSTRAP (default: true; set false to skip)
# - ITSM_FORCE_UPDATE (default: terraform output itsm_force_update or true)
# - ITSM_FORCE_UPDATE_INCLUDED_REALMS_JSON (default: terraform output itsm_force_update_included_realms; when empty, overwrite is disabled)
# - ITSM_SKIP_IF_PROJECT_EXISTS (default: true; set false to still apply labels/templates/boards)
# - ITSM_PROVISION_GRAFANA_EVENT_INBOX (default: false; when true, runs provision_grafana_itsm_event_inbox.sh before bootstrapping)
# - ITSM_PURGE_EXISTING (default: false; when true, deletes existing realm projects/templates before bootstrapping)
# - ITSM_ALLOW_ALL_REALMS (default: false; when REALMS is unset and DRY_RUN is unset, require true to allow targeting all realms)
# - ITSM_WIKI_SYNC_* (see ensure_realm_groups.sh)
# - DRY_RUN (set to any value to skip creation)

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/gitlab_lib.sh"

usage() {
  cat <<'EOF'
Usage: scripts/itsm/gitlab/itsm_bootstrap_realms.sh [--purge-existing] [--files-only] [--dry-run|-n]

Options:
  --purge-existing        Delete existing ITSM projects/templates for each target realm before bootstrapping (default: false).
  --files-only            Update only service-management Markdown/YAML files (skip labels/boards/wiki/schedules).
  --dry-run, -n           Resolve inputs and show planned actions (no create/update/delete API calls).
  -h, --help              Show this help.

Environment variables:
  - REALMS: comma-separated realm list (default: all realms from monitoring targets)
  - ITSM_ALLOW_ALL_REALMS: "true" to allow applying to all realms when REALMS is not specified (default: false)
  - ITSM_PURGE_EXISTING: "true" to enable purge (same as --purge-existing; default: false)
  - ITSM_EFS_MIRROR_CLEANUP: "true" to delete GitLab->EFS mirror clones when purging projects (default: true)
  - ITSM_EFS_MIRROR_CLEANUP_REQUIRED: "true" to fail the script when EFS mirror cleanup cannot run (default: auto)
  - ITSM_EFS_MIRROR_ROOT: when set, delete mirror clones locally under this path (otherwise uses ECS one-off task)
  - GITLAB_CREATE_PROJECT_MAX_ATTEMPTS: Retry count for transient "still being deleted" project-creation errors (default: 30)
  - GITLAB_CREATE_PROJECT_RETRY_SLEEP_SECONDS: Sleep between retries (default: 10)
EOF
}

_heartbeat_start() {
  local message="$1"
  local interval="${2:-5}"

  if [[ -n "${DRY_RUN:-}" ]]; then
    return
  fi

  (
    local start_seconds
    start_seconds="${SECONDS}"
    echo "[gitlab] ... ${message} (elapsed=0s)"
    while true; do
      sleep "${interval}"
      echo "[gitlab] ... ${message} (elapsed=$((SECONDS - start_seconds))s)"
    done
  ) &

  echo "$!"
}

_heartbeat_stop() {
  local pid="${1:-}"
  if [[ -z "${pid}" ]]; then
    return
  fi
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
}

gitlab_sync_repo_from_template() {
  local template_full_path="$1"
  local template_project_id="$2"
  local template_branch="$3"
  local target_full_path="$4"
  local target_project_id="$5"
  local target_branch="$6"

  echo "[gitlab] Pull updates from template: ${template_full_path}@${template_branch} -> ${target_full_path}@${target_branch}"
  gitlab_sync_repository_from_project "${template_project_id}" "${template_branch}" "${target_project_id}" "${target_branch}"
}

itsm_update_service_management_files_only() {
  local realm="$1"
  local group_full_path="$2"
  local template_project_id="$3"
  local template_branch="$4"
  local itsm_project_id="$5"
  local itsm_branch="$6"
  local grafana_base_url="$7"

  local template_path itsm_path general_management_path tech_management_path sample_service_id sample_service_file_id
  template_path="${ITSM_TEMPLATE_SERVICE_MANAGEMENT_PROJECT_PATH:-template-service-management}"
  itsm_path="${ITSM_SERVICE_MANAGEMENT_PROJECT_PATH:-service-management}"
  general_management_path="${ITSM_GENERAL_MANAGEMENT_PROJECT_PATH:-general-management}"
  tech_management_path="${ITSM_TECHNICAL_MANAGEMENT_PROJECT_PATH:-technical-management}"
  sample_service_file_id="${ITSM_CMDB_SAMPLE_FILE_ID:-web-service}"
  sample_service_id="${ITSM_CMDB_SAMPLE_SERVICE_ID:-sulu}"

  local grafana_url
  grafana_url="${grafana_base_url}"
  if [[ -z "${grafana_url}" || "${grafana_url}" == "null" ]]; then
    grafana_url="https://grafana.example.com"
    echo "[gitlab] WARN: grafana base_url not found for ${group_full_path}, using placeholder."
  fi
  grafana_url="${grafana_url%/}"

  local itsm_event_inbox_dashboard_uid itsm_event_inbox_dashboard_title
  local itsm_event_inbox_panel_id itsm_event_inbox_panel_title itsm_event_inbox_url
  itsm_event_inbox_dashboard_uid="$(echo "${ITSM_MONITORING_CONTEXT_JSON:-{}}" | jq -r --arg realm "${realm}" '.[$realm].grafana.itsm_event_inbox.dashboard_uid // empty' 2>/dev/null || true)"
  itsm_event_inbox_dashboard_title="$(echo "${ITSM_MONITORING_CONTEXT_JSON:-{}}" | jq -r --arg realm "${realm}" '.[$realm].grafana.itsm_event_inbox.dashboard_title // empty' 2>/dev/null || true)"
  itsm_event_inbox_panel_id="$(echo "${ITSM_MONITORING_CONTEXT_JSON:-{}}" | jq -r --arg realm "${realm}" '.[$realm].grafana.itsm_event_inbox.panel_id // empty' 2>/dev/null || true)"
  itsm_event_inbox_panel_title="$(echo "${ITSM_MONITORING_CONTEXT_JSON:-{}}" | jq -r --arg realm "${realm}" '.[$realm].grafana.itsm_event_inbox.panel_title // empty' 2>/dev/null || true)"
  itsm_event_inbox_url=""
  if [[ -n "${itsm_event_inbox_dashboard_uid}" ]]; then
    itsm_event_inbox_url="${grafana_url}/d/${itsm_event_inbox_dashboard_uid}/itsm-event-inbox"
    if [[ -n "${itsm_event_inbox_panel_id}" ]]; then
      itsm_event_inbox_url="${itsm_event_inbox_url}?viewPanel=${itsm_event_inbox_panel_id}"
    fi
  fi
  if [[ -z "${itsm_event_inbox_dashboard_title}" ]]; then
    itsm_event_inbox_dashboard_title="ITSM Event Inbox"
  fi
  if [[ -z "${itsm_event_inbox_panel_title}" ]]; then
    itsm_event_inbox_panel_title="Event Inbox (Annotations)"
  fi
  if [[ -z "${itsm_event_inbox_dashboard_uid}" ]]; then
    itsm_event_inbox_dashboard_uid="(unset)"
  fi
  if [[ -z "${itsm_event_inbox_panel_id}" ]]; then
    itsm_event_inbox_panel_id="(unset)"
  fi
  if [[ -z "${itsm_event_inbox_url}" ]]; then
    itsm_event_inbox_url="(unset)"
  fi

  local workflow_catalog_template escalation_matrix_template cmdb_template runbook_template
  workflow_catalog_template="$(load_template "service-management/docs/workflow_catalog.md.tpl")"
  escalation_matrix_template="$(load_template "service-management/docs/escalation_matrix.md.tpl")"

  local cmdb_id cmdb_org cmdb_service
  cmdb_org="$(printf '%s' "${group_full_path}" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '-' | sed 's/-$//')"
  cmdb_service="$(printf '%s' "${sample_service_id}" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '-' | sed 's/-$//')"
  cmdb_id="${cmdb_org}-${cmdb_service}-001"

  cmdb_template="$(
    load_and_render_template "service-management/cmdb/sulu.md.tpl" \
      "CMDB_ID" "${cmdb_id}" \
      "ORG_ID" "${group_full_path}" \
      "ORG_NAME" "${group_full_path}" \
      "SERVICE_ID" "${sample_service_id}" \
      "GRAFANA_BASE_URL" "${grafana_url}" \
      "GRAFANA_ITSM_EVENT_INBOX_DASHBOARD_UID" "${itsm_event_inbox_dashboard_uid}" \
      "GRAFANA_ITSM_EVENT_INBOX_DASHBOARD_TITLE" "${itsm_event_inbox_dashboard_title}" \
      "GRAFANA_ITSM_EVENT_INBOX_PANEL_ID" "${itsm_event_inbox_panel_id}" \
      "GRAFANA_ITSM_EVENT_INBOX_PANEL_TITLE" "${itsm_event_inbox_panel_title}" \
      "GRAFANA_ITSM_EVENT_INBOX_URL" "${itsm_event_inbox_url}" \
      "GITLAB_PROJECT_URL" "${GITLAB_BASE_URL}/${group_full_path}/${sample_service_id}"
  )"

  runbook_template="$(
    load_and_render_template "service-management/cmdb/runbook/sulu.md.tpl" \
      "SERVICE_NAME" "Sulu" \
      "SERVICE_ID" "${sample_service_id}" \
      "ENVIRONMENT" "本番" \
      "ORG_ID" "${group_full_path}" \
      "GITLAB_PROJECT_URL" "${GITLAB_BASE_URL}/${group_full_path}/${sample_service_id}"
  )"

  echo "[gitlab] files-only: updating service-management docs/cmdb for realm=${realm}"
  gitlab_upsert_file "${template_project_id}" "${template_branch}" "docs/workflow_catalog.md" "${workflow_catalog_template}" "Update workflow catalog"
  gitlab_upsert_file "${template_project_id}" "${template_branch}" "docs/escalation_matrix.md" "${escalation_matrix_template}" "Update escalation matrix"
  gitlab_upsert_file "${template_project_id}" "${template_branch}" "cmdb/${group_full_path}/${sample_service_file_id}.md" "${cmdb_template}" "Update CMDB template"
  gitlab_upsert_file "${template_project_id}" "${template_branch}" "cmdb/runbook/sulu.md" "${runbook_template}" "Update runbook template"

  gitlab_upsert_file "${itsm_project_id}" "${itsm_branch}" "docs/workflow_catalog.md" "${workflow_catalog_template}" "Update workflow catalog"
  gitlab_upsert_file "${itsm_project_id}" "${itsm_branch}" "docs/escalation_matrix.md" "${escalation_matrix_template}" "Update escalation matrix"
  gitlab_upsert_file "${itsm_project_id}" "${itsm_branch}" "cmdb/${group_full_path}/${sample_service_file_id}.md" "${cmdb_template}" "Update CMDB template"
  gitlab_upsert_file "${itsm_project_id}" "${itsm_branch}" "cmdb/runbook/sulu.md" "${runbook_template}" "Update runbook template"
}

gitlab_delete_project_by_id() {
  local project_id="$1"
  require_var "project id" "${project_id}"

  gitlab_request DELETE "/projects/${project_id}"
  case "${GITLAB_LAST_STATUS}" in
    200|202|204) ;;
    404) return ;;
    *)
      echo "ERROR: Failed to delete project id=${project_id} (HTTP ${GITLAB_LAST_STATUS})." >&2
      echo "${GITLAB_LAST_BODY}" >&2
      exit 1
      ;;
  esac
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

itsm_delete_efs_mirror_clones_for_project() {
  local realm="$1"
  local group_full_path="$2"
  local project_path="$3"

  # This cleanup targets the GitLab->EFS mirror layout documented in docs/itsm/README.md:
  #   /<n8n_filesystem_path>/qdrant/<realm>/gitlab/<group_full_path>/<project>.git
  #
  # Cleanup modes:
  # - local: set ITSM_EFS_MIRROR_ROOT to a path that is already mounted locally (e.g. inside the ECS task/container)
  # - ecs:   run a one-off ECS task that mounts the same EFS and deletes the mirror directories
  #
  # Controls:
  # - ITSM_EFS_MIRROR_CLEANUP (default: true)               enable/disable cleanup
  # - ITSM_EFS_MIRROR_CLEANUP_REQUIRED (default: auto)      when true, failure/skip is fatal; when "auto",
  #                                                        it's required only if gitlab_efs_mirror_task_definition_arn exists.
  # - ITSM_EFS_MIRROR_ROOT                                 when set, prefer local deletion under this root

  if ! is_truthy "${ITSM_EFS_MIRROR_CLEANUP:-true}"; then
    return
  fi

  if [[ -z "${realm}" || -z "${group_full_path}" || -z "${project_path}" ]]; then
    echo "[gitlab] WARN: EFS mirror cleanup skipped (missing realm/group/project)." >&2
    return
  fi

  if [[ "${group_full_path}" == /* || "${group_full_path}" == *".."* ]]; then
    echo "[gitlab] WARN: EFS mirror cleanup skipped (invalid group_full_path=${group_full_path})." >&2
    return
  fi
  if [[ "${project_path}" == /* || "${project_path}" == *".."* || "${project_path}" == */* ]]; then
    echo "[gitlab] WARN: EFS mirror cleanup skipped (invalid project_path=${project_path})." >&2
    return
  fi

  local mirror_td_arn required_mode required
  mirror_td_arn="$(tf_output_raw gitlab_efs_mirror_task_definition_arn || true)"
  required_mode="${ITSM_EFS_MIRROR_CLEANUP_REQUIRED:-auto}"
  required="false"
  if is_truthy "${required_mode}"; then
    required="true"
  elif [[ "${required_mode}" == "auto" && -n "${mirror_td_arn}" ]]; then
    required="true"
  fi

  local n8n_fs_root mirror_root
  n8n_fs_root="${ITSM_EFS_MIRROR_ROOT:-}"
  if [[ -n "${n8n_fs_root}" ]]; then
    mirror_root="${n8n_fs_root%/}/qdrant/${realm}/gitlab/${group_full_path}"
    if [[ -n "${DRY_RUN:-}" ]]; then
      echo "[gitlab] DRY_RUN would delete EFS mirror clones:"
      echo "  - ${mirror_root}/${project_path}.git"
      if [[ "${project_path}" != *.wiki ]]; then
        echo "  - ${mirror_root}/${project_path}.wiki.git"
      fi
      return
    fi
    if [[ -d "${mirror_root}" ]]; then
      echo "[gitlab] Deleting EFS mirror clones under (local): ${mirror_root}"
      rm -rf "${mirror_root:?}/${project_path}.git"
      if [[ "${project_path}" != *.wiki ]]; then
        rm -rf "${mirror_root:?}/${project_path}.wiki.git"
      fi
      return
    fi

    echo "[gitlab] WARN: ITSM_EFS_MIRROR_ROOT is set but mirror_root does not exist: ${mirror_root}" >&2
    if [[ "${required}" == "true" ]]; then
      exit 1
    fi
    # fall through to ECS-based cleanup
  fi

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "[gitlab] DRY_RUN would delete EFS mirror clones via ECS task:"
    echo "  - qdrant/${realm}/gitlab/${group_full_path}/${project_path}.git"
    if [[ "${project_path}" != *.wiki ]]; then
      echo "  - qdrant/${realm}/gitlab/${group_full_path}/${project_path}.wiki.git"
    fi
    return
  fi

  if ! command -v aws >/dev/null 2>&1; then
    echo "[gitlab] WARN: aws CLI not found; cannot delete EFS mirror clones." >&2
    if [[ "${required}" == "true" ]]; then
      exit 1
    fi
    return
  fi

  if [[ -z "${mirror_td_arn}" ]]; then
    echo "[gitlab] WARN: terraform output gitlab_efs_mirror_task_definition_arn is missing; cannot delete EFS mirror clones." >&2
    if [[ "${required}" == "true" ]]; then
      exit 1
    fi
    return
  fi

  local aws_profile aws_region cluster service_name
  aws_profile="${AWS_PROFILE:-$(tf_output_raw aws_profile || true)}"
  aws_profile="${aws_profile:-Admin-AIOps}"
  aws_region="${AWS_REGION:-$(tf_output_raw region || true)}"
  aws_region="${aws_region:-ap-northeast-1}"
  cluster="$(tf_output_raw ecs_cluster_name || true)"
  service_name="$(tf_output_raw n8n_service_name || true)"

  if [[ -z "${cluster}" || -z "${service_name}" ]]; then
    echo "[gitlab] WARN: terraform outputs ecs_cluster_name/n8n_service_name are missing; cannot run EFS cleanup task." >&2
    if [[ "${required}" == "true" ]]; then
      exit 1
    fi
    return
  fi

  local net_json subnets_csv sgs_csv
  net_json=""
  subnets_csv=""
  sgs_csv=""
  local aws_rc=0 aws_err=""

  local attempt
  for attempt in {1..5}; do
    local aws_stderr_file
    aws_stderr_file="$(mktemp)"
    aws_rc=0
    if ! net_json="$(aws --profile "${aws_profile}" --region "${aws_region}" ecs describe-services \
      --cluster "${cluster}" \
      --services "${service_name}" \
      --query 'services[0].networkConfiguration.awsvpcConfiguration' \
      --output json 2>"${aws_stderr_file}")"; then
      aws_rc=$?
      net_json=""
    fi
    aws_err="$(tr '\n' ' ' <"${aws_stderr_file}" | head -c 200 || true)"
    rm -f "${aws_stderr_file}"

    subnets_csv="$(jq -r '.subnets // [] | join(",")' <<<"${net_json}" 2>/dev/null || true)"
    sgs_csv="$(jq -r '.securityGroups // [] | join(",")' <<<"${net_json}" 2>/dev/null || true)"
    if [[ -n "${subnets_csv}" && -n "${sgs_csv}" ]]; then
      break
    fi
    if (( attempt < 5 )); then
      sleep 2
    fi
  done

  if [[ -z "${subnets_csv}" || -z "${sgs_csv}" ]]; then
    echo "[gitlab] WARN: Failed to resolve ECS network configuration for ${service_name}; cannot run EFS cleanup task." >&2
    local net_json_preview
    net_json_preview="$(tr '\n' ' ' <<<"${net_json}" | head -c 200 || true)"
    echo "[gitlab] DEBUG: aws_profile=${aws_profile} aws_region=${aws_region} cluster=${cluster} service_name=${service_name} aws_rc=${aws_rc} aws_err=${aws_err:-<empty>} net_json=${net_json_preview:-<empty>}" >&2
    if [[ "${required}" == "true" ]]; then
      exit 1
    fi
    return
  fi

  local overrides_json task_arn exit_code
  overrides_json="$(jq -n \
    --arg realm "${realm}" \
    --arg group "${group_full_path}" \
    --arg project "${project_path}" \
    '{
      containerOverrides: [
        {
          name: "gitlab-mirror",
          environment: [
            {name:"REALM", value:$realm},
            {name:"GROUP_FULL_PATH", value:$group},
            {name:"PROJECT_PATH", value:$project}
          ],
          command: [
            (
              "set -eu\n"
              + "apk add --no-cache util-linux coreutils >/dev/null\n"
              + "n8n_fs=\"${N8N_FILESYSTEM_PATH%/}\"\n"
              + "realm=\"${REALM:-}\"\n"
              + "group=\"${GROUP_FULL_PATH:-}\"\n"
              + "project=\"${PROJECT_PATH:-}\"\n"
              + "if [ -z \"$realm\" ] || [ -z \"$group\" ] || [ -z \"$project\" ]; then echo \"[cleanup] missing vars\" >&2; exit 1; fi\n"
              + "case \"$group\" in /*|*..*) echo \"[cleanup] invalid group\" >&2; exit 1 ;; esac\n"
              + "case \"$project\" in /*|*..*|*/*) echo \"[cleanup] invalid project\" >&2; exit 1 ;; esac\n"
              + "lock_root=\"${LOCK_ROOT:-$n8n_fs/qdrant}\"\n"
              + "lock_dir=\"${lock_root%/}/$realm\"\n"
              + "mkdir -p \"$lock_dir\"\n"
              + "lock_file=\"$lock_dir/.gitlab_mirror.lock\"\n"
              + "exec 9>\"$lock_file\"\n"
              + "flock -w 600 9\n"
              + "mirror_root=\"$n8n_fs/qdrant/$realm/gitlab/$group\"\n"
              + "echo \"[cleanup] mirror_root=$mirror_root\"\n"
              + "rm -rf \"$mirror_root/$project.git\"\n"
              + "case \"$project\" in\n"
              + "  *.wiki) : ;;\n"
              + "  *) rm -rf \"$mirror_root/$project.wiki.git\" ;;\n"
              + "esac\n"
              + "echo \"[cleanup] done\"\n"
            )
          ]
        }
      ]
    }')"

  echo "[gitlab] Deleting EFS mirror clones via ECS task: ${group_full_path}/${project_path}"
  task_arn="$(aws --profile "${aws_profile}" --region "${aws_region}" ecs run-task \
    --cluster "${cluster}" \
    --launch-type FARGATE \
    --task-definition "${mirror_td_arn}" \
    --network-configuration "awsvpcConfiguration={subnets=[${subnets_csv}],securityGroups=[${sgs_csv}],assignPublicIp=DISABLED}" \
    --overrides "${overrides_json}" \
    --query 'tasks[0].taskArn' \
    --output text 2>/dev/null || true)"
  if [[ -z "${task_arn}" || "${task_arn}" == "None" ]]; then
    echo "[gitlab] WARN: Failed to start ECS cleanup task." >&2
    if [[ "${required}" == "true" ]]; then
      exit 1
    fi
    return
  fi

  aws --profile "${aws_profile}" --region "${aws_region}" ecs wait tasks-stopped \
    --cluster "${cluster}" \
    --tasks "${task_arn}" >/dev/null

  exit_code="$(aws --profile "${aws_profile}" --region "${aws_region}" ecs describe-tasks \
    --cluster "${cluster}" \
    --tasks "${task_arn}" \
    --query 'tasks[0].containers[?name==`gitlab-mirror`].exitCode | [0]' \
    --output text 2>/dev/null || true)"

  if [[ -z "${exit_code}" || "${exit_code}" == "None" || "${exit_code}" != "0" ]]; then
    echo "[gitlab] WARN: ECS cleanup task failed (task=${task_arn}, exit_code=${exit_code:-unknown})." >&2
    if [[ "${required}" == "true" ]]; then
      exit 1
    fi
  fi
}

gitlab_wait_project_absent_by_full_path() {
  local full_path="$1"
  local encoded_path
  encoded_path="$(urlencode "${full_path}")"

  local attempt
  for attempt in {1..60}; do
    gitlab_request GET "/projects/${encoded_path}"
    if [[ "${GITLAB_LAST_STATUS}" == "404" ]]; then
      return
    fi
    sleep 2
  done

  echo "[gitlab] WARN: Project still exists (or deletion pending): ${full_path}"
}

itsm_purge_existing_projects_for_realm() {
  local realm="$1"
  local group_full_path="$2"

  if [[ "${ITSM_PURGE_EXISTING:-false}" != "true" ]]; then
    return
  fi

  echo "[gitlab] WARNING: Purging existing ITSM projects/templates for realm ${realm} in ${group_full_path}"

  local template_service_path service_path template_general_path general_path template_tech_path tech_path
  template_service_path="${ITSM_TEMPLATE_SERVICE_MANAGEMENT_PROJECT_PATH:-template-service-management}"
  service_path="${ITSM_SERVICE_MANAGEMENT_PROJECT_PATH:-service-management}"
  template_general_path="${ITSM_TEMPLATE_GENERAL_MANAGEMENT_PROJECT_PATH:-template-general-management}"
  general_path="${ITSM_GENERAL_MANAGEMENT_PROJECT_PATH:-general-management}"
  template_tech_path="${ITSM_TEMPLATE_TECHNICAL_MANAGEMENT_PROJECT_PATH:-template-technical-management}"
  tech_path="${ITSM_TECHNICAL_MANAGEMENT_PROJECT_PATH:-technical-management}"

  local -a delete_paths=(
    "${service_path}"
    "${general_path}"
    "${tech_path}"
    "${template_service_path}"
    "${template_general_path}"
    "${template_tech_path}"
  )

  local -a deleted_full_paths=()
  local path full_path project_id
  for path in "${delete_paths[@]}"; do
    full_path="${group_full_path}/${path}"
    project_id="$(gitlab_find_project_id_by_full_path "${full_path}" "${path}")"
    if [[ -z "${project_id}" ]]; then
      continue
    fi
    echo "[gitlab] Deleting project: ${full_path} (id=${project_id})"
    gitlab_delete_project_by_id "${project_id}"
    itsm_delete_efs_mirror_clones_for_project "${realm}" "${group_full_path}" "${path}"
    deleted_full_paths+=("${full_path}")
  done

  # NOTE: On macOS default bash (3.2), `set -u` + empty arrays can raise
  # "unbound variable" when expanding `"${arr[@]}"`. Guard on length.
  if ((${#deleted_full_paths[@]} > 0)); then
    local p
    for p in "${deleted_full_paths[@]}"; do
      gitlab_wait_project_absent_by_full_path "${p}"
    done
  fi
}

dry_run_plan_realm() {
  local realm="$1"
  local group_id="$2"
  local group_full_path="$3"
  local visibility="$4"

  local force_update
  force_update="$(effective_force_update_for_realm "${realm}")"

  local template_service_path service_path
  local template_general_path general_path
  local template_tech_path tech_path
  template_service_path="${ITSM_TEMPLATE_SERVICE_MANAGEMENT_PROJECT_PATH:-template-service-management}"
  service_path="${ITSM_SERVICE_MANAGEMENT_PROJECT_PATH:-service-management}"
  template_general_path="${ITSM_TEMPLATE_GENERAL_MANAGEMENT_PROJECT_PATH:-template-general-management}"
  general_path="${ITSM_GENERAL_MANAGEMENT_PROJECT_PATH:-general-management}"
  template_tech_path="${ITSM_TEMPLATE_TECHNICAL_MANAGEMENT_PROJECT_PATH:-template-technical-management}"
  tech_path="${ITSM_TECHNICAL_MANAGEMENT_PROJECT_PATH:-technical-management}"

  local template_service_full_path="${group_full_path}/${template_service_path}"
  local service_full_path="${group_full_path}/${service_path}"
  local template_general_full_path="${group_full_path}/${template_general_path}"
  local general_full_path="${group_full_path}/${general_path}"
  local template_tech_full_path="${group_full_path}/${template_tech_path}"
  local tech_full_path="${group_full_path}/${tech_path}"

  local template_service_id service_id template_general_id general_id template_tech_id tech_id
  template_service_id="$(gitlab_find_project_id_by_full_path "${template_service_full_path}" "${template_service_path}")"
  service_id="$(gitlab_find_project_id_by_full_path "${service_full_path}" "${service_path}")"
  template_general_id="$(gitlab_find_project_id_by_full_path "${template_general_full_path}" "${template_general_path}")"
  general_id="$(gitlab_find_project_id_by_full_path "${general_full_path}" "${general_path}")"
  template_tech_id="$(gitlab_find_project_id_by_full_path "${template_tech_full_path}" "${template_tech_path}")"
  tech_id="$(gitlab_find_project_id_by_full_path "${tech_full_path}" "${tech_path}")"

  local skip_if_exists="${ITSM_SKIP_IF_PROJECT_EXISTS:-true}"

  echo "[gitlab] DRY_RUN plan realm=${realm} group=${group_full_path} visibility=${visibility} force_update=${force_update} skip_if_exists=${skip_if_exists}"
  if [[ "${ITSM_PURGE_EXISTING:-false}" == "true" ]]; then
    echo "[gitlab] DRY_RUN would purge existing ITSM projects/templates before bootstrapping"
  fi
  echo "[gitlab] DRY_RUN - template(service): ${template_service_full_path} (exists=$([[ -n "${template_service_id}" ]] && echo true || echo false))"
  echo "[gitlab] DRY_RUN - template(general): ${template_general_full_path} (exists=$([[ -n "${template_general_id}" ]] && echo true || echo false))"
  echo "[gitlab] DRY_RUN - template(technical): ${template_tech_full_path} (exists=$([[ -n "${template_tech_id}" ]] && echo true || echo false))"
  echo "[gitlab] DRY_RUN - service project: ${service_full_path} (exists=$([[ -n "${service_id}" ]] && echo true || echo false))"
  echo "[gitlab] DRY_RUN - general project: ${general_full_path} (exists=$([[ -n "${general_id}" ]] && echo true || echo false))"
  echo "[gitlab] DRY_RUN - technical project: ${tech_full_path} (exists=$([[ -n "${tech_id}" ]] && echo true || echo false))"

  if [[ "${ITSM_PURGE_EXISTING:-false}" == "true" ]]; then
    if [[ -n "${service_id}" ]]; then
      itsm_delete_efs_mirror_clones_for_project "${realm}" "${group_full_path}" "${service_path}"
    fi
    if [[ -n "${general_id}" ]]; then
      itsm_delete_efs_mirror_clones_for_project "${realm}" "${group_full_path}" "${general_path}"
    fi
    if [[ -n "${tech_id}" ]]; then
      itsm_delete_efs_mirror_clones_for_project "${realm}" "${group_full_path}" "${tech_path}"
    fi
    if [[ -n "${template_service_id}" ]]; then
      itsm_delete_efs_mirror_clones_for_project "${realm}" "${group_full_path}" "${template_service_path}"
    fi
    if [[ -n "${template_general_id}" ]]; then
      itsm_delete_efs_mirror_clones_for_project "${realm}" "${group_full_path}" "${template_general_path}"
    fi
    if [[ -n "${template_tech_id}" ]]; then
      itsm_delete_efs_mirror_clones_for_project "${realm}" "${group_full_path}" "${template_tech_path}"
    fi
  fi

  if [[ -z "${template_service_id}" ]]; then
    echo "[gitlab] DRY_RUN would create template project (service): ${template_service_full_path} under group_id=${group_id}"
  else
    echo "[gitlab] DRY_RUN would update template repo/wiki content and ensure labels/boards/schedules (service): ${template_service_full_path}"
  fi
  if [[ -z "${template_general_id}" ]]; then
    echo "[gitlab] DRY_RUN would create template project (general): ${template_general_full_path} under group_id=${group_id}"
  else
    echo "[gitlab] DRY_RUN would update template repo/wiki content and ensure labels/boards (general): ${template_general_full_path}"
  fi
  if [[ -z "${template_tech_id}" ]]; then
    echo "[gitlab] DRY_RUN would create template project (technical): ${template_tech_full_path} under group_id=${group_id}"
  else
    echo "[gitlab] DRY_RUN would update template repo/wiki content and ensure labels/boards/branches (technical): ${template_tech_full_path}"
  fi

  local service_skip="false"
  if [[ -n "${service_id}" && "${skip_if_exists}" != "false" && "${force_update}" != "true" ]]; then
    service_skip="true"
  fi
  if [[ -z "${service_id}" ]]; then
    echo "[gitlab] DRY_RUN would fork service project from template: ${template_service_full_path} -> ${service_full_path}"
    echo "[gitlab] DRY_RUN would sync repo from template after fork: ${service_full_path}"
    echo "[gitlab] DRY_RUN would sync wiki from local templates to: ${service_full_path}"
    echo "[gitlab] DRY_RUN would ensure labels/boards/schedules in: ${service_full_path}"
  elif [[ "${service_skip}" == "true" ]]; then
    echo "[gitlab] DRY_RUN would skip service content bootstrap (project exists): ${service_full_path}"
  else
    echo "[gitlab] DRY_RUN would sync repo from template (force_update=${force_update}): ${service_full_path}"
    echo "[gitlab] DRY_RUN would sync wiki from local templates to: ${service_full_path}"
    echo "[gitlab] DRY_RUN would ensure labels/boards/schedules in: ${service_full_path}"
  fi

  local general_skip="false"
  if [[ -n "${general_id}" && "${skip_if_exists}" != "false" && "${force_update}" != "true" ]]; then
    general_skip="true"
  fi
  if [[ -z "${general_id}" ]]; then
    echo "[gitlab] DRY_RUN would fork general project from template: ${template_general_full_path} -> ${general_full_path}"
    echo "[gitlab] DRY_RUN would sync repo from template after fork: ${general_full_path}"
    echo "[gitlab] DRY_RUN would sync wiki from local templates to: ${general_full_path}"
    echo "[gitlab] DRY_RUN would ensure labels/boards in: ${general_full_path}"
  elif [[ "${general_skip}" == "true" ]]; then
    echo "[gitlab] DRY_RUN would skip general content bootstrap (project exists): ${general_full_path}"
  else
    echo "[gitlab] DRY_RUN would sync repo from template (force_update=${force_update}): ${general_full_path}"
    echo "[gitlab] DRY_RUN would sync wiki from local templates to: ${general_full_path}"
    echo "[gitlab] DRY_RUN would ensure labels/boards in: ${general_full_path}"
  fi

  local tech_skip="false"
  if [[ -n "${tech_id}" && "${skip_if_exists}" != "false" && "${force_update}" != "true" ]]; then
    tech_skip="true"
  fi
  if [[ -z "${tech_id}" ]]; then
    echo "[gitlab] DRY_RUN would fork technical project from template: ${template_tech_full_path} -> ${tech_full_path}"
    echo "[gitlab] DRY_RUN would sync repo from template after fork: ${tech_full_path}"
    echo "[gitlab] DRY_RUN would sync wiki from local templates to: ${tech_full_path}"
    echo "[gitlab] DRY_RUN would ensure labels/boards/branches in: ${tech_full_path}"
  elif [[ "${tech_skip}" == "true" ]]; then
    echo "[gitlab] DRY_RUN would skip technical content bootstrap (project exists): ${tech_full_path}"
  else
    echo "[gitlab] DRY_RUN would sync repo from template (force_update=${force_update}): ${tech_full_path}"
    echo "[gitlab] DRY_RUN would sync wiki from local templates to: ${tech_full_path}"
    echo "[gitlab] DRY_RUN would ensure labels/boards/branches in: ${tech_full_path}"
  fi
}

ensure_service_bootstrap() {
  local realm="$1"
  local group_id="$2"
  local group_full_path="$3"
  local project_visibility="$4"
  local grafana_base_url="$5"
  local keycloak_admin_console_url="${6:-}"
  local zulip_base_url="${7:-}"
  local n8n_base_url="${8:-}"
  local force_update
  force_update="$(effective_force_update_for_realm "${realm}")"

  local template_name template_path itsm_name itsm_path service_management_path
  local general_management_path tech_management_path
  template_name="${ITSM_TEMPLATE_SERVICE_MANAGEMENT_PROJECT_NAME:-template-service-management}"
  template_path="${ITSM_TEMPLATE_SERVICE_MANAGEMENT_PROJECT_PATH:-template-service-management}"
  itsm_name="${ITSM_SERVICE_MANAGEMENT_PROJECT_NAME:-service-management}"
  itsm_path="${ITSM_SERVICE_MANAGEMENT_PROJECT_PATH:-service-management}"
  service_management_path="${itsm_path}"
  general_management_path="${ITSM_GENERAL_MANAGEMENT_PROJECT_PATH:-general-management}"
  tech_management_path="${ITSM_TECHNICAL_MANAGEMENT_PROJECT_PATH:-technical-management}"
  local sample_service_id sample_service_file_id
  sample_service_file_id="${ITSM_CMDB_SAMPLE_FILE_ID:-web-service}"
  sample_service_id="${ITSM_CMDB_SAMPLE_SERVICE_ID:-sulu}"

  local template_full_path="${group_full_path}/${template_path}"
  local itsm_full_path="${group_full_path}/${itsm_path}"
  local general_full_path="${group_full_path}/${general_management_path}"
  local tech_full_path="${group_full_path}/${tech_management_path}"

  local template_project_id
  template_project_id="$(gitlab_find_project_id_by_full_path "${template_full_path}" "${template_path}")"
  if [[ -z "${template_project_id}" ]]; then
    echo "[gitlab] Creating template project: ${template_full_path}"
    gitlab_create_project "${template_name}" "${template_path}" "${group_id}" "${project_visibility}"
    template_project_id="$(gitlab_find_project_id_by_full_path "${template_full_path}" "${template_path}")"
    require_var "template project id" "${template_project_id}"
  else
    echo "[gitlab] Template project exists: ${template_full_path}"
  fi

  local itsm_project_id
  itsm_project_id="$(gitlab_find_project_id_by_full_path "${itsm_full_path}" "${itsm_path}")"
  local itsm_forked="false"
  local itsm_existed="false"
  local itsm_skip_content="false"
  if [[ -z "${itsm_project_id}" ]]; then
    echo "[gitlab] Forking ITSM project: ${itsm_full_path}"
    gitlab_fork_project "${template_project_id}" "${group_id}" "${itsm_name}" "${itsm_path}"
    itsm_forked="true"
    local attempt
    for attempt in {1..10}; do
      itsm_project_id="$(gitlab_find_project_id_by_full_path "${itsm_full_path}" "${itsm_path}")"
      if [[ -n "${itsm_project_id}" ]]; then
        break
      fi
      sleep 1
    done
    require_var "ITSM project id" "${itsm_project_id}"
  else
    itsm_existed="true"
    echo "[gitlab] ITSM project exists: ${itsm_full_path}"
    if [[ "${ITSM_SKIP_IF_PROJECT_EXISTS:-true}" != "false" && "${force_update}" != "true" ]]; then
      itsm_skip_content="true"
      echo "[gitlab] ITSM content bootstrap skipped (project exists): ${itsm_full_path}"
    fi
  fi

  local branch
  branch="$(gitlab_project_default_branch "${itsm_project_id}")"
  if [[ -z "${branch}" ]]; then
    branch="main"
  fi

  local template_branch
  template_branch="$(gitlab_project_default_branch "${template_project_id}")"
  if [[ -z "${template_branch}" ]]; then
    template_branch="main"
  fi

  local rendered_grafana_url
  rendered_grafana_url="${grafana_base_url%/}"
  if [[ -z "${rendered_grafana_url}" || "${rendered_grafana_url}" == "null" ]]; then
    rendered_grafana_url="(Grafana URL not configured)"
  fi

  if [[ -z "${keycloak_admin_console_url}" || "${keycloak_admin_console_url}" == "null" ]]; then
    keycloak_admin_console_url="(Keycloak admin URL not configured)"
  fi
  if [[ -z "${zulip_base_url}" || "${zulip_base_url}" == "null" ]]; then
    zulip_base_url="(Zulip URL not configured)"
  fi
  if [[ -z "${n8n_base_url}" || "${n8n_base_url}" == "null" ]]; then
    n8n_base_url="(n8n URL not configured)"
  fi

  if [[ "${ITSM_FILES_ONLY:-false}" == "true" ]]; then
    itsm_update_service_management_files_only \
      "${realm}" \
      "${group_full_path}" \
      "${template_project_id}" \
      "${template_branch}" \
      "${itsm_project_id}" \
      "${branch}" \
      "${grafana_base_url}"
    return 0
  fi

  local labels_data
  labels_data="$(
    cat <<'EOF'
種別：インシデント|#FF4D4F|障害・システム不具合
種別：サービス要求|#1890FF|アカウント作成等の依頼
種別：問い合わせ|#52C41A|質問・確認
種別：改善提案|#722ED1|改善の提案
種別：問題|#722ED1|根本原因分析用
種別：イベント|#FAAD14|監視イベント
KPI/インシデント件数|#FF4D4F|月間障害件数
KPI/MTTR|#722ED1|平均復旧時間
KPI/SLA達成率|#52C41A|SLA/SLO達成率
KPI/一次完結率|#13C2C2|サービスデスク一次完結率
KPI/サービス要求処理時間|#1890FF|サービス要求の平均処理時間
KPI/顧客満足度|#FAAD14|顧客満足度（CSAT）
KPI/初回応答時間|#13C2C2|初回応答までの時間
KPI/解決時間|#722ED1|解決までの時間
KPI/バックログ|#8C8C8C|未処理件数
KPI/再オープン率|#FAAD14|再オープン率
状態：新規|#D9D9D9|受付直後
状態：調査中|#13C2C2|原因調査中
状態：対応中|#1890FF|対応作業中
状態：暫定対応|#FAAD14|回避策実施
状態：解決|#52C41A|解決済
状態：クローズ|#389E0D|完了
優先度：P1（業務停止）|#A8071A|全社影響
優先度：P2（業務影響大）|#D46B08|一部業務停止
優先度：P3（業務影響小）|#FADB14|軽微影響
優先度：P4（業務影響極小）|#52C41A|影響ごく小
緊急度：高|#A8071A|高い緊急度
緊急度：中|#D46B08|中程度の緊急度
緊急度：低|#52C41A|低い緊急度
影響度：全社|#A8071A|全社影響
影響度：部門|#D46B08|部門影響
影響度：個人|#52C41A|個人影響
担当：インフラ|#0050B3|インフラチーム
担当：アプリ|#096DD9|アプリチーム
担当：ネットワーク|#003A8C|ネットワーク
担当：セキュリティ|#531DAB|セキュリティ
チャネル：Zulip|#2F54EB|受付チャネル
自動：Zulip同期|#8C8C8C|Zulip連携で更新
自動：自動作成|#8C8C8C|自動起票
ナレッジ：手順書|#2F54EB|運用手順
ナレッジ：FAQ|#13C2C2|FAQ
ナレッジ：事例|#52C41A|対応事例
ナレッジ：障害対応|#FAAD14|障害対応記録
改善：提案|#722ED1|改善提案
改善：対応中|#1890FF|改善対応中
改善：完了|#52C41A|改善完了
集計：対象|#000000|レポート集計対象
集計：除外|#8C8C8C|集計除外
変更：申請中|#0050B3|変更申請の受付
  変更：審査中|#096DD9|変更諮問委員会（承認者）/承認待ち
変更：承認済|#52C41A|承認完了
変更：実施中|#FAAD14|変更実施中
変更：完了|#389E0D|変更完了
変更：中止|#8C8C8C|変更中止
サービス要求：受付|#1890FF|サービス要求の受付
サービス要求：確認中|#13C2C2|要件確認・調査中
サービス要求：対応中|#FAAD14|対応実施中
サービス要求：完了|#52C41A|対応完了
サービス要求：却下|#8C8C8C|対応不可・却下
EOF
  )"

  # Template project: ensure labels exist as well (so template boards/etc can be created consistently).
  local label_total label_index
  label_total="$(printf '%s\n' "${labels_data}" | grep -c '|' || true)"
  label_index=0
  echo "[gitlab] Ensuring labels (${label_total}) for template ${template_full_path}"
  local line name color description
  while IFS='|' read -r name color description; do
    [[ -z "${name}" ]] && continue
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    gitlab_ensure_label "${template_project_id}" "${name}" "${color}" "${description}" "${force_update}"
    label_index=$((label_index + 1))
    if ((label_index % 20 == 0)); then
      echo "[gitlab] Template label progress: ${label_index}/${label_total}"
    fi
  done <<<"${labels_data}"

  if [[ "${itsm_skip_content}" != "true" ]]; then
    local line name color description
    local label_total label_index
    label_total="$(printf '%s\n' "${labels_data}" | grep -c '|')"
    label_index=0
    echo "[gitlab] Ensuring labels (${label_total}) for ${itsm_full_path}"
    while IFS='|' read -r name color description; do
      [[ -z "${name}" ]] && continue
      name="${name#"${name%%[![:space:]]*}"}"
      name="${name%"${name##*[![:space:]]}"}"
      gitlab_ensure_label "${itsm_project_id}" "${name}" "${color}" "${description}" "${force_update}"
      label_index=$((label_index + 1))
      if ((label_index % 20 == 0)); then
        echo "[gitlab] Label progress: ${label_index}/${label_total}"
      fi
    done <<<"${labels_data}"
  fi

  local incident_board_name change_board_name service_request_board_name
  local board_specs
  local board_label_force_update="${force_update}"
  incident_board_name="${ITSM_INCIDENT_BOARD_NAME:-インシデント管理}"
  change_board_name="${ITSM_CHANGE_BOARD_NAME:-変更管理}"
  service_request_board_name="${ITSM_SERVICE_REQUEST_BOARD_NAME:-サービス要求管理}"
  board_specs="$(
    cat <<EOF
${incident_board_name}|インシデント管理|状態：新規,状態：調査中,状態：対応中,状態：暫定対応,状態：解決,状態：クローズ|タグ：インシデント管理
${service_request_board_name}|サービス要求管理|サービス要求：受付,サービス要求：確認中,サービス要求：対応中,サービス要求：完了,サービス要求：却下|タグ：サービス要求管理
問題管理|問題管理|問題：受付,問題：調査中,問題：恒久対策,問題：承認,問題：完了|タグ：問題管理
${change_board_name}|変更管理|変更：申請中,変更：審査中,変更：承認済,変更：実施中,変更：完了,変更：中止|タグ：変更管理
重大インシデント対応|重大インシデント対応|重大インシデント：宣言,重大インシデント：対応中,重大インシデント：復旧,重大インシデント：レビュー|タグ：重大インシデント
サービスデスク一次対応|サービスデスク一次対応|一次対応：受付,一次対応：対応中,一次対応：エスカレーション,一次対応：完了|タグ：サービスデスク
ナレッジ作成・レビュー|ナレッジ作成・レビュー|ナレッジ：作成,ナレッジ：レビュー,ナレッジ：承認,ナレッジ：公開|タグ：ナレッジ
継続的改善|継続的改善|改善：提案,改善：評価,改善：計画,改善：実施,改善：効果確認,改善：完了|タグ：継続的改善
変更評価・承認（変更諮問委員会（承認者））|変更評価・承認|変更諮問委員会（承認者）：申請,変更諮問委員会（承認者）：審査,変更諮問委員会（承認者）：承認,変更諮問委員会（承認者）：却下,変更諮問委員会（承認者）：完了|タグ：変更諮問委員会（承認者）
ポストインシデントレビュー（PIR）|PIR|PIR：準備,PIR：分析,PIR：対策,PIR：完了|タグ：PIR
監視イベントトリアージ|監視イベントトリアージ|イベント：検知,イベント：判定,イベント：対応,イベント：完了|タグ：監視イベント
SLA/OLA 逸脱フォローアップ|SLA/OLA逸脱フォローアップ|SLA：検知,SLA：調査,SLA：是正,SLA：完了|タグ：SLA/OLA
変更後の検証・回帰テスト|回帰テスト|回帰テスト：計画,回帰テスト：実施,回帰テスト：結果確認,回帰テスト：完了|タグ：回帰テスト
依存関係・影響分析|影響分析|影響分析：受付,影響分析：分析,影響分析：レビュー,影響分析：完了|タグ：影響分析
変更リリース準備|変更リリース準備|リリース準備：計画,リリース準備：準備,リリース準備：リハーサル,リリース準備：実施,リリース準備：完了|タグ：リリース準備
問題既知化（Known Error）|問題既知化|既知問題：登録,既知問題：回避策,既知問題：確認,既知問題：完了|タグ：既知問題
監視アラート精査|監視アラート精査|アラート：確認,アラート：抑制,アラート：修正,アラート：完了|タグ：アラート精査
標準変更（定型作業）|標準変更|標準変更：申請,標準変更：承認,標準変更：実施,標準変更：完了|タグ：標準変更
変更スケジュール調整|変更スケジュール調整|変更スケジュール：受付,変更スケジュール：調整,変更スケジュール：確定,変更スケジュール：完了|タグ：変更スケジュール
依頼/問い合わせ一次仕分け|一次仕分け|一次仕分け：受付,一次仕分け：振分,一次仕分け：完了|タグ：一次仕分け
サービス障害復旧計画|サービス障害復旧計画|復旧計画：作成,復旧計画：レビュー,復旧計画：承認,復旧計画：演習,復旧計画：完了|タグ：復旧計画
変更影響調整（業務影響）|変更影響調整|業務影響：評価,業務影響：調整,業務影響：承認,業務影響：完了|タグ：業務影響
運用手順の整備|運用手順の整備|手順：作成,手順：レビュー,手順：承認,手順：公開|タグ：運用手順
サービスカタログ整備|サービスカタログ整備|カタログ：作成,カタログ：レビュー,カタログ：公開,カタログ：改定|タグ：サービスカタログ
サービスレベル改善提案|サービスレベル改善提案|SL改善：提案,SL改善：評価,SL改善：計画,SL改善：実施,SL改善：完了|タグ：サービスレベル
コミュニケーション/ステークホルダー連携|ステークホルダー連携|連携：通知,連携：調整,連携：合意,連携：完了|タグ：ステークホルダー
コンプライアンス/監査対応|監査対応|監査：依頼,監査：対応中,監査：是正,監査：完了|タグ：監査対応
リスク評価・対策|リスク評価・対策|リスク：識別,リスク：評価,リスク：対策,リスク：完了|タグ：リスク管理
SLAレポート作成|SLAレポート作成|SLAレポート：準備,SLAレポート：集計,SLAレポート：レビュー,SLAレポート：公開|タグ：SLAレポート
継続的改善アイデア管理|改善アイデア管理|改善アイデア：提案,改善アイデア：評価,改善アイデア：実施,改善アイデア：効果確認,改善アイデア：完了|タグ：改善アイデア
EOF
  )"

  local incident_template service_request_template customer_request_template problem_template report_template change_template
  local sla_slo_definition_template
  local mention_mapping_template sla_master_template monitoring_unification_template
  local workflow_catalog_template escalation_matrix_template ola_master_template uc_master_template
  local cmdb_template runbook_template ci_template report_script grafana_sync_script zulip_stream_sync_script readme_template audit_readme_template
  local raci_template role_guide_template
  local grafana_url
  grafana_url="${grafana_base_url}"
  if [[ -z "${grafana_base_url}" || "${grafana_base_url}" == "null" ]]; then
    grafana_url="https://grafana.example.com"
    echo "[gitlab] WARN: grafana base_url not found for ${group_full_path}, using placeholder."
  fi
  grafana_url="${grafana_url%/}"

  local itsm_event_inbox_dashboard_uid itsm_event_inbox_dashboard_title
  local itsm_event_inbox_panel_id itsm_event_inbox_panel_title itsm_event_inbox_url
  itsm_event_inbox_dashboard_uid="$(echo "${ITSM_MONITORING_CONTEXT_JSON:-{}}" | jq -r --arg realm "${realm}" '.[$realm].grafana.itsm_event_inbox.dashboard_uid // empty' 2>/dev/null || true)"
  itsm_event_inbox_dashboard_title="$(echo "${ITSM_MONITORING_CONTEXT_JSON:-{}}" | jq -r --arg realm "${realm}" '.[$realm].grafana.itsm_event_inbox.dashboard_title // empty' 2>/dev/null || true)"
  itsm_event_inbox_panel_id="$(echo "${ITSM_MONITORING_CONTEXT_JSON:-{}}" | jq -r --arg realm "${realm}" '.[$realm].grafana.itsm_event_inbox.panel_id // empty' 2>/dev/null || true)"
  itsm_event_inbox_panel_title="$(echo "${ITSM_MONITORING_CONTEXT_JSON:-{}}" | jq -r --arg realm "${realm}" '.[$realm].grafana.itsm_event_inbox.panel_title // empty' 2>/dev/null || true)"
  itsm_event_inbox_url=""
  if [[ -n "${itsm_event_inbox_dashboard_uid}" ]]; then
    itsm_event_inbox_url="${grafana_url}/d/${itsm_event_inbox_dashboard_uid}/itsm-event-inbox"
    if [[ -n "${itsm_event_inbox_panel_id}" ]]; then
      itsm_event_inbox_url="${itsm_event_inbox_url}?viewPanel=${itsm_event_inbox_panel_id}"
    fi
  fi

  if [[ -z "${itsm_event_inbox_dashboard_title}" ]]; then
    itsm_event_inbox_dashboard_title="ITSM Event Inbox"
  fi
  if [[ -z "${itsm_event_inbox_panel_title}" ]]; then
    itsm_event_inbox_panel_title="Event Inbox (Annotations)"
  fi
  if [[ -z "${itsm_event_inbox_dashboard_uid}" ]]; then
    itsm_event_inbox_dashboard_uid="(unset)"
  fi
  if [[ -z "${itsm_event_inbox_panel_id}" ]]; then
    itsm_event_inbox_panel_id="(unset)"
  fi
  if [[ -z "${itsm_event_inbox_url}" ]]; then
    itsm_event_inbox_url="(unset)"
  fi
  incident_template="$(load_template "service-management/issue_templates/01_incident.md.tpl")"

  service_request_template="$(load_template "service-management/issue_templates/02_service_request.md.tpl")"

  customer_request_template="$(load_template "service-management/issue_templates/06_customer_request.md.tpl")"

  problem_template="$(load_template "service-management/issue_templates/03_problem.md.tpl")"

  change_template="$(load_template "service-management/issue_templates/04_change.md.tpl")"

  sla_slo_definition_template="$(load_template "service-management/issue_templates/05_sla_slo_definition.md.tpl")"

  report_template="$(load_template "service-management/docs/monthly_report_template.md.tpl")"

  mention_mapping_template="$(load_template "service-management/docs/mention_user_mapping.md.tpl")"

  sla_master_template="$(load_template "service-management/docs/sla_master.md.tpl")"

  monitoring_unification_template="$(load_template "service-management/docs/monitoring_unification_grafana.md.tpl")"

  workflow_catalog_template="$(load_template "service-management/docs/workflow_catalog.md.tpl")"
  escalation_matrix_template="$(load_template "service-management/docs/escalation_matrix.md.tpl")"
  ola_master_template="$(load_template "service-management/docs/ola_master.md.tpl")"
  uc_master_template="$(load_template "service-management/docs/uc_master.md.tpl")"

  readme_template="$(load_and_render_template "service-management/README.md.tpl" \
    "REALM" "${realm}" \
    "KEYCLOAK_ADMIN_CONSOLE_URL" "${keycloak_admin_console_url}" \
    "N8N_BASE_URL" "${n8n_base_url}" \
    "GRAFANA_BASE_URL" "${rendered_grafana_url}" \
    "GITLAB_BASE_URL" "${GITLAB_BASE_URL}" \
    "GENERAL_MANAGEMENT_PROJECT_PATH" "${general_full_path}" \
    "TECHNICAL_MANAGEMENT_PROJECT_PATH" "${tech_full_path}" \
  )"

  audit_readme_template="$(load_template "service-management/docs/audit_readme.md.tpl")"

  raci_template="$(load_template "service-management/docs/raci.md.tpl")"

  role_guide_template="$(load_template "service-management/docs/role_guide.md.tpl")"


  local cmdb_id cmdb_org cmdb_service
  cmdb_org="$(printf '%s' "${group_full_path}" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '-' | sed 's/-$//')"
  cmdb_service="$(printf '%s' "${sample_service_id}" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '-' | sed 's/-$//')"
  cmdb_id="${cmdb_org}-${cmdb_service}-001"
	  cmdb_template="$(
	    load_and_render_template "service-management/cmdb/sulu.md.tpl" \
	      "CMDB_ID" "${cmdb_id}" \
	      "ORG_ID" "${group_full_path}" \
	      "ORG_NAME" "${group_full_path}" \
	      "SERVICE_ID" "${sample_service_id}" \
	      "GRAFANA_BASE_URL" "${grafana_base_url}" \
	      "GRAFANA_ITSM_EVENT_INBOX_DASHBOARD_UID" "${itsm_event_inbox_dashboard_uid}" \
	      "GRAFANA_ITSM_EVENT_INBOX_DASHBOARD_TITLE" "${itsm_event_inbox_dashboard_title}" \
	      "GRAFANA_ITSM_EVENT_INBOX_PANEL_ID" "${itsm_event_inbox_panel_id}" \
	      "GRAFANA_ITSM_EVENT_INBOX_PANEL_TITLE" "${itsm_event_inbox_panel_title}" \
	      "GRAFANA_ITSM_EVENT_INBOX_URL" "${itsm_event_inbox_url}" \
	      "GITLAB_PROJECT_URL" "${GITLAB_BASE_URL}/${group_full_path}/${sample_service_id}"
	  )"
  runbook_template="$(
    load_and_render_template "service-management/cmdb/runbook/sulu.md.tpl" \
      "SERVICE_NAME" "Sulu" \
      "SERVICE_ID" "${sample_service_id}" \
      "ENVIRONMENT" "本番" \
      "ORG_ID" "${group_full_path}" \
      "GITLAB_PROJECT_URL" "${GITLAB_BASE_URL}/${group_full_path}/${sample_service_id}"
  )"

  ci_template="$(
    cat <<'EOF'
stages:
  - validate
  - sync

cmdb_validate:
  stage: validate
  image: alpine
  script:
    - apk add --no-cache yq curl
    - |
      set -euo pipefail
      for f in cmdb/**/*.md; do
        echo "Checking $f"
        CMDB_ID=$(yq '.cmdb_id' "$f")
        ORG_ID=$(yq '.組織ID' "$f")
        SERVICE_ID=$(yq '.サービスID' "$f")
        GRAFANA_URL=$(yq '.grafana.base_url' "$f")
        DASH_UID=$(yq '.grafana.dashboard_uid' "$f")
        if [[ -z "$CMDB_ID" || "$CMDB_ID" == "null" ]]; then
          echo "Missing cmdb_id in $f" >&2
          exit 1
        fi
        if [[ -z "$ORG_ID" || "$ORG_ID" == "null" || -z "$SERVICE_ID" || "$SERVICE_ID" == "null" ]]; then
          echo "Missing 組織ID/サービスID in $f" >&2
          exit 1
        fi
        if [[ -n "$GRAFANA_URL" && "$GRAFANA_URL" != "null" && -n "$DASH_UID" && "$DASH_UID" != "null" ]]; then
          curl -sf "$GRAFANA_URL/d/$DASH_UID" >/dev/null
        fi
      done

grafana_sync:
  stage: sync
  image: alpine
  rules:
    - if: '$CI_PIPELINE_SOURCE == "schedule"'
    - changes:
        - cmdb/**/*.md
        - scripts/grafana/sync_cmdb_dashboards.sh
  script:
    - apk add --no-cache bash curl jq yq
    - bash scripts/grafana/sync_cmdb_dashboards.sh

zulip_stream_sync:
  stage: sync
  image: alpine
  rules:
    - if: '$CI_PIPELINE_SOURCE == "schedule"'
    - changes:
        - cmdb/**/*.md
        - scripts/cmdb/sync_zulip_streams.sh
  script:
    - apk add --no-cache bash curl jq yq
    - bash scripts/cmdb/sync_zulip_streams.sh
EOF
  )"

  report_script="$(
    cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

REPORT_PATH="reports/cmdb_status.md"
mkdir -p "$(dirname "${REPORT_PATH}")"

echo "| cmdb_id | サービス名 | Grafana | 最終更新 |" > "${REPORT_PATH}"
echo "|---|---|---|---|" >> "${REPORT_PATH}"

for f in cmdb/**/*.md; do
  CMDB_ID=$(yq '.cmdb_id' "$f")
  SERVICE_NAME=$(yq '.サービス名' "$f")
  DASH_UID=$(yq '.grafana.dashboard_uid' "$f")
  UPDATED=$(yq '.最終更新日' "$f")
  echo "| ${CMDB_ID} | ${SERVICE_NAME} | ${DASH_UID} | ${UPDATED} |" >> "${REPORT_PATH}"
done
echo "Wrote ${REPORT_PATH}"
EOF
  )"

  grafana_sync_script="$(load_template "service-management/scripts/grafana/sync_cmdb_dashboards.sh.tpl")"
  zulip_stream_sync_script="$(load_template "service-management/scripts/cmdb/sync_zulip_streams.sh")"

  if [[ "${force_update}" == "true" ]]; then
    gitlab_upsert_file "${template_project_id}" "${branch}" "README.md" "${readme_template}" "Update README"
    gitlab_upsert_file "${template_project_id}" "${branch}" "docs/audit_readme.md" "${audit_readme_template}" "Update audit README"
    gitlab_upsert_file "${template_project_id}" "${branch}" "docs/raci.md" "${raci_template}" "Update RACI"
    gitlab_upsert_file "${template_project_id}" "${branch}" "docs/role_guide.md" "${role_guide_template}" "Update role guide"
    gitlab_upsert_file "${template_project_id}" "${branch}" "$(prefixed_template_path "01" "incident")" "${incident_template}" "Update incident issue template"
    gitlab_upsert_file "${template_project_id}" "${branch}" "$(prefixed_template_path "02" "service_request")" "${service_request_template}" "Update service request issue template"
    gitlab_upsert_file "${template_project_id}" "${branch}" "$(prefixed_template_path "06" "customer_request")" "${customer_request_template}" "Update customer request issue template"
    gitlab_upsert_file "${template_project_id}" "${branch}" "$(prefixed_template_path "03" "problem")" "${problem_template}" "Update problem issue template"
    gitlab_upsert_file "${template_project_id}" "${branch}" "$(prefixed_template_path "04" "change")" "${change_template}" "Update change issue template"
    gitlab_upsert_file "${template_project_id}" "${branch}" "$(prefixed_template_path "05" "sla_slo_definition")" "${sla_slo_definition_template}" "Update sla/slo definition issue template"
    gitlab_upsert_file "${template_project_id}" "${branch}" "docs/sla_master.md" "${sla_master_template}" "Update SLA/SLO master template"
    gitlab_upsert_file "${template_project_id}" "${branch}" "docs/monitoring_unification_grafana.md" "${monitoring_unification_template}" "Update monitoring unification guide"
    gitlab_upsert_file "${template_project_id}" "${branch}" "docs/workflow_catalog.md" "${workflow_catalog_template}" "Update workflow catalog"
    gitlab_upsert_file "${template_project_id}" "${branch}" "docs/escalation_matrix.md" "${escalation_matrix_template}" "Update escalation matrix"
    gitlab_upsert_file "${template_project_id}" "${branch}" "docs/ola_master.md" "${ola_master_template}" "Update OLA master"
    gitlab_upsert_file "${template_project_id}" "${branch}" "docs/uc_master.md" "${uc_master_template}" "Update UC master"
    gitlab_upsert_file "${template_project_id}" "${branch}" "docs/monthly_report_template.md" "${report_template}" "Update monthly report template"
    gitlab_upsert_file "${template_project_id}" "${branch}" "docs/mention_user_mapping.md" "${mention_mapping_template}" "Update mention user mapping"
    gitlab_upsert_file "${template_project_id}" "${branch}" ".gitlab-ci.yml" "${ci_template}" "Update CMDB validation pipeline"
    gitlab_upsert_file "${template_project_id}" "${branch}" "scripts/cmdb/generate_cmdb_report.sh" "${report_script}" "Update CMDB report generator"
    gitlab_upsert_file "${template_project_id}" "${branch}" "scripts/grafana/sync_cmdb_dashboards.sh" "${grafana_sync_script}" "Update Grafana CMDB sync script"
    gitlab_upsert_file "${template_project_id}" "${branch}" "scripts/cmdb/sync_zulip_streams.sh" "${zulip_stream_sync_script}" "Update Zulip stream sync script"
    gitlab_apply_templates_in_dir "${template_project_id}" "${branch}" "service-management" "docs/usecases" "true" \
      "SERVICE_MANAGEMENT_PROJECT_PATH" "${template_path}" \
      "GENERAL_MANAGEMENT_PROJECT_PATH" "${general_management_path}" \
      "TECHNICAL_MANAGEMENT_PROJECT_PATH" "${tech_management_path}" \
      "GITLAB_BASE_URL" "${GITLAB_BASE_URL}" \
      "GROUP_FULL_PATH" "${group_full_path}" \
      "GRAFANA_BASE_URL" "${grafana_base_url}"
    gitlab_apply_templates_in_dir "${template_project_id}" "${branch}" "service-management" "docs/dashboards" "true" \
      "SERVICE_MANAGEMENT_PROJECT_PATH" "${template_path}" \
      "GITLAB_BASE_URL" "${GITLAB_BASE_URL}" \
      "GROUP_FULL_PATH" "${group_full_path}" \
      "GRAFANA_BASE_URL" "${grafana_base_url}"
    gitlab_apply_templates_in_dir "${template_project_id}" "${branch}" "service-management" "docs/reports" "true" \
      "SERVICE_MANAGEMENT_PROJECT_PATH" "${template_path}" \
      "GITLAB_BASE_URL" "${GITLAB_BASE_URL}" \
      "GROUP_FULL_PATH" "${group_full_path}" \
      "GRAFANA_BASE_URL" "${grafana_base_url}"
  else
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "README.md" "${readme_template}" "Add README"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "docs/audit_readme.md" "${audit_readme_template}" "Add audit README"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "docs/raci.md" "${raci_template}" "Add RACI"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "docs/role_guide.md" "${role_guide_template}" "Add role guide"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "$(prefixed_template_path "01" "incident")" "${incident_template}" "Add incident issue template"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "$(prefixed_template_path "02" "service_request")" "${service_request_template}" "Add service request issue template"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "$(prefixed_template_path "06" "customer_request")" "${customer_request_template}" "Add customer request issue template"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "$(prefixed_template_path "03" "problem")" "${problem_template}" "Add problem issue template"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "$(prefixed_template_path "04" "change")" "${change_template}" "Add change issue template"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "$(prefixed_template_path "05" "sla_slo_definition")" "${sla_slo_definition_template}" "Add sla/slo definition issue template"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "docs/sla_master.md" "${sla_master_template}" "Add SLA/SLO master template"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "docs/monitoring_unification_grafana.md" "${monitoring_unification_template}" "Add monitoring unification guide"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "docs/workflow_catalog.md" "${workflow_catalog_template}" "Add workflow catalog"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "docs/escalation_matrix.md" "${escalation_matrix_template}" "Add escalation matrix"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "docs/ola_master.md" "${ola_master_template}" "Add OLA master"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "docs/uc_master.md" "${uc_master_template}" "Add UC master"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "docs/monthly_report_template.md" "${report_template}" "Add monthly report template"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "docs/mention_user_mapping.md" "${mention_mapping_template}" "Add mention user mapping"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" ".gitlab-ci.yml" "${ci_template}" "Add CMDB validation pipeline"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "scripts/cmdb/generate_cmdb_report.sh" "${report_script}" "Add CMDB report generator"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "scripts/grafana/sync_cmdb_dashboards.sh" "${grafana_sync_script}" "Add Grafana CMDB sync script"
    gitlab_create_file_if_missing "${template_project_id}" "${branch}" "scripts/cmdb/sync_zulip_streams.sh" "${zulip_stream_sync_script}" "Add Zulip stream sync script"
    gitlab_apply_templates_in_dir "${template_project_id}" "${branch}" "service-management" "docs/usecases" "false" \
      "SERVICE_MANAGEMENT_PROJECT_PATH" "${template_path}" \
      "GENERAL_MANAGEMENT_PROJECT_PATH" "${general_management_path}" \
      "TECHNICAL_MANAGEMENT_PROJECT_PATH" "${tech_management_path}" \
      "GITLAB_BASE_URL" "${GITLAB_BASE_URL}" \
      "GROUP_FULL_PATH" "${group_full_path}" \
      "GRAFANA_BASE_URL" "${grafana_base_url}"
    gitlab_apply_templates_in_dir "${template_project_id}" "${branch}" "service-management" "docs/dashboards" "false" \
      "SERVICE_MANAGEMENT_PROJECT_PATH" "${template_path}" \
      "GITLAB_BASE_URL" "${GITLAB_BASE_URL}" \
      "GROUP_FULL_PATH" "${group_full_path}" \
      "GRAFANA_BASE_URL" "${grafana_base_url}"
    gitlab_apply_templates_in_dir "${template_project_id}" "${branch}" "service-management" "docs/reports" "false" \
      "SERVICE_MANAGEMENT_PROJECT_PATH" "${template_path}" \
      "GITLAB_BASE_URL" "${GITLAB_BASE_URL}" \
      "GROUP_FULL_PATH" "${group_full_path}" \
      "GRAFANA_BASE_URL" "${grafana_base_url}"
  fi
  gitlab_upsert_file "${template_project_id}" "${branch}" "cmdb/${group_full_path}/${sample_service_file_id}.md" "${cmdb_template}" "Update CMDB template"
  gitlab_upsert_file "${template_project_id}" "${branch}" "cmdb/runbook/sulu.md" "${runbook_template}" "Update runbook template"

  if [[ "${itsm_skip_content}" != "true" ]]; then
    if [[ "${itsm_forked}" == "true" || "${force_update}" == "true" ]]; then
      gitlab_sync_repo_from_template \
        "${template_full_path}" "${template_project_id}" "${template_branch}" \
        "${itsm_full_path}" "${itsm_project_id}" "${branch}"
    fi
    sync_service_management_wiki_templates_to_project "${realm}" "${itsm_full_path}"
  fi

  local grafana_schedule_enabled
  local grafana_schedule_cron
  local grafana_schedule_timezone
  local grafana_schedule_desc
  grafana_schedule_enabled="${GRAFANA_SYNC_SCHEDULE_ENABLED:-true}"
  grafana_schedule_cron="${GRAFANA_SYNC_SCHEDULE_CRON:-0 * * * *}"
  grafana_schedule_timezone="${GRAFANA_SYNC_SCHEDULE_TIMEZONE:-Asia/Tokyo}"
  grafana_schedule_desc="${GRAFANA_SYNC_SCHEDULE_DESC:-cmdb-grafana-sync-hourly}"
  if [[ "${grafana_schedule_enabled}" == "true" ]]; then
    gitlab_ensure_pipeline_schedule "${template_project_id}" "${grafana_schedule_desc}" "${template_branch}" "${grafana_schedule_cron}" "${grafana_schedule_timezone}" "true"
    if [[ "${itsm_skip_content}" != "true" ]]; then
      gitlab_ensure_pipeline_schedule "${itsm_project_id}" "${grafana_schedule_desc}" "${branch}" "${grafana_schedule_cron}" "${grafana_schedule_timezone}" "true"
    fi
  fi

  local board_name board_key status_csv tag_label template_content template_path
  local -a status_labels=()
  local template_index
  template_index=10
  while IFS='|' read -r board_name board_key status_csv tag_label; do
    [[ -z "${board_name}" ]] && continue

    gitlab_ensure_label "${template_project_id}" "${tag_label}" "#8C8C8C" "ボード分類タグ" "${board_label_force_update}"

    if [[ "${itsm_skip_content}" != "true" ]]; then
      gitlab_ensure_label "${itsm_project_id}" "${tag_label}" "#8C8C8C" "ボード分類タグ" "${board_label_force_update}"
    fi

    IFS=',' read -r -a status_labels <<<"${status_csv}"
    for name in "${status_labels[@]}"; do
      gitlab_ensure_label "${template_project_id}" "${name}" "#1890FF" "${board_key}の状態" "${board_label_force_update}"
    done
    if [[ "${itsm_skip_content}" != "true" ]]; then
      for name in "${status_labels[@]}"; do
        gitlab_ensure_label "${itsm_project_id}" "${name}" "#1890FF" "${board_key}の状態" "${board_label_force_update}"
      done
    fi

    if ! array_contains "${board_key}" "インシデント管理" "サービス要求管理" "問題管理" "変更管理"; then
      template_content="$(load_and_render_template "service-management/issue_templates/board_generic.md.tpl" "BOARD_KEY" "${board_key}")"
      local board_key_hash
      board_key_hash="$(printf '%s' "${board_key}" | cksum | awk '{print $1}')"
      template_path="$(prefixed_template_path "$(printf "%02d" "${template_index}")" "board_${board_key_hash}")"
      template_index=$((template_index + 1))
      if [[ "${force_update}" == "true" ]]; then
        gitlab_upsert_file "${template_project_id}" "${branch}" "${template_path}" "${template_content}" "Update ${board_key} issue template"
      else
        gitlab_create_file_if_missing "${template_project_id}" "${branch}" "${template_path}" "${template_content}" "Add ${board_key} issue template"
      fi
    fi

    gitlab_ensure_board_with_lists "${template_project_id}" "${board_name}" "${status_labels[@]}"
    if [[ "${itsm_skip_content}" != "true" ]]; then
      gitlab_ensure_board_with_lists "${itsm_project_id}" "${board_name}" "${status_labels[@]}"
    fi
  done <<<"${board_specs}"
}


ensure_technical_management_project() {
  local realm="$1"
  local group_id="$2"
  local group_full_path="$3"
  local project_visibility="$4"
  local force_update="$5"
  local operations_project_path="$6"
  local grafana_base_url="${7:-}"
  local keycloak_admin_console_url="${8:-}"
  local zulip_base_url="${9:-}"
  local n8n_base_url="${10:-}"

  local grafana_url
  grafana_url="${grafana_base_url}"
  if [[ -z "${grafana_base_url}" || "${grafana_base_url}" == "null" ]]; then
    grafana_url="https://grafana.example.com"
    echo "[gitlab] WARN: grafana base_url not found for ${group_full_path}, using placeholder."
  fi
  grafana_url="${grafana_url%/}"

  if [[ -z "${keycloak_admin_console_url}" || "${keycloak_admin_console_url}" == "null" ]]; then
    keycloak_admin_console_url="(Keycloak admin URL not configured)"
  fi
  if [[ -z "${zulip_base_url}" || "${zulip_base_url}" == "null" ]]; then
    zulip_base_url="(Zulip URL not configured)"
  fi
  if [[ -z "${n8n_base_url}" || "${n8n_base_url}" == "null" ]]; then
    n8n_base_url="(n8n URL not configured)"
  fi

  if [[ "${ITSM_TECHNICAL_MANAGEMENT_PROJECT_ENABLED:-true}" == "false" ]]; then
    echo "[gitlab] Technical management project skipped"
    return
  fi

  local tech_name tech_management_path tech_full_path
  local tech_template_name tech_template_path tech_template_full_path
  tech_template_name="${ITSM_TEMPLATE_TECHNICAL_MANAGEMENT_PROJECT_NAME:-template-technical-management}"
  tech_template_path="${ITSM_TEMPLATE_TECHNICAL_MANAGEMENT_PROJECT_PATH:-template-technical-management}"
  tech_template_full_path="${group_full_path}/${tech_template_path}"
  tech_name="${ITSM_TECHNICAL_MANAGEMENT_PROJECT_NAME:-technical-management}"
  tech_management_path="${ITSM_TECHNICAL_MANAGEMENT_PROJECT_PATH:-technical-management}"
  tech_full_path="${group_full_path}/${tech_management_path}"

  local tech_template_project_id
  tech_template_project_id="$(gitlab_find_project_id_by_full_path "${tech_template_full_path}" "${tech_template_path}")"
  if [[ -z "${tech_template_project_id}" ]]; then
    echo "[gitlab] Creating technical management template project: ${tech_template_full_path}"
    gitlab_create_project "${tech_template_name}" "${tech_template_path}" "${group_id}" "${project_visibility}"
    tech_template_project_id="$(gitlab_find_project_id_by_full_path "${tech_template_full_path}" "${tech_template_path}")"
    require_var "technical template project id" "${tech_template_project_id}"
  else
    echo "[gitlab] Technical management template project exists: ${tech_template_full_path}"
  fi

  local tech_project_id
  tech_project_id="$(gitlab_find_project_id_by_full_path "${tech_full_path}" "${tech_management_path}")"
  local tech_forked="false"
  local tech_existed="false"
  local tech_skip_content="false"
  if [[ -z "${tech_project_id}" ]]; then
    echo "[gitlab] Forking technical management project: ${tech_full_path}"
    gitlab_fork_project "${tech_template_project_id}" "${group_id}" "${tech_name}" "${tech_management_path}"
    tech_forked="true"
    local attempt
    for attempt in {1..10}; do
      tech_project_id="$(gitlab_find_project_id_by_full_path "${tech_full_path}" "${tech_management_path}")"
      if [[ -n "${tech_project_id}" ]]; then
        break
      fi
      sleep 1
    done
    require_var "technical project id" "${tech_project_id}"
  else
    tech_existed="true"
    echo "[gitlab] Technical management project exists: ${tech_full_path}"
    if [[ "${ITSM_SKIP_IF_PROJECT_EXISTS:-true}" != "false" && "${force_update}" != "true" ]]; then
      tech_skip_content="true"
      echo "[gitlab] Technical management content bootstrap skipped (project exists): ${tech_full_path}"
    fi
  fi

  local branch
  branch="$(gitlab_project_default_branch "${tech_project_id}")"
  if [[ -z "${branch}" ]]; then
    branch="main"
  fi

  local template_branch
  template_branch="$(gitlab_project_default_branch "${tech_template_project_id}")"
  if [[ -z "${template_branch}" ]]; then
    template_branch="main"
  fi

  if [[ "${tech_skip_content}" != "true" ]] && ! gitlab_branch_exists "${tech_project_id}" "develop"; then
    gitlab_create_branch "${tech_project_id}" "develop" "${branch}"
  fi

  local tech_readme tech_ci
  tech_readme="$(load_and_render_template "technical-management/README.md.tpl" \
    "SERVICE_MANAGEMENT_PROJECT_PATH" "${operations_project_path}" \
    "REALM" "${realm}" \
    "KEYCLOAK_ADMIN_CONSOLE_URL" "${keycloak_admin_console_url}" \
    "N8N_BASE_URL" "${n8n_base_url}" \
    "GRAFANA_BASE_URL" "${grafana_base_url}" \
  )"

  tech_ci="$(
    cat <<'EOF'
stages:
  - validate
  - test

json_validate:
  stage: validate
  image: alpine
  script:
    - apk add --no-cache jq
    - find workflows -name "*.json" -print0 | xargs -0 -I{} jq -e . {} >/dev/null

schema_validate:
  stage: validate
  image: alpine
  script:
    - apk add --no-cache jq
    - find schemas -name "*.json" -print0 | xargs -0 -I{} jq -e . {} >/dev/null

deploy_to_test:
  stage: test
  image: alpine
  script:
    - echo "Deploy to test n8n (placeholder)"
  when: manual
EOF
  )"

  if [[ "${force_update}" == "true" ]]; then
    gitlab_upsert_file "${tech_template_project_id}" "${template_branch}" "README.md" "${tech_readme}" "Update README"
    gitlab_upsert_file "${tech_template_project_id}" "${template_branch}" ".gitlab-ci.yml" "${tech_ci}" "Update CI pipeline"
    gitlab_apply_templates_in_dir "${tech_template_project_id}" "${template_branch}" "technical-management" "docs/usecases" "true" \
      "SERVICE_MANAGEMENT_PROJECT_PATH" "${operations_project_path}" \
      "TECHNICAL_MANAGEMENT_PROJECT_PATH" "${tech_management_path}" \
      "GITLAB_BASE_URL" "${GITLAB_BASE_URL}" \
      "GROUP_FULL_PATH" "${group_full_path}" \
      "GRAFANA_BASE_URL" "${grafana_base_url}"
  else
    gitlab_create_file_if_missing "${tech_template_project_id}" "${template_branch}" "README.md" "${tech_readme}" "Add README"
    gitlab_create_file_if_missing "${tech_template_project_id}" "${template_branch}" ".gitlab-ci.yml" "${tech_ci}" "Add CI pipeline"
    gitlab_apply_templates_in_dir "${tech_template_project_id}" "${template_branch}" "technical-management" "docs/usecases" "false" \
      "SERVICE_MANAGEMENT_PROJECT_PATH" "${operations_project_path}" \
      "TECHNICAL_MANAGEMENT_PROJECT_PATH" "${tech_management_path}" \
      "GITLAB_BASE_URL" "${GITLAB_BASE_URL}" \
      "GROUP_FULL_PATH" "${group_full_path}" \
      "GRAFANA_BASE_URL" "${grafana_base_url}"
  fi

  gitlab_apply_templates_in_dir "${tech_template_project_id}" "${template_branch}" "technical-management" "docs/reports" "${force_update}" \
    "SERVICE_MANAGEMENT_PROJECT_PATH" "${operations_project_path}" \
    "TECHNICAL_MANAGEMENT_PROJECT_PATH" "${tech_management_path}" \
    "GITLAB_BASE_URL" "${GITLAB_BASE_URL}" \
    "GROUP_FULL_PATH" "${group_full_path}" \
    "GRAFANA_BASE_URL" "${grafana_base_url}"

  gitlab_apply_templates_in_dir "${tech_template_project_id}" "${template_branch}" "technical-management" "docs/dashboards" "${force_update}" \
    "SERVICE_MANAGEMENT_PROJECT_PATH" "${operations_project_path}" \
    "TECHNICAL_MANAGEMENT_PROJECT_PATH" "${tech_management_path}" \
    "GITLAB_BASE_URL" "${GITLAB_BASE_URL}" \
    "GROUP_FULL_PATH" "${group_full_path}" \
    "GRAFANA_BASE_URL" "${grafana_base_url}"

  local repo_paths=(
    "workflows/active/.gitkeep"
    "workflows/experimental/.gitkeep"
    "workflows/deprecated/.gitkeep"
    "schemas/.gitkeep"
    "tests/.gitkeep"
    "docs/design/README.md"
    "docs/architecture/README.md"
    "docs/operations/README.md"
  )
  local doc_content
  doc_content="$(load_and_render_template "technical-management/docs/operations/README.md.tpl" "SERVICE_MANAGEMENT_PROJECT_PATH" "${operations_project_path}")"
  local repo_path
  for repo_path in "${repo_paths[@]}"; do
    if [[ "${repo_path}" == "docs/operations/README.md" ]]; then
      if [[ "${force_update}" == "true" ]]; then
        gitlab_upsert_file "${tech_template_project_id}" "${template_branch}" "${repo_path}" "${doc_content}" "Update ${repo_path}"
      else
        gitlab_create_file_if_missing "${tech_template_project_id}" "${template_branch}" "${repo_path}" "${doc_content}" "Add ${repo_path}"
      fi
    else
      if [[ "${force_update}" == "true" ]]; then
        gitlab_upsert_file "${tech_template_project_id}" "${template_branch}" "${repo_path}" "" "Update ${repo_path}"
      else
        gitlab_create_file_if_missing "${tech_template_project_id}" "${template_branch}" "${repo_path}" "" "Add ${repo_path}"
      fi
    fi
  done

  local common_labels
  common_labels="$(
    cat <<'EOF'
ITSM/変更管理|#0050B3|RFC関連
ITSM/リリース管理|#096DD9|リリース判定
ITSM/インシデント|#FF4D4F|障害対応
ITSM/問題管理|#722ED1|根本原因分析
ITSM/ナレッジ|#13C2C2|手順・FAQ
ITSM/継続的改善|#52C41A|改善提案
プラクティス/展開管理|#1890FF|Deployment Management
プラクティス/インフラ基盤管理|#2F54EB|Infrastructure & Platform Management
プラクティス/ソフトウェア開発管理|#722ED1|Software Development & Management
KPI/展開成功率|#52C41A|デプロイ成功率
KPI/展開後インシデント数|#FAAD14|展開後の障害件数
KPI/開発成功率|#52C41A|開発完了率
KPI/デプロイ迅速性|#13C2C2|リードタイム短縮
KPI/リードタイム|#13C2C2|変更のリードタイム
KPI/変更失敗率|#FAAD14|変更による障害・ロールバック率
KPI/MTTR|#722ED1|平均復旧時間
KPI/自動化率|#1890FF|自動化で削減できた手作業割合
スクラム/ユーザーストーリー|#1890FF|プロダクト要求
スクラム/スプリント|#52C41A|スプリント対象
スクラム/レトロ|#FAAD14|振り返り
スクラム/改善アクション|#722ED1|レトロ対応
技術/n8n|#003A8C|n8n固有
技術/API|#096DD9|API連携
技術/データ|#2F54EB|データ変換
技術/CI-CD|#13C2C2|パイプライン
技術/調査|#8C8C8C|Spike
状態/対応中|#1890FF|作業中
状態/レビュー待ち|#FAAD14|MR待ち
状態/承認待ち|#722ED1|承認待ち
状態/完了|#52C41A|完了
スクラム：バックログ|#D9D9D9|バックログ
スクラム：準備完了|#13C2C2|準備完了
スクラム：進行中|#1890FF|進行中
スクラム：レビュー待ち|#FAAD14|レビュー待ち
スクラム：完了|#52C41A|完了
EOF
  )"

  if [[ "${tech_skip_content}" != "true" ]]; then
    local label_name label_color label_desc
    while IFS='|' read -r label_name label_color label_desc; do
      [[ -z "${label_name}" ]] && continue
      gitlab_ensure_label "${tech_project_id}" "${label_name}" "${label_color}" "${label_desc}" "${force_update}"
    done <<<"${common_labels}"
  fi

  local label_name label_color label_desc
  while IFS='|' read -r label_name label_color label_desc; do
    [[ -z "${label_name}" ]] && continue
    gitlab_ensure_label "${tech_template_project_id}" "${label_name}" "${label_color}" "${label_desc}" "${force_update}"
  done <<<"${common_labels}"

  local issue_template_specs
  issue_template_specs="$(
    cat <<'EOF'
01|user_story|ユーザーストーリー
02|technical_task|技術タスク
03|bug_fix|バグ修正
04|spike|技術調査
05|ops_linkage|変更連携
06|deployment_management|展開管理
07|infrastructure_platform_management|インフラ基盤管理
08|software_development_management|ソフトウェア開発管理
EOF
  )"

  local template_prefix template_name template_title template_content template_path
  while IFS='|' read -r template_prefix template_name template_title; do
    [[ -z "${template_name}" ]] && continue
    template_content="$(
      load_and_render_template "technical-management/issue_templates/generic.md.tpl" \
        "TITLE" "${template_title}" \
        "SERVICE_MANAGEMENT_PROJECT_PATH" "${operations_project_path}"
    )"
    template_path="$(prefixed_template_path "${template_prefix}" "${template_name}")"
    if [[ "${force_update}" == "true" ]]; then
      gitlab_upsert_file "${tech_template_project_id}" "${template_branch}" "${template_path}" "${template_content}" "Update ${template_name} issue template"
    else
      gitlab_create_file_if_missing "${tech_template_project_id}" "${template_branch}" "${template_path}" "${template_content}" "Add ${template_name} issue template"
    fi
  done <<<"${issue_template_specs}"

  if [[ "${tech_skip_content}" != "true" ]]; then
    local scrum_board_name
    scrum_board_name="${ITSM_TECH_SCRUM_BOARD_NAME:-スクラム開発}"
    gitlab_ensure_board_with_lists "${tech_project_id}" "${scrum_board_name}" \
      "スクラム：バックログ" \
      "スクラム：準備完了" \
      "スクラム：進行中" \
      "スクラム：レビュー待ち" \
      "スクラム：完了"

    gitlab_ensure_board_with_lists "${tech_project_id}" "展開管理" \
      "展開：計画" \
      "展開：準備" \
      "展開：実施" \
      "展開：検証" \
      "展開：完了"

    gitlab_ensure_board_with_lists "${tech_project_id}" "インフラ基盤管理" \
      "基盤：計画" \
      "基盤：構築" \
      "基盤：検証" \
      "基盤：運用" \
      "基盤：改善"

    gitlab_ensure_board_with_lists "${tech_project_id}" "ソフトウェア開発管理" \
      "開発：バックログ" \
      "開発：設計" \
      "開発：実装" \
      "開発：レビュー" \
      "開発：完了"
  fi

  local scrum_board_name
  scrum_board_name="${ITSM_TECH_SCRUM_BOARD_NAME:-スクラム開発}"
  gitlab_ensure_board_with_lists "${tech_template_project_id}" "${scrum_board_name}" \
    "スクラム：バックログ" \
    "スクラム：準備完了" \
    "スクラム：進行中" \
    "スクラム：レビュー待ち" \
    "スクラム：完了"

  gitlab_ensure_board_with_lists "${tech_template_project_id}" "展開管理" \
    "展開：計画" \
    "展開：準備" \
    "展開：実施" \
    "展開：検証" \
    "展開：完了"

  gitlab_ensure_board_with_lists "${tech_template_project_id}" "インフラ基盤管理" \
    "基盤：計画" \
    "基盤：構築" \
    "基盤：検証" \
    "基盤：運用" \
    "基盤：改善"

  gitlab_ensure_board_with_lists "${tech_template_project_id}" "ソフトウェア開発管理" \
    "開発：バックログ" \
    "開発：設計" \
    "開発：実装" \
    "開発：レビュー" \
    "開発：完了"

  local svc_examples
  svc_examples="$(
    cat <<'EOF'
01|deployment_standard_release|展開管理：標準リリース|展開管理|展開成功率
02|deployment_emergency_patch|展開管理：緊急パッチ|展開管理|展開後インシデント数
03|infra_capacity_plan|インフラ基盤：増強計画|インフラ基盤管理|安定稼働
04|infra_vulnerability_response|インフラ基盤：脆弱性対応|インフラ基盤管理|変更影響最小化
05|software_new_workflow|ソフト開発：新規ワークフロー|ソフトウェア開発管理|開発成功率
06|software_refactor_improvement|ソフト開発：改善リファクタ|ソフトウェア開発管理|デプロイ迅速性
07|monitoring_threshold_tuning|監視連携：閾値調整|インフラ基盤管理|展開後インシデント数
08|testing_regression_automation|テスト強化：回帰自動化|ソフトウェア開発管理|開発成功率
09|cicd_optimization|CI/CD最適化|展開管理|デプロイ迅速性
10|operations_change_linkage|運用連携：変更連携|展開管理|展開成功率
EOF
  )"

  local svc_id svc_slug svc_title svc_practice svc_kpi svc_path svc_content
  while IFS='|' read -r svc_id svc_slug svc_title svc_practice svc_kpi; do
    [[ -z "${svc_id}" ]] && continue
    svc_content="$(
      load_and_render_template "technical-management/docs/svc_examples/example.md.tpl" \
        "TITLE" "${svc_title}" \
        "PRACTICE" "${svc_practice}" \
        "KPI" "${svc_kpi}" \
        "SERVICE_MANAGEMENT_PROJECT_PATH" "${operations_project_path}"
    )"
    svc_path="docs/svc_examples/${svc_id}_${svc_slug}.md"
    if [[ "${force_update}" == "true" ]]; then
      gitlab_upsert_file "${tech_template_project_id}" "${template_branch}" "${svc_path}" "${svc_content}" "Update ${svc_title} サービスバリューチェーン事例"
    else
      gitlab_create_file_if_missing "${tech_template_project_id}" "${template_branch}" "${svc_path}" "${svc_content}" "Add ${svc_title} サービスバリューチェーン事例"
    fi
  done <<<"${svc_examples}"

  if [[ "${tech_skip_content}" != "true" ]] && [[ "${tech_forked}" == "true" || "${force_update}" == "true" ]]; then
    gitlab_sync_repo_from_template \
      "${tech_template_full_path}" "${tech_template_project_id}" "${template_branch}" \
      "${tech_full_path}" "${tech_project_id}" "${branch}"
  fi
  if [[ "${tech_skip_content}" != "true" ]]; then
    sync_technical_management_wiki_templates_to_project "${realm}" "${tech_full_path}"
  fi

  if ! gitlab_branch_exists "${tech_template_project_id}" "develop"; then
    gitlab_create_branch "${tech_template_project_id}" "develop" "${template_branch}"
  fi
}

ensure_general_management_project() {
  local realm="$1"
  local group_id="$2"
  local group_full_path="$3"
  local project_visibility="$4"
  local force_update="$5"
  local operations_project_path="$6"
  local grafana_base_url="${7:-}"
  local keycloak_admin_console_url="${8:-}"
  local zulip_base_url="${9:-}"
  local n8n_base_url="${10:-}"

  if [[ "${ITSM_GENERAL_MANAGEMENT_PROJECT_ENABLED:-true}" == "false" ]]; then
    echo "[gitlab] General management project skipped"
    return
  fi

  local general_name general_management_path general_full_path
  local general_template_name general_template_path general_template_full_path
  general_template_name="${ITSM_TEMPLATE_GENERAL_MANAGEMENT_PROJECT_NAME:-template-general-management}"
  general_template_path="${ITSM_TEMPLATE_GENERAL_MANAGEMENT_PROJECT_PATH:-template-general-management}"
  general_template_full_path="${group_full_path}/${general_template_path}"
  general_name="${ITSM_GENERAL_MANAGEMENT_PROJECT_NAME:-general-management}"
  general_management_path="${ITSM_GENERAL_MANAGEMENT_PROJECT_PATH:-general-management}"
  general_full_path="${group_full_path}/${general_management_path}"

  local general_template_project_id
  general_template_project_id="$(gitlab_find_project_id_by_full_path "${general_template_full_path}" "${general_template_path}")"
  if [[ -z "${general_template_project_id}" ]]; then
    echo "[gitlab] Creating general management template project: ${general_template_full_path}"
    gitlab_create_project "${general_template_name}" "${general_template_path}" "${group_id}" "${project_visibility}"
    general_template_project_id="$(gitlab_find_project_id_by_full_path "${general_template_full_path}" "${general_template_path}")"
    require_var "general template project id" "${general_template_project_id}"
  else
    echo "[gitlab] General management template project exists: ${general_template_full_path}"
  fi

  local general_project_id
  general_project_id="$(gitlab_find_project_id_by_full_path "${general_full_path}" "${general_management_path}")"
  local general_forked="false"
  local general_existed="false"
  local general_skip_content="false"
  if [[ -z "${general_project_id}" ]]; then
    echo "[gitlab] Forking general management project: ${general_full_path}"
    gitlab_fork_project "${general_template_project_id}" "${group_id}" "${general_name}" "${general_management_path}"
    general_forked="true"
    local attempt
    for attempt in {1..10}; do
      general_project_id="$(gitlab_find_project_id_by_full_path "${general_full_path}" "${general_management_path}")"
      if [[ -n "${general_project_id}" ]]; then
        break
      fi
      sleep 1
    done
    require_var "general project id" "${general_project_id}"
  else
    general_existed="true"
    echo "[gitlab] General management project exists: ${general_full_path}"
    if [[ "${ITSM_SKIP_IF_PROJECT_EXISTS:-true}" != "false" && "${force_update}" != "true" ]]; then
      general_skip_content="true"
      echo "[gitlab] General management content bootstrap skipped (project exists): ${general_full_path}"
    fi
  fi

  local branch
  branch="$(gitlab_project_default_branch "${general_project_id}")"
  if [[ -z "${branch}" ]]; then
    branch="main"
  fi

  local template_branch
  template_branch="$(gitlab_project_default_branch "${general_template_project_id}")"
  if [[ -z "${template_branch}" ]]; then
    template_branch="main"
  fi

  local grafana_url
  grafana_url="${grafana_base_url%/}"
  if [[ -z "${grafana_base_url}" || "${grafana_base_url}" == "null" ]]; then
    grafana_url="(Grafana URL not configured)"
  fi

  if [[ -z "${keycloak_admin_console_url}" || "${keycloak_admin_console_url}" == "null" ]]; then
    keycloak_admin_console_url="(Keycloak admin URL not configured)"
  fi
  if [[ -z "${zulip_base_url}" || "${zulip_base_url}" == "null" ]]; then
    zulip_base_url="(Zulip URL not configured)"
  fi
  if [[ -z "${n8n_base_url}" || "${n8n_base_url}" == "null" ]]; then
    n8n_base_url="(n8n URL not configured)"
  fi

  local tech_management_path tech_full_path
  tech_management_path="${ITSM_TECHNICAL_MANAGEMENT_PROJECT_PATH:-technical-management}"
  tech_full_path="${group_full_path}/${tech_management_path}"

  local general_readme
  general_readme="$(load_and_render_template "general-management/README.md.tpl" \
    "SERVICE_MANAGEMENT_PROJECT_PATH" "${operations_project_path}" \
    "TECHNICAL_MANAGEMENT_PROJECT_PATH" "${tech_full_path}" \
    "GITLAB_BASE_URL" "${GITLAB_BASE_URL}" \
    "REALM" "${realm}" \
    "KEYCLOAK_ADMIN_CONSOLE_URL" "${keycloak_admin_console_url}" \
    "N8N_BASE_URL" "${n8n_base_url}" \
    "GRAFANA_BASE_URL" "${grafana_base_url}" \
  )"

  if [[ "${force_update}" == "true" ]]; then
    gitlab_upsert_file "${general_template_project_id}" "${template_branch}" "README.md" "${general_readme}" "Update README"
    gitlab_apply_templates_in_dir "${general_template_project_id}" "${template_branch}" "general-management" "docs/usecases" "true" \
      "GITLAB_BASE_URL" "${GITLAB_BASE_URL}" \
      "GROUP_FULL_PATH" "${group_full_path}" \
      "SERVICE_MANAGEMENT_PROJECT_PATH" "${operations_project_path}" \
      "GENERAL_MANAGEMENT_PROJECT_PATH" "${general_management_path}" \
      "GRAFANA_BASE_URL" "${grafana_base_url}"
  else
    gitlab_create_file_if_missing "${general_template_project_id}" "${template_branch}" "README.md" "${general_readme}" "Add README"
    gitlab_apply_templates_in_dir "${general_template_project_id}" "${template_branch}" "general-management" "docs/usecases" "false" \
      "GITLAB_BASE_URL" "${GITLAB_BASE_URL}" \
      "GROUP_FULL_PATH" "${group_full_path}" \
      "SERVICE_MANAGEMENT_PROJECT_PATH" "${operations_project_path}" \
      "GENERAL_MANAGEMENT_PROJECT_PATH" "${general_management_path}" \
      "GRAFANA_BASE_URL" "${grafana_base_url}"
  fi

  local general_labels
  general_labels="$(
    cat <<'EOF'
ITSM/リスク|#A8071A|リスク管理
ITSM/コンプライアンス|#722ED1|監査・法令対応
ITSM/情報セキュリティ|#531DAB|情報セキュリティ管理
ITSM/ポリシー|#1890FF|方針・規程
ITSM/ポートフォリオ|#096DD9|ポートフォリオ管理
ITSM/財務|#13C2C2|財務管理
ITSM/ベンダー|#2F54EB|サプライヤ管理
状態/受付|#D9D9D9|受付
状態/分析|#FAAD14|分析中
状態/承認|#52C41A|承認済み
状態/完了|#389E0D|完了
EOF
  )"

  if [[ "${general_skip_content}" != "true" ]]; then
    local label_name label_color label_desc
    while IFS='|' read -r label_name label_color label_desc; do
      [[ -z "${label_name}" ]] && continue
      gitlab_ensure_label "${general_project_id}" "${label_name}" "${label_color}" "${label_desc}" "${force_update}"
    done <<<"${general_labels}"
  fi

  local label_name label_color label_desc
  while IFS='|' read -r label_name label_color label_desc; do
    [[ -z "${label_name}" ]] && continue
    gitlab_ensure_label "${general_template_project_id}" "${label_name}" "${label_color}" "${label_desc}" "${force_update}"
  done <<<"${general_labels}"

  local general_templates
  general_templates="$(
    cat <<'EOF'
risk_management|リスク管理
compliance|コンプライアンス
information_security|情報セキュリティ
policy_governance|ポリシー
portfolio|ポートフォリオ
EOF
  )"

  local template_name template_title template_content template_path
  while IFS='|' read -r template_name template_title; do
    [[ -z "${template_name}" ]] && continue
    template_content="$(
      load_and_render_template "general-management/issue_templates/generic.md.tpl" \
        "TITLE" "${template_title}" \
        "SERVICE_MANAGEMENT_PROJECT_PATH" "${operations_project_path}"
    )"
    template_path="$(prefixed_template_path "01" "${template_name}")"
    if [[ "${force_update}" == "true" ]]; then
      gitlab_upsert_file "${general_template_project_id}" "${template_branch}" "${template_path}" "${template_content}" "Update ${template_name} issue template"
    else
      gitlab_create_file_if_missing "${general_template_project_id}" "${template_branch}" "${template_path}" "${template_content}" "Add ${template_name} issue template"
    fi
  done <<<"${general_templates}"

  if [[ "${general_skip_content}" != "true" ]] && [[ "${general_forked}" == "true" || "${force_update}" == "true" ]]; then
    gitlab_sync_repo_from_template \
      "${general_template_full_path}" "${general_template_project_id}" "${template_branch}" \
      "${general_full_path}" "${general_project_id}" "${branch}"
  fi
  if [[ "${general_skip_content}" != "true" ]]; then
    sync_general_management_wiki_templates_to_project "${realm}" "${general_full_path}"
  fi

  if [[ "${general_skip_content}" != "true" ]]; then
    local general_board_name
    general_board_name="${ITSM_GENERAL_BOARD_NAME:-ガバナンス管理}"
    gitlab_ensure_board_with_lists "${general_project_id}" "${general_board_name}" \
      "状態/受付" \
      "状態/分析" \
      "状態/承認" \
      "状態/完了"
  fi

  local general_board_name
  general_board_name="${ITSM_GENERAL_BOARD_NAME:-ガバナンス管理}"
  gitlab_ensure_board_with_lists "${general_template_project_id}" "${general_board_name}" \
    "状態/受付" \
    "状態/分析" \
    "状態/承認" \
    "状態/完了"
}


# Backward-compatible aliases (deprecated)
ensure_itsm_bootstrap() {
  ensure_service_bootstrap "$@"
}

ensure_sevice_bootstrap() {
  ensure_service_bootstrap "$@"
}

ensure_general_bootstrap() {
  local realm="$1"
  local group_id="$2"
  local group_full_path="$3"
  local project_visibility="$4"
  local grafana_base_url="$5"
  local keycloak_admin_console_url="${6:-}"
  local zulip_base_url="${7:-}"
  local n8n_base_url="${8:-}"

  local force_update
  force_update="$(effective_force_update_for_realm "${realm}")"

  local itsm_path itsm_full_path
  itsm_path="${ITSM_SERVICE_MANAGEMENT_PROJECT_PATH:-service-management}"
  itsm_full_path="${group_full_path}/${itsm_path}"

  ensure_general_management_project     "${realm}"     "${group_id}"     "${group_full_path}"     "${project_visibility}"     "${force_update}"     "${itsm_full_path}"     "${grafana_base_url}"     "${keycloak_admin_console_url}"     "${zulip_base_url}"     "${n8n_base_url}"
}

ensure_technical_bootstrap() {
  local realm="$1"
  local group_id="$2"
  local group_full_path="$3"
  local project_visibility="$4"
  local grafana_base_url="$5"
  local keycloak_admin_console_url="${6:-}"
  local zulip_base_url="${7:-}"
  local n8n_base_url="${8:-}"

  local force_update
  force_update="$(effective_force_update_for_realm "${realm}")"

  local itsm_path itsm_full_path
  itsm_path="${ITSM_SERVICE_MANAGEMENT_PROJECT_PATH:-service-management}"
  itsm_full_path="${group_full_path}/${itsm_path}"

  ensure_technical_management_project     "${realm}"     "${group_id}"     "${group_full_path}"     "${project_visibility}"     "${force_update}"     "${itsm_full_path}"     "${grafana_base_url}"     "${keycloak_admin_console_url}"     "${zulip_base_url}"     "${n8n_base_url}"
}

split_csv() {
  local csv="$1"
  local -a out=()
  local item
  IFS=',' read -r -a out <<<"${csv}"
  for item in "${out[@]}"; do
    item="$(echo "${item}" | xargs)"
    [[ -n "${item}" ]] && echo "${item}"
  done
}

bootstrap_main() {
  while [[ "${1:-}" != "" ]]; do
    case "${1}" in
      --purge-existing)
        ITSM_PURGE_EXISTING="true"
        shift
        ;;
      --files-only)
        ITSM_FILES_ONLY="true"
        shift
        ;;
      --dry-run|-n)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      --)
        shift
        break
        ;;
      *)
        echo "ERROR: Unknown option: ${1}" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  require_cmd terraform jq curl python3

  if [[ "${ITSM_BOOTSTRAP:-true}" == "false" ]]; then
    echo "[gitlab] ITSM bootstrap skipped"
    return
  fi

  if [[ "${ITSM_PROVISION_GRAFANA_EVENT_INBOX:-false}" == "true" ]]; then
    local provision_script="${SCRIPT_DIR}/provision_grafana_itsm_event_inbox.sh"
    if [[ ! -f "${provision_script}" ]]; then
      echo "ERROR: provision script not found: ${provision_script}" >&2
      exit 1
    fi
    if [[ -n "${DRY_RUN:-}" ]]; then
      echo "[gitlab] DRY_RUN: provisioning Grafana ITSM Event Inbox (dry-run)"
      DRY_RUN=1 REALMS="${REALMS:-}" bash "${provision_script}"
    else
      echo "[gitlab] Provisioning Grafana ITSM Event Inbox"
      REALMS="${REALMS:-}" bash "${provision_script}"
    fi
  fi

  if [[ -z "${GITLAB_REFRESH_ADMIN_TOKEN:-}" ]]; then
    GITLAB_REFRESH_ADMIN_TOKEN="true"
  fi
  if [[ -z "${GITLAB_TOKEN:-}" ]]; then
    GITLAB_TOKEN="$(tf_output_raw gitlab_admin_token)"
  fi
  if [[ -z "${GITLAB_TOKEN:-}" && "${GITLAB_REFRESH_ADMIN_TOKEN}" != "false" ]]; then
    require_cmd aws
    TFVARS_PATH="$(resolve_tfvars_path)"
    local refresh_script="${SCRIPT_DIR}/refresh_gitlab_admin_token.sh"
    if [[ ! -f "${refresh_script}" ]]; then
      echo "ERROR: refresh script not found: ${refresh_script}" >&2
      exit 1
    fi
    echo "[gitlab] gitlab_admin_token is empty. Running ${refresh_script} to refresh it."
    TFVARS_PATH="${TFVARS_PATH}" bash "${refresh_script}"
    echo "[gitlab] gitlab_admin_token refreshed. Please re-run this script to continue."
    exit 1
  fi
  require_var "GITLAB_TOKEN" "${GITLAB_TOKEN:-}"

  if [[ -z "${ITSM_FORCE_UPDATE:-}" ]]; then
    ITSM_FORCE_UPDATE="$(tf_output_raw itsm_force_update)"
  fi
  if [[ -z "${ITSM_FORCE_UPDATE:-}" || "${ITSM_FORCE_UPDATE}" == "null" ]]; then
    ITSM_FORCE_UPDATE="true"
  fi

  local included_realms_json
  included_realms_json="${ITSM_FORCE_UPDATE_INCLUDED_REALMS_JSON:-}"
  if [[ -z "${included_realms_json}" ]]; then
    included_realms_json="$(tf_output_json itsm_force_update_included_realms)"
  fi
  ITSM_FORCE_UPDATE_INCLUDED_REALMS=()
  if [[ -n "${included_realms_json}" && "${included_realms_json}" != "null" ]]; then
    while IFS= read -r realm; do
      [[ -n "${realm}" ]] && ITSM_FORCE_UPDATE_INCLUDED_REALMS+=("${realm}")
    done < <(echo "${included_realms_json}" | jq -r '.[]?' 2>/dev/null || true)
  fi

  local output_name context_json targets_json
  output_name="${TERRAFORM_OUTPUT_NAME:-service_control_web_monitoring_context}"
  context_json="$(tf_output_json "${output_name}")"
  if [[ -z "${context_json}" || "${context_json}" == "null" ]]; then
    echo "ERROR: terraform output -json ${output_name} is empty." >&2
    exit 1
  fi

  targets_json="$(echo "${context_json}" | jq -c '.targets // empty')"
  if [[ -z "${targets_json}" || "${targets_json}" == "null" ]]; then
    echo "ERROR: ${output_name}.targets is empty." >&2
    exit 1
  fi

  local -a realms=()
  if [[ -n "${REALMS:-}" ]]; then
    while IFS= read -r r; do
      realms+=("${r}")
    done < <(split_csv "${REALMS}")
  else
    while IFS= read -r realm; do
      [[ -n "${realm}" ]] && realms+=("${realm}")
    done < <(echo "${targets_json}" | jq -r 'keys[]' 2>/dev/null || true)
  fi

  if [[ "${#realms[@]}" -eq 0 ]]; then
    echo "ERROR: No realms specified/found." >&2
    exit 1
  fi

  if [[ -z "${REALMS:-}" && -z "${DRY_RUN:-}" ]]; then
    if ! is_truthy "${ITSM_ALLOW_ALL_REALMS:-false}"; then
      echo "ERROR: REALMS is not specified; refusing to apply to all realms by default." >&2
      echo "Target realms would be: ${realms[*]}" >&2
      echo "Set REALMS=<comma-separated realms> or ITSM_ALLOW_ALL_REALMS=true to proceed." >&2
      exit 1
    fi
  fi

  if [[ -z "${GITLAB_API_BASE_URL:-}" ]]; then
    if [[ -z "${GITLAB_BASE_URL:-}" ]]; then
      local gitlab_url
      gitlab_url="$(echo "${targets_json}" | jq -r 'to_entries[] | .value.gitlab // empty' | awk 'NF{print; exit}')"
      require_var "gitlab url in monitoring targets" "${gitlab_url}"
      GITLAB_BASE_URL="${gitlab_url%/}"
    else
      GITLAB_BASE_URL="${GITLAB_BASE_URL%/}"
    fi
    GITLAB_API_BASE_URL="${GITLAB_BASE_URL}/api/v4"
  else
    GITLAB_API_BASE_URL="${GITLAB_API_BASE_URL%/}"
    GITLAB_BASE_URL="${GITLAB_API_BASE_URL%/api/v4}"
  fi

  local parent_group_path="" parent_id_json="null"
  if [[ -n "${GITLAB_PARENT_GROUP_ID:-}" ]]; then
    if ! [[ "${GITLAB_PARENT_GROUP_ID}" =~ ^[0-9]+$ ]]; then
      echo "ERROR: GITLAB_PARENT_GROUP_ID must be numeric; got: ${GITLAB_PARENT_GROUP_ID}" >&2
      exit 1
    fi
    parent_id_json="${GITLAB_PARENT_GROUP_ID}"
    gitlab_request GET "/groups/${GITLAB_PARENT_GROUP_ID}"
    if [[ "${GITLAB_LAST_STATUS}" != "200" ]]; then
      echo "ERROR: Failed to resolve parent group ID ${GITLAB_PARENT_GROUP_ID} (HTTP ${GITLAB_LAST_STATUS})." >&2
      echo "${GITLAB_LAST_BODY}" >&2
      exit 1
    fi
    parent_group_path="$(echo "${GITLAB_LAST_BODY}" | jq -r '.full_path // empty')"
    require_var "parent group full_path" "${parent_group_path}"
  fi

  local grafana_realm_urls_json
  grafana_realm_urls_json="$(tf_output_json grafana_realm_urls)"
  if [[ -z "${grafana_realm_urls_json}" || "${grafana_realm_urls_json}" == "null" ]]; then
    grafana_realm_urls_json="{}"
  fi

  ITSM_MONITORING_CONTEXT_JSON="$(tf_output_json itsm_monitoring_context)"
  if [[ -z "${ITSM_MONITORING_CONTEXT_JSON}" || "${ITSM_MONITORING_CONTEXT_JSON}" == "null" ]]; then
    ITSM_MONITORING_CONTEXT_JSON="{}"
  fi

  local visibility
  visibility="${GITLAB_GROUP_VISIBILITY:-private}"

  local realm group_path full_path encoded_path status group_id
  for realm in "${realms[@]}"; do
    local realm_gitlab_url
    realm_gitlab_url="$(echo "${targets_json}" | jq -r --arg realm "${realm}" '.[$realm].gitlab // empty')"
    if [[ -z "${realm_gitlab_url}" || "${realm_gitlab_url}" == "null" ]]; then
      echo "[gitlab] Skip realm ${realm}: gitlab url not set in monitoring targets."
      continue
    fi

    group_path="${realm}"
    full_path="${group_path}"
    if [[ -n "${parent_group_path}" ]]; then
      full_path="${parent_group_path}/${group_path}"
    fi

    encoded_path="$(urlencode "${full_path}")"
    gitlab_request GET "/groups/${encoded_path}"
    status="${GITLAB_LAST_STATUS}"
    if [[ "${status}" == "200" ]]; then
      group_id="$(echo "${GITLAB_LAST_BODY}" | jq -r '.id // empty')"
    else
      group_id="$(gitlab_search_group_id_by_full_path "${full_path}" "${group_path}")"
    fi
    if [[ -z "${group_id}" ]]; then
      echo "ERROR: GitLab group not found for realm ${realm}: ${full_path}" >&2
      exit 1
    fi

    if [[ -n "${DRY_RUN:-}" ]]; then
      dry_run_plan_realm "${realm}" "${group_id}" "${full_path}" "${visibility}"
      continue
    fi

    itsm_purge_existing_projects_for_realm "${realm}" "${full_path}"

    if [[ "${ITSM_FILES_ONLY:-false}" != "true" ]]; then
      ensure_service_template_project_exists "${group_id}" "${full_path}" "${visibility}"
      ensure_general_template_project_exists "${group_id}" "${full_path}" "${visibility}"
      ensure_technical_template_project_exists "${group_id}" "${full_path}" "${visibility}"
      sync_service_management_wiki_templates "${realm}" "${full_path}"
      sync_general_management_wiki_templates "${realm}" "${full_path}"
      sync_technical_management_wiki_templates "${realm}" "${full_path}"
    fi

    local grafana_url
    grafana_url="$(echo "${grafana_realm_urls_json}" | jq -r --arg realm "${realm}" '.[$realm] // empty' 2>/dev/null || true)"
    if [[ -z "${grafana_url}" || "${grafana_url}" == "null" ]]; then
      grafana_url="$(echo "${targets_json}" | jq -r --arg realm "${realm}" '.[$realm].grafana // empty')"
    fi

    local keycloak_url zulip_url n8n_url keycloak_admin_console_url
    keycloak_url="$(echo "${targets_json}" | jq -r --arg realm "${realm}" '.[$realm].keycloak // empty')"
    zulip_url="$(echo "${targets_json}" | jq -r --arg realm "${realm}" '.[$realm].zulip // empty')"
    n8n_url="$(echo "${targets_json}" | jq -r --arg realm "${realm}" '.[$realm].n8n // empty')"
    keycloak_admin_console_url=""
    if [[ -n "${keycloak_url}" && "${keycloak_url}" != "null" ]]; then
      keycloak_admin_console_url="${keycloak_url%/}/admin/${realm}/console/"
    fi

    echo "[gitlab] ITSM bootstrap realm ${realm} -> ${full_path}"
    ensure_service_bootstrap "${realm}" "${group_id}" "${full_path}" "${visibility}" "${grafana_url}" "${keycloak_admin_console_url}" "${zulip_url}" "${n8n_url}"
    if [[ "${ITSM_FILES_ONLY:-false}" != "true" ]]; then
      ensure_general_bootstrap "${realm}" "${group_id}" "${full_path}" "${visibility}" "${grafana_url}" "${keycloak_admin_console_url}" "${zulip_url}" "${n8n_url}"
      ensure_technical_bootstrap "${realm}" "${group_id}" "${full_path}" "${visibility}" "${grafana_url}" "${keycloak_admin_console_url}" "${zulip_url}" "${n8n_url}"
    fi
  done
}

bootstrap_main "$@"
