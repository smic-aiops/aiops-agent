# OQ: ユースケース別カバレッジ（zulip_backfill_to_sor）

## 目的

`apps/itsm_core/zulip_backfill_to_sor/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

## 対象

- アプリ: `apps/itsm_core/zulip_backfill_to_sor`
- スクリプト: `apps/itsm_core/zulip_backfill_to_sor/scripts/backfill_zulip_decisions_to_sor.sh`
- OQ 実行補助: `apps/itsm_core/zulip_backfill_to_sor/scripts/run_oq.sh`
- n8n workflows:
  - `apps/itsm_core/zulip_backfill_to_sor/workflows/itsm_zulip_backfill_decisions_job.json`
  - `apps/itsm_core/zulip_backfill_to_sor/workflows/itsm_zulip_backfill_decisions_test.json`

## ユースケース別 OQ シナリオ

### 07_compliance（7. コンプライアンス）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/07_compliance.md.tpl`
- シナリオ（OQ-ZHB-UC07-01）:
  - `oq_zulip_backfill_plan.md`（dry-run）で対象範囲/検出ルールと秘匿非出力を確認する
  - `oq_zulip_backfill_n8n_smoke.md` を実施し、定期実行（差分バックフィル）が n8n で運用可能であることを確認する
  - （任意）scan/execute を小さな範囲で実施し、決定の証跡が SoR へ残ることを確認する
- 受け入れ基準:
  - dry-run で方針が確認でき、execute で証跡が残る（再実行可能）
- 証跡:
  - dry-run 出力、（任意）scan/execute ログ

### 09_change_decision（9. 変更判断）

- SSoT: `scripts/itsm/gitlab/templates/general-management/docs/usecases/09_change_decision.md.tpl`
- シナリオ（OQ-ZHB-UC09-01）:
  - 決定マーカー（例: `/decision`）の検出→投入が成立することを確認する（dry-run→scan→execute）
  - 冪等キーにより再実行で重複しないことを確認する（任意）
- 受け入れ基準:
  - 同一メッセージが重複投入されない
- 証跡:
  - 実行ログ、（任意）SoR 側のキー確認

### 14_knowledge_management（14. ナレッジ管理）

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/14_knowledge_management.md.tpl`
- シナリオ（OQ-ZHB-UC14-01）:
  - Zulip の決定ログが SoR に集約され、後続の参照（検索/監査）に使える状態であることを確認する
- 受け入れ基準:
  - 決定ログが追跡可能（message_id/URL 等）である
- 証跡:
  - 投入結果ログ（秘匿マスク）

### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- シナリオ（OQ-ZHB-UC22-01）:
  - `apps/itsm_core/zulip_backfill_to_sor/scripts/run_oq.sh` を用いて、dry-run の証跡を保存する
  - scan/execute の手順が再現可能であることを確認する
  - `oq_zulip_backfill_n8n_smoke.md` を実施し、状態保持・小分け処理が定期実行できることを確認する
- 受け入れ基準:
  - 証跡が保存され、段階実行できる
- 証跡:
  - evidence ディレクトリ配下のログ

### 27_data_platform（27. データ基盤）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- シナリオ（OQ-ZHB-UC27-01）:
  - SoR（`itsm.*`）へバックフィル結果が格納されることを確認する
- 受け入れ基準:
  - SoR に投入され、後続の集計/参照に使える
- 証跡:
  - SoR 側の件数/キー確認ログ（秘匿マスク）

### 31_system_of_record（31. SoR（System of Record）運用）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/31_system_of_record.md.tpl`
- シナリオ（OQ-ZHB-UC31-01）:
  - dry-run→（任意）scan/execute で SoR 集約が成立し、再実行可能であることを確認する
- 受け入れ基準:
  - 失敗時に原因追跡・再実行が可能である
- 証跡:
  - dry-run/scan/execute のログ
