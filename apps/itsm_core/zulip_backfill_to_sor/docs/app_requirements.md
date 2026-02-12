# Zulip Backfill to SoR - 要求（Requirements）

本書は `apps/itsm_core/zulip_backfill_to_sor` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `README.md` と `scripts/` を正とします。

## 1. 対象

Zulip の過去メッセージを走査し、決定マーカー（例: `/decision`）に一致する投稿を ITSM SoR（`itsm.audit_event`）へバックフィルします。

## 2. 目的

- GitLab を経由しない「決定」の履歴を SoR に集約し、参照・監査を可能にする。
- 冪等キー（`zulip:decision:<message_id>`）により、再実行しても重複投入されない運用を成立させる。
- 継続運用では、状態（処理済み範囲）を保持し、未処理分のみを小分けに定期実行できる（n8n workflow）。

## 3. 代表ユースケース

ユースケース本文（SSoT）は `scripts/itsm/gitlab/templates/*-management/docs/usecases/` を正とし、本サブアプリは以下のユースケースを主に支援します。

- 07 コンプライアンス（決定の証跡）: `scripts/itsm/gitlab/templates/general-management/docs/usecases/07_compliance.md.tpl`
- 09 変更判断（決定の記録）: `scripts/itsm/gitlab/templates/general-management/docs/usecases/09_change_decision.md.tpl`
- 14 ナレッジ管理（決定の再利用/検索）: `scripts/itsm/gitlab/templates/service-management/docs/usecases/14_knowledge_management.md.tpl`
- 22 自動化（バックフィル運用）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 27 データ基盤（SoR への履歴集約）: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- 31 SoR（System of Record）運用: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/31_system_of_record.md.tpl`

以下の UC-ZHB-* は「本サブアプリ固有の運用シナリオ（実装観点）」であり、ユースケース本文の正は上記テンプレートです。

- UC-ZHB-01: dry-run（計画のみ）で対象範囲と検出ルールを確認できる
- UC-ZHB-02: scan のみ（SQL 生成）と実行（DB 書き込み）を分離できる
- UC-ZHB-03: 再実行しても重複投入されない（冪等）
- UC-ZHB-04: 状態（カーソル）を保持し、未処理分のみを定期実行できる（小分け）

## 4. 定期実行（n8n Cron）

継続運用では、n8n の Cron で差分バックフィルを小分けに実行し、処理済み範囲（カーソル）は SoR 側で保持する。

- ジョブ: `apps/itsm_core/zulip_backfill_to_sor/workflows/itsm_zulip_backfill_decisions_job.json`
  - Cron（既定）: 毎時 25分（n8n のタイムゾーン設定に依存。ECS 既定: `GENERIC_TIMEZONE=Asia/Tokyo`）
  - 状態保持: `itsm.integration_state`（`state_key = zulip_backfill_to_sor.decisions`）
  - 実行ガード: `ITSM_ZULIP_BACKFILL_EXECUTE=true` のときのみ DB へ書き込み + カーソル更新（既定 false）
- スモーク（dry-run）: `apps/itsm_core/zulip_backfill_to_sor/workflows/itsm_zulip_backfill_decisions_test.json`（`POST /webhook/itsm/sor/zulip/backfill/decisions/test`）

注: workflow JSON は `active=false`（既定: 無効）で同梱する（有効化は n8n UI または `apps/itsm_core/zulip_backfill_to_sor/scripts/deploy_workflows.sh --activate`）。

## 5. 参照（SSoT）

- README: `apps/itsm_core/zulip_backfill_to_sor/README.md`
- 実行スクリプト: `apps/itsm_core/zulip_backfill_to_sor/scripts/backfill_zulip_decisions_to_sor.sh`
- n8n workflow: `apps/itsm_core/zulip_backfill_to_sor/workflows/`
- DQ: `apps/itsm_core/zulip_backfill_to_sor/docs/dq/dq.md`
- IQ: `apps/itsm_core/zulip_backfill_to_sor/docs/iq/iq.md`
- OQ: `apps/itsm_core/zulip_backfill_to_sor/docs/oq/oq.md`
- PQ: `apps/itsm_core/zulip_backfill_to_sor/docs/pq/pq.md`
