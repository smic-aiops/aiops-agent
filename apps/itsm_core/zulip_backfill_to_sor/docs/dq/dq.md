# DQ（設計適格性確認）: Zulip Backfill to SoR

## 目的

- Zulip の過去メッセージを SoR へ投入する設計前提・制約・リスク対策を明文化する。
- 検証（IQ/OQ/PQ）の入口条件・出口条件と証跡を最小限で定義し、変更時の再検証判断を可能にする。

## 対象（SSoT）

- 本 README: `apps/itsm_core/zulip_backfill_to_sor/README.md`
- 実行スクリプト: `apps/itsm_core/zulip_backfill_to_sor/scripts/backfill_zulip_decisions_to_sor.sh`
- 要求: `apps/itsm_core/zulip_backfill_to_sor/docs/app_requirements.md`
- CS（AIS）: `apps/itsm_core/zulip_backfill_to_sor/docs/cs/ai_behavior_spec.md`
- IQ/OQ/PQ: `apps/itsm_core/zulip_backfill_to_sor/docs/iq/`, `apps/itsm_core/zulip_backfill_to_sor/docs/oq/`, `apps/itsm_core/zulip_backfill_to_sor/docs/pq/`

## 設計スコープ

- 対象:
  - Zulip API を走査し、決定マーカーに一致する投稿を SoR（`itsm.audit_event`）へ投入する
  - dry-run / scan / execute を分離し、段階的に運用できる
  - 冪等キー（`zulip:decision:<message_id>`）で重複投入を避ける
- 非対象:
  - Zulip 自体の製品バリデーション
  - SoR のデータモデル変更（必要なら ITSM Core 側で別途変更管理）

## 主要リスクとコントロール（最低限）

- 誤検出（決定ではない投稿の誤投入）
  - コントロール: 既定はマーカー先頭一致（`/decision` 等）に限定。必要に応じて `--decision-prefixes` で明示
- 取り漏れ（マーカー運用の逸脱）
  - コントロール: scan のみ（SQL 生成）を可能にし、検出ルールの調整を段階的に行う
- 秘匿情報の漏えい（Zulip API key/DB パスワード）
  - コントロール: 既存の解決スクリプト（`scripts/itsm/zulip/resolve_zulip_env.sh`）を正とし、tfvars 直読みを禁止
- 冪等性の破綻（重複投入）
  - コントロール: event_key を `zulip:decision:<message_id>` に固定

## 出口条件（Exit）

- IQ 合格: `apps/itsm_core/zulip_backfill_to_sor/docs/iq/iq.md` の最低限条件を満たす
- OQ 合格: `apps/itsm_core/zulip_backfill_to_sor/docs/oq/oq.md` の必須ケースが合格する

## 証跡（最小）

- dry-run 出力（対象 realm/検出ルール）
- scan/execute のログ（日時、対象、結果）

