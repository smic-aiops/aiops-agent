#!/usr/bin/env bash
set -euo pipefail

cmdb_root="cmdb"
strict_mode=0
skip_aws=0
skip_grafana=0

usage() {
  cat <<'EOF'
Usage: validate_cmdb.sh [--strict] [--no-aws] [--no-grafana] [cmdb_dir]

Options:
  --strict  Require grafana or aws_monitoring and a sla_master link in each CMDB file
  --no-aws  Skip aws_monitoring checks
  --no-grafana  Skip grafana checks
  -h, --help  Show this help message

Examples:
  validate_cmdb.sh cmdb
  validate_cmdb.sh --strict cmdb
  validate_cmdb.sh --no-aws cmdb
  validate_cmdb.sh --no-grafana cmdb

Exit codes:
  0  All checks passed
  1  Validation failed or prerequisites are missing
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --strict)
      strict_mode=1
      shift
      ;;
    --no-aws)
      skip_aws=1
      shift
      ;;
    --no-grafana)
      skip_grafana=1
      shift
      ;;
    *)
      cmdb_root="$1"
      shift
      ;;
  esac
done

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg (ripgrep) is required for CMDB validation" >&2
  echo "hint: install ripgrep or update CI image before running this script" >&2
  exit 1
fi

if [ ! -d "$cmdb_root" ]; then
  echo "error: CMDB directory not found: $cmdb_root" >&2
  exit 1
fi

failed=0
scanned=0

while IFS= read -r -d '' file; do
  scanned=$((scanned + 1))
  missing=()
  has_grafana=0
  has_aws=0

  if [ "$skip_grafana" -eq 0 ] && rg -n "^grafana:" "$file" >/dev/null 2>&1; then
    has_grafana=1
    rg -n "^\s*base_url:\s*" "$file" >/dev/null 2>&1 || missing+=("grafana.base_url")
    rg -n "^\s*dashboard_uid:\s*" "$file" >/dev/null 2>&1 || missing+=("grafana.dashboard_uid")
    rg -n "^\s*dashboard_name:\s*" "$file" >/dev/null 2>&1 || missing+=("grafana.dashboard_name")
    rg -n "^\s*dashboard_url:\s*" "$file" >/dev/null 2>&1 || missing+=("grafana.dashboard_url")
  fi

  if [ "$skip_aws" -eq 0 ] && rg -n "^aws_monitoring:" "$file" >/dev/null 2>&1; then
    has_aws=1
    rg -n "^\s*cloudwatch_dashboard:" "$file" >/dev/null 2>&1 || missing+=("aws_monitoring.cloudwatch_dashboard")
    rg -n "^\s*name:\s*" "$file" >/dev/null 2>&1 || missing+=("aws_monitoring.cloudwatch_dashboard.name")
    rg -n "^\s*url:\s*" "$file" >/dev/null 2>&1 || missing+=("aws_monitoring.cloudwatch_dashboard.url")
    rg -n "^\s*synthetics:" "$file" >/dev/null 2>&1 || missing+=("aws_monitoring.synthetics")
    rg -n "^\s*canary_name:\s*" "$file" >/dev/null 2>&1 || missing+=("aws_monitoring.synthetics.canary_name")
    rg -n "^\s*metrics:" "$file" >/dev/null 2>&1 || missing+=("aws_monitoring.metrics")
    rg -n "^\s*availability:\s*" "$file" >/dev/null 2>&1 || missing+=("aws_monitoring.metrics.availability")
    rg -n "^\s*error_budget_burn:\s*" "$file" >/dev/null 2>&1 || missing+=("aws_monitoring.metrics.error_budget_burn")
    rg -n "^\s*latency_p95:\s*" "$file" >/dev/null 2>&1 || missing+=("aws_monitoring.metrics.latency_p95")
  fi

  if [ "$strict_mode" -eq 1 ]; then
    monitoring_ok=0
    if [ "$skip_grafana" -eq 0 ] && [ "$has_grafana" -eq 1 ]; then
      monitoring_ok=1
    fi
    if [ "$skip_aws" -eq 0 ] && [ "$has_aws" -eq 1 ]; then
      monitoring_ok=1
    fi
    if [ "$monitoring_ok" -eq 0 ]; then
      missing+=("monitoring.grafana_or_aws")
    fi
    if ! rg -n "sla_master\\.md" "$file" >/dev/null 2>&1; then
      missing+=("sla_master.link")
    fi
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    echo "CMDB validation failed: $file" >&2
    printf '  missing: %s\n' "${missing[@]}" >&2
    failed=1
  fi
done < <(find "$cmdb_root" -type f -name "*.md" -print0)

if [ "$scanned" -eq 0 ]; then
  echo "error: no CMDB markdown files found in $cmdb_root" >&2
  exit 1
fi

exit "$failed"
