# OQ（運用適格性確認）: GitLab Backfill to SoR

## 目的

GitLab バックフィルのテスト投入 Webhook により、SoR への投入経路が成立することを確認する。

## 前提

- n8n にワークフローが同期済みであること（`apps/itsm_core/gitlab_backfill_to_sor/workflows/*.json`）
- SoR の DDL が適用済みであること（`apps/itsm_core/sql/itsm_sor_core.sql`）

## OQ ケース（要約）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-GBF-001 | 決定 backfill のテスト投入 | `HTTP 200`、`ok=true` 等が返る |
| OQ-GBF-002 | Issue backfill のテスト投入 | `HTTP 200`、`ok=true` 等が返る |

## 証跡（evidence）

- テスト投入の応答 JSON（センシティブ情報はマスク）
- n8n 実行ログ（必要に応じて）

<!-- OQ_SCENARIOS_BEGIN -->
## OQ シナリオ（詳細）

このセクションは同一ディレクトリ内の `oq_*.md` から自動生成されます（更新: `scripts/generate_oq_md.sh`）。
個別シナリオを追加/修正した場合は、まず `oq_*.md` を更新し、最後に本スクリプトで `oq.md` を更新してください。

### 一覧
- [oq_gitlab_backfill_integration_smoke_test.md](oq_gitlab_backfill_integration_smoke_test.md)
- [oq_gitlab_backfill_smoke_test.md](oq_gitlab_backfill_smoke_test.md)
- [oq_usecase_coverage.md](oq_usecase_coverage.md)

---

### OQ: GitLab backfill（integration）のスモークテスト（任意）（source: `oq_gitlab_backfill_integration_smoke_test.md`）

> NOTE: 本ファイルは互換のため残しています（統合/移動）。正の OQ は `apps/itsm_core/gitlab_backfill_to_sor/docs/oq/oq_gitlab_backfill_smoke_test.md` を参照してください。

#### 目的

GitLab backfill（integration）が提供するテスト投入 Webhook により、SoR（`itsm.*`）へのバックフィル系投入が成立することを確認する。

#### 受け入れ基準

- `POST /webhook/gitlab/decision/backfill/sor/test` が `HTTP 200` を返す
- `POST /webhook/gitlab/issue/backfill/sor/test` が `HTTP 200` を返す

#### テスト手順（例）

本テストは `apps/itsm_core/gitlab_backfill_to_sor` の OQ 実行補助で実行する（統合後も SoR core とは別に同期/運用するため）。

```bash
apps/itsm_core/gitlab_backfill_to_sor/scripts/run_oq.sh
```

---

### OQ: GitLab Backfill - テスト投入（スモーク）（source: `oq_gitlab_backfill_smoke_test.md`）

#### 対象

- アプリ: `apps/itsm_core/gitlab_backfill_to_sor`
- ワークフロー:
  - `apps/itsm_core/gitlab_backfill_to_sor/workflows/gitlab_decision_backfill_to_sor_test.json`
  - `apps/itsm_core/gitlab_backfill_to_sor/workflows/gitlab_issue_backfill_to_sor_test.json`
- Webhook:
  - `POST /webhook/gitlab/decision/backfill/sor/test`
  - `POST /webhook/gitlab/issue/backfill/sor/test`

#### 受け入れ基準

- いずれのテスト投入でも `HTTP 200` を返す
- 応答 JSON が `ok=true`（または同等の成功シグナル）を含む

#### 証跡（evidence）

- 応答 JSON（センシティブ情報はマスク済み）


---

### OQ: ユースケース別カバレッジ（gitlab_backfill_to_sor）（source: `oq_usecase_coverage.md`）

#### 目的

`apps/itsm_core/gitlab_backfill_to_sor/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

#### 対象

- アプリ: `apps/itsm_core/gitlab_backfill_to_sor`
- OQ 実行補助: `apps/itsm_core/gitlab_backfill_to_sor/scripts/run_oq.sh`
- 主要 OQ:
  - `oq_gitlab_backfill_smoke_test.md`

#### ユースケース別 OQ シナリオ

##### 07_compliance（7. コンプライアンス）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/07_compliance.md.tpl`
- シナリオ（OQ-GBF-UC07-01）:
  - `oq_gitlab_backfill_smoke_test.md` を実施し、決定/監査に関わる記録が SoR に投入できることを確認する
- 受け入れ基準:
  - テスト投入が `HTTP 200` / `ok=true` で完了する
- 証跡:
  - 応答 JSON（秘匿情報はマスク）

##### 09_change_decision（9. 変更判断）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/09_change_decision.md.tpl`
- シナリオ（OQ-GBF-UC09-01）:
  - `POST /webhook/gitlab/decision/backfill/sor/test` の成立を確認する（`oq_gitlab_backfill_smoke_test.md`）
- 受け入れ基準:
  - decision backfill のテスト投入が成功する
- 証跡:
  - 応答 JSON

##### 12_incident_management（12. インシデント管理）

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/12_incident_management.md.tpl`
- シナリオ（OQ-GBF-UC12-01）:
  - `POST /webhook/gitlab/issue/backfill/sor/test` の成立を確認する（`oq_gitlab_backfill_smoke_test.md`）
- 受け入れ基準:
  - issue backfill のテスト投入が成功する
- 証跡:
  - 応答 JSON

##### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- シナリオ（OQ-GBF-UC22-01）:
  - ワークフロー同期（`apps/itsm_core/gitlab_backfill_to_sor/scripts/deploy_workflows.sh`）の dry-run→apply を実施する
  - `apps/itsm_core/gitlab_backfill_to_sor/scripts/run_oq.sh` でスモークテストを投入する
- 受け入れ基準:
  - 同期とテスト投入が再現可能である
- 証跡:
  - 同期ログ、スモークテスト応答

##### 27_data_platform（27. データ基盤）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- シナリオ（OQ-GBF-UC27-01）:
  - SoR（`itsm.*`）へ backfill 結果が投入できることをスモークテストで確認する
- 受け入れ基準:
  - SoR 側に投入が成立する（テスト投入成功）
- 証跡:
  - 応答 JSON、必要なら SoR 側の件数確認ログ

##### 31_system_of_record（31. SoR（System of Record）運用）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/31_system_of_record.md.tpl`
- シナリオ（OQ-GBF-UC31-01）:
  - 前提（SoR DDL 適用）を満たした環境で、テスト投入経路（/test）を維持できることを確認する
- 受け入れ基準:
  - 最小の投入経路が常に動作し、失敗時に原因追跡できる
- 証跡:
  - 応答 JSON、n8n 実行ログ


---
<!-- OQ_SCENARIOS_END -->

