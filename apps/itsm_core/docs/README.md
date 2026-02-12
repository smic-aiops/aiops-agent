# ITSM Core ドキュメント

ITSM Core（SoR: System of Record）関連のドキュメントはこのディレクトリ（`apps/itsm_core/docs/`）に配置します。

- ITSM 全体の入口: `docs/itsm/README.md`
- SoR スキーマ（正）: `apps/itsm_core/sql/itsm_sor_core.sql`
- 運用スクリプト（正）: `apps/itsm_core/sor_ops/scripts/`
- n8n ワークフロー（SoR core / Webhook）: `apps/itsm_core/sor_webhooks/workflows/`
- n8n ワークフロー（サブアプリ）: `apps/itsm_core/<app>/workflows/`
- OQ（入口）: `apps/itsm_core/docs/oq/oq.md`
- OQ（SoR core / Webhook）: `apps/itsm_core/sor_webhooks/docs/oq/oq.md`
- OQ 実行補助: `apps/itsm_core/sor_webhooks/scripts/run_oq.sh`
