# Usage: ITSM Bootstrap

## GitLab ITSM bootstrap（テンプレ投入）

```bash
# （必要なら）GitLab 管理者トークン更新
bash apps/itsm_core/bootstrap/scripts/refresh_gitlab_admin_token.sh

# レルム用のグループ/トークン整備
bash apps/itsm_core/bootstrap/scripts/ensure_realm_groups.sh

# テンプレ/運用資材の投入
bash apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh

# 変更箇所だけ反映（labels/boards/wiki 等は触らない）
bash apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh --files-only
```

## Grafana（ユースケース用ダッシュボード同期）

```bash
bash apps/itsm_core/bootstrap/scripts/sync_usecase_dashboards.sh
```

