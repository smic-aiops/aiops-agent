# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### SoR Webhooks（n8n） / GAMP® 5 第2版（2022, CSA ベース, IQ/OQ/PQ を含む）

---

## 目的
ITSM SoR（`itsm.*`）へ投入する SoR コアの Webhook ワークフロー定義を管理し、同期・スモークテスト（OQ）を実行できる状態を維持する。

## ワークフロー
`apps/itsm_core/sor_webhooks/workflows/` に SoR コア Webhook を配置する。

### 収録ワークフロー（現行）
- SoR 監査イベント（スモークテスト投入）: `apps/itsm_core/sor_webhooks/workflows/itsm_sor_audit_event_test.json`（`POST /webhook/itsm/sor/audit_event/test`）
- AIOps 互換 Webhook（スモークテスト）: `apps/itsm_core/sor_webhooks/workflows/itsm_sor_aiops_write_test.json`（`POST /webhook/itsm/sor/aiops/write/test`）
- AIOps 自動処理キュー投入: `apps/itsm_core/sor_webhooks/workflows/itsm_sor_aiops_auto_enqueue.json`（`POST /webhook/itsm/sor/aiops/auto_enqueue`）
- 承認結果（decision）を SoR へ記録: `apps/itsm_core/sor_webhooks/workflows/itsm_sor_aiops_approval_decision.json`（`POST /webhook/itsm/sor/aiops/approval/decision`）
- 承認コメント等を SoR へ記録: `apps/itsm_core/sor_webhooks/workflows/itsm_sor_aiops_approval_comment.json`（`POST /webhook/itsm/sor/aiops/approval/comment`）

## 同期（n8n Public API へ upsert）
```bash
apps/itsm_core/sor_webhooks/scripts/deploy_workflows.sh
```

## OQ（スモークテスト）
```bash
# 例: 実行（実 HTTP）
apps/itsm_core/sor_webhooks/scripts/run_oq.sh --realm default

# 例: dry-run（リクエストを表示のみ）
apps/itsm_core/sor_webhooks/scripts/run_oq.sh --realm default --dry-run
```

## 環境変数（任意）
- `ITSM_SOR_WEBHOOK_TOKEN`: OQ/スモークテストの POST に Bearer トークンを付与する（`Authorization: Bearer ...`）

## ディレクトリ構成
- `apps/itsm_core/sor_webhooks/workflows/`: n8n ワークフロー（JSON）
- `apps/itsm_core/sor_webhooks/scripts/`: 同期・OQ 実行
- `apps/itsm_core/sor_webhooks/docs/`: DQ/IQ/OQ/PQ（最小）
- `apps/itsm_core/sor_webhooks/data/default/prompt/system.md`: サブアプリ単位の中心プロンプト（System 相当）

## 参照
- OQ: `apps/itsm_core/sor_webhooks/docs/oq/oq.md`
