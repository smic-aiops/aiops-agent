# OQ（運用適格性確認）: SoR Webhooks（ITSM Core）

## 目的

ITSM SoR（`itsm.*`）の **コア Webhook ワークフロー**（監査イベント投入、AIOps 互換 Webhook など）と、ワークフロー同期（n8n Public API upsert）が成立することを確認する。

## 対象

- ワークフロー: `apps/itsm_core/sor_webhooks/workflows/`
- 同期スクリプト: `apps/itsm_core/scripts/deploy_workflows.sh`

## 前提

- SoR の DDL が適用済みであること（`apps/itsm_core/sql/itsm_sor_core.sql`）
- n8n が稼働し、n8n Public API が利用可能であること（同期を実施する場合）

## 証跡（evidence）

- スモークテスト/テスト投入の応答 JSON（センシティブ情報はマスク）
- n8n 実行履歴（必要に応じて）
- ワークフロー同期ログ（dry-run の差分、upsert 完了ログ）

<!-- OQ_SCENARIOS_BEGIN -->
## OQ シナリオ（詳細）

このセクションは同一ディレクトリ内の `oq_*.md` から自動生成されます（更新: `scripts/generate_oq_md.sh`）。
個別シナリオを追加/修正した場合は、まず `oq_*.md` を更新し、最後に本スクリプトで `oq.md` を更新してください。

### 一覧
- [oq_sor_aiops_write_test.md](oq_sor_aiops_write_test.md)
- [oq_sor_audit_event_smoke_test.md](oq_sor_audit_event_smoke_test.md)
- [oq_usecase_coverage.md](oq_usecase_coverage.md)
- [oq_workflow_sync_deploy.md](oq_workflow_sync_deploy.md)

---

### OQ: AIOps → SoR 書き込み（互換 Webhook / スモークテスト）（source: `oq_sor_aiops_write_test.md`）

#### 目的

`POST /webhook/itsm/sor/aiops/write/test` により、AIOps 由来ペイロードを受け取る **互換 Webhook 経路**が成立し、`itsm.audit_event` 等へ最小の書き込みが行えることを確認する。

注: AIOpsAgent の実運用は、n8n の Postgres ノードから `itsm.aiops_*` 関数を直接呼び出す（Webhook 非依存）。

#### 受け入れ基準

- `POST /webhook/itsm/sor/aiops/write/test` が `HTTP 200` を返す
- 応答 JSON が `ok=true` を含む（または同等の成功シグナルを返す）

#### テスト手順（例）

```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
curl -sS -H 'Content-Type: application/json' \
  ${ITSM_SOR_WEBHOOK_TOKEN:+-H "Authorization: Bearer ${ITSM_SOR_WEBHOOK_TOKEN}"} \
  -d "{\"realm\":\"$(terraform output -raw default_realm)\",\"message\":\"OQ test: aiops write\"}" \
  "${N8N_BASE_URL%/}/webhook/itsm/sor/aiops/write/test" | jq .
```

---

### OQ: SoR 監査イベント（スモークテスト）（source: `oq_sor_audit_event_smoke_test.md`）

#### 目的

`POST /webhook/itsm/sor/audit_event/test` により、SoR（`itsm.audit_event`）へ最小の書き込みが成立することを確認する。

#### 受け入れ基準

- `POST /webhook/itsm/sor/audit_event/test` が `HTTP 200` を返す
- 応答 JSON が `ok=true` を含む（または同等の成功シグナルを返す）

#### テスト手順（例）

```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
curl -sS -H 'Content-Type: application/json' \
  -d "{\"realm\":\"$(terraform output -raw default_realm)\",\"message\":\"OQ test: audit_event smoke\"}" \
  "${N8N_BASE_URL%/}/webhook/itsm/sor/audit_event/test" | jq .
```


---

### OQ: ユースケース別カバレッジ（sor_webhooks）（source: `oq_usecase_coverage.md`）

#### 目的

`apps/itsm_core/sor_webhooks/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

#### 対象

- アプリ: `apps/itsm_core/sor_webhooks`
- 主要 OQ シナリオ:
  - `oq_sor_audit_event_smoke_test.md`
  - `oq_sor_aiops_write_test.md`
  - `oq_workflow_sync_deploy.md`
- OQ 実行補助: `apps/itsm_core/sor_webhooks/scripts/run_oq.sh`（スモークテスト投入）

#### ユースケース別 OQ シナリオ

##### 07_compliance（7. コンプライアンス）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/07_compliance.md.tpl`
- 実施:
  - `oq_sor_audit_event_smoke_test.md`
- 受け入れ基準:
  - 監査イベントが SoR に最小投入でき、成功が応答として返る
- 証跡:
  - 応答 JSON、n8n 実行ログ

##### 09_change_decision（9. 変更判断）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/09_change_decision.md.tpl`
- 実施:
  - `oq_sor_aiops_write_test.md`（互換 Webhook 経路）
- 受け入れ基準:
  - 承認/決定に関わる記録が最小経路で投入できる（スモーク）
- 証跡:
  - 応答 JSON、n8n 実行ログ

##### 15_change_and_release（15. 変更管理（Change Enablement）とリリース）

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/15_change_and_release.md.tpl`
- 実施:
  - `oq_workflow_sync_deploy.md`
- 受け入れ基準:
  - Webhook ワークフローが同期/有効化でき、最小のスモークテストが通る
- 証跡:
  - 同期ログ、スモークテスト応答

##### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 実施:
  - `oq_workflow_sync_deploy.md`
  - `apps/itsm_core/sor_webhooks/scripts/run_oq.sh`
- 受け入れ基準:
  - 同期→検証（スモーク）を再現可能に実施できる
- 証跡:
  - 同期ログ、OQ 実行ログ

##### 24_security（24. セキュリティ）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/24_security.md.tpl`
- シナリオ（OQ-SORWH-UC24-01）:
  - `oq_sor_audit_event_smoke_test.md` / `oq_sor_aiops_write_test.md` 実施時に、必要に応じて Bearer トークンを付与できること（`ITSM_SOR_WEBHOOK_TOKEN`）を確認する
  - 不正トークン時に拒否されること（経路上の遮断を含む）を確認する（任意）
- 受け入れ基準:
  - 認可付きのスモークテストが成立し、不正送信が抑止される
- 証跡:
  - 成功応答、（任意）拒否応答

##### 27_data_platform（27. データ基盤）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- 実施:
  - `oq_sor_audit_event_smoke_test.md`
- 受け入れ基準:
  - SoR に最小投入でき、後続の参照/バックフィルの前提になる
- 証跡:
  - 応答 JSON

##### 31_system_of_record（31. SoR（System of Record）運用）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/31_system_of_record.md.tpl`
- 実施:
  - `oq_workflow_sync_deploy.md`（同期の維持）
  - `oq_sor_audit_event_smoke_test.md`（最小投入）
- 受け入れ基準:
  - SoR の最小経路（同期 + 投入）が常に成立する
- 証跡:
  - 同期ログ、スモークテスト応答


---

### OQ: ワークフロー同期（n8n Public API upsert）（source: `oq_workflow_sync_deploy.md`）

#### 目的

`apps/itsm_core/scripts/deploy_workflows.sh` により、ITSM Core 配下（`apps/itsm_core/**/workflows/`）のワークフロー群が n8n Public API へ upsert されることを確認する（dry-run の差分確認も含む）。

#### 受け入れ基準

- `DRY_RUN=true` で差分（計画）が表示され、API 書き込みなしで終了できる
- 実行時（dry-run なし）に upsert が完了し、必要なワークフローが active になる

#### テスト手順（例）

```bash
# dry-run
DRY_RUN=true \
WORKFLOW_DIR=apps/itsm_core/sor_webhooks/workflows \
WITH_TESTS=false \
apps/itsm_core/scripts/deploy_workflows.sh

# 実行（必要なら有効化も）
ACTIVATE=true \
WORKFLOW_DIR=apps/itsm_core/sor_webhooks/workflows \
WITH_TESTS=false \
apps/itsm_core/scripts/deploy_workflows.sh
```

補足:
- SoR core / Webhook のみを同期したい場合は `WORKFLOW_DIR=apps/itsm_core/sor_webhooks/workflows` を指定する。
- リポジトリ全体（apps/* を含む）を一括同期する場合は `scripts/apps/deploy_all_workflows.sh` を使用する。

---
<!-- OQ_SCENARIOS_END -->

