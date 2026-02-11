# PQ（性能適格性確認）: CloudWatch Event Notify

## 目的

- 監視イベントのバースト（アラーム集中）時に、通知が滞留せず運用上許容できる形で処理されることを確認する。
- 外部 API（Zulip/GitLab/Grafana）制約に対して、失敗の可視化・リトライ方針・フォールバック（dry-run/部分失敗）が成立することを確認する。

## 対象

- ワークフロー: `apps/itsm_core/integrations/cloudwatch_event_notify/workflows/cloudwatch_event_notify.json`
- OQ: `apps/itsm_core/integrations/cloudwatch_event_notify/docs/oq/oq_cloudwatch_event_notify.md`

## 想定負荷（例）

- 監視アラームの集中（同一時間帯に複数件）
- 同一通知の再送（SNS 再試行等）による重複入力

## 測定/確認ポイント（最低限）

- n8n 実行時間・失敗率（外部 API 失敗が `results[]` に可視化されること）
- 外部 API の 429/5xx 発生時に、運用上必要な再実行・復旧が可能であること
- 部分失敗時に `status_code=207` となり、失敗チャネルが特定できること

## 実施手順（最小）

1. OQ の `OQ-CWN-002`（notify）を複数回投入し、n8n 側の実行履歴で滞留や失敗傾向を確認する。
2. 外部 API を有効化している場合は、Zulip/GitLab/Grafana の成功/失敗が `results[]` に残ることを確認する。
3. 一部チャネルを意図的に失敗させ（例: 一時的に無効な token で実行）、`207` と失敗チャネルの可視化を確認する。

## 合否判定（最低限）

- バースト投入後も n8n の実行が収束し、未処理が継続的に増えないこと
- 失敗が発生した場合でも、原因（外部 API 制約/認証/ネットワーク）が特定でき、再実行で復旧できること

## 証跡（evidence）

- n8n 実行履歴（件数、実行時間、失敗）
- `/webhook/cloudwatch/notify` の応答（`results` と `status_code`）
- 外部連携先のログ（投稿/Issue/Annotation の確認結果）

