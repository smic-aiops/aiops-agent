# OQ（運用適格性確認）: Zulip Backfill to SoR

## 目的

Zulip の過去メッセージ走査（dry-run→scan→execute）が成立することを確認する。

## OQ ケース（要約）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-ZHB-001 | dry-run（計画のみ） | 対象 realm/検出ルールが出力され、秘匿情報が漏れない |
| OQ-ZHB-002（任意） | scan（SQL 生成のみ） | 生成 SQL が作成され、DB 書き込みは行われない |
| OQ-ZHB-003（任意） | execute（小さな範囲） | SoR へ投入され、再実行で重複しない |

## 証跡（evidence）

- dry-run 出力ログ
- scan/execute のログ（任意）

<!-- OQ_SCENARIOS_BEGIN -->
## OQ シナリオ（詳細）

このセクションは同一ディレクトリ内の `oq_*.md` から自動生成されます（更新: `scripts/generate_oq_md.sh`）。
個別シナリオを追加/修正した場合は、まず `oq_*.md` を更新し、最後に本スクリプトで `oq.md` を更新してください。

### 一覧
- [oq_usecase_coverage.md](oq_usecase_coverage.md)
- [oq_zulip_backfill_n8n_smoke.md](oq_zulip_backfill_n8n_smoke.md)
- [oq_zulip_backfill_plan.md](oq_zulip_backfill_plan.md)

---

### OQ: ユースケース別カバレッジ（zulip_backfill_to_sor）（source: `oq_usecase_coverage.md`）

#### 目的

`apps/itsm_core/zulip_backfill_to_sor/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

#### 対象

- アプリ: `apps/itsm_core/zulip_backfill_to_sor`
- スクリプト: `apps/itsm_core/zulip_backfill_to_sor/scripts/backfill_zulip_decisions_to_sor.sh`
- OQ 実行補助: `apps/itsm_core/zulip_backfill_to_sor/scripts/run_oq.sh`
- n8n workflows:
  - `apps/itsm_core/zulip_backfill_to_sor/workflows/itsm_zulip_backfill_decisions_job.json`
  - `apps/itsm_core/zulip_backfill_to_sor/workflows/itsm_zulip_backfill_decisions_test.json`

#### ユースケース別 OQ シナリオ

##### 07_compliance（7. コンプライアンス）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/07_compliance.md.tpl`
- シナリオ（OQ-ZHB-UC07-01）:
  - `oq_zulip_backfill_plan.md`（dry-run）で対象範囲/検出ルールと秘匿非出力を確認する
  - `oq_zulip_backfill_n8n_smoke.md` を実施し、定期実行（差分バックフィル）が n8n で運用可能であることを確認する
  - （任意）scan/execute を小さな範囲で実施し、決定の証跡が SoR へ残ることを確認する
- 受け入れ基準:
  - dry-run で方針が確認でき、execute で証跡が残る（再実行可能）
- 証跡:
  - dry-run 出力、（任意）scan/execute ログ

##### 09_change_decision（9. 変更判断）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/09_change_decision.md.tpl`
- シナリオ（OQ-ZHB-UC09-01）:
  - 決定マーカー（例: `/decision`）の検出→投入が成立することを確認する（dry-run→scan→execute）
  - 冪等キーにより再実行で重複しないことを確認する（任意）
- 受け入れ基準:
  - 同一メッセージが重複投入されない
- 証跡:
  - 実行ログ、（任意）SoR 側のキー確認

##### 14_knowledge_management（14. ナレッジ管理）

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/14_knowledge_management.md.tpl`
- シナリオ（OQ-ZHB-UC14-01）:
  - Zulip の決定ログが SoR に集約され、後続の参照（検索/監査）に使える状態であることを確認する
- 受け入れ基準:
  - 決定ログが追跡可能（message_id/URL 等）である
- 証跡:
  - 投入結果ログ（秘匿マスク）

##### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- シナリオ（OQ-ZHB-UC22-01）:
  - `apps/itsm_core/zulip_backfill_to_sor/scripts/run_oq.sh` を用いて、dry-run の証跡を保存する
  - scan/execute の手順が再現可能であることを確認する
  - `oq_zulip_backfill_n8n_smoke.md` を実施し、状態保持・小分け処理が定期実行できることを確認する
- 受け入れ基準:
  - 証跡が保存され、段階実行できる
- 証跡:
  - evidence ディレクトリ配下のログ

##### 27_data_platform（27. データ基盤）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- シナリオ（OQ-ZHB-UC27-01）:
  - SoR（`itsm.*`）へバックフィル結果が格納されることを確認する
- 受け入れ基準:
  - SoR に投入され、後続の集計/参照に使える
- 証跡:
  - SoR 側の件数/キー確認ログ（秘匿マスク）

##### 31_system_of_record（31. SoR（System of Record）運用）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/31_system_of_record.md.tpl`
- シナリオ（OQ-ZHB-UC31-01）:
  - dry-run→（任意）scan/execute で SoR 集約が成立し、再実行可能であることを確認する
- 受け入れ基準:
  - 失敗時に原因追跡・再実行が可能である
- 証跡:
  - dry-run/scan/execute のログ

---

### OQ: Zulip Backfill to SoR - n8n スモークテスト（差分バックフィル）（source: `oq_zulip_backfill_n8n_smoke.md`）

#### 目的

Zulip backfill を n8n workflow として **定期実行できる前提**（デプロイ可能・Webhook dry-run が成立）を確認する。

#### 受け入れ基準

- `apps/itsm_core/zulip_backfill_to_sor/scripts/deploy_workflows.sh` が dry-run で成立する
- Webhook テストが `HTTP 200` を返し、`ok=true` を返す（資格情報不足時は `skipped=true` として安全に終了する）
- 状態保持（カーソル）は `itsm.integration_state` を使う設計になっている（`state_key = zulip_backfill_to_sor.decisions`）
- Cron の既定スケジュールが把握できる（毎時 25分）

#### 手順（例）

##### 1. ワークフロー同期（dry-run）

```bash
DRY_RUN=true WITH_TESTS=false apps/itsm_core/zulip_backfill_to_sor/scripts/deploy_workflows.sh
```

##### 2. Webhook テスト（dry-run）

```bash
curl -sS -X POST \\
  -H 'Content-Type: application/json' \\
  --data '{\"realm\":\"default\",\"page_size\":50}' \\
  \"${N8N_BASE_URL%/}/webhook/itsm/sor/zulip/backfill/decisions/test\"
```

---

### OQ: Zulip Backfill - dry-run（計画のみ）（source: `oq_zulip_backfill_plan.md`）

#### 対象

- アプリ: `apps/itsm_core/zulip_backfill_to_sor`
- 実行スクリプト: `apps/itsm_core/zulip_backfill_to_sor/scripts/backfill_zulip_decisions_to_sor.sh`

#### 受け入れ基準

- `--dry-run` で以下が出力される:
  - 対象 realm_key / zulip realm
  - 検出マーカー（decision prefixes）
  - 対象スコープ（include_private / stream_prefix / since 等）
- 秘匿情報（API key 等）が出力されない

#### 証跡（evidence）

- dry-run の標準出力ログ


---
<!-- OQ_SCENARIOS_END -->

