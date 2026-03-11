# PQ（性能適格性確認）: Zulip GitLab Issue Sync

## 目的

- 投稿量と定期同期頻度（既定: every minute）に対して、同期処理が滞留せず運用上成立することを確認する。
- 外部 API（Zulip/GitLab）制約に対して、失敗の可視化と復旧（再実行/運用切替）が可能であることを確認する。

## 対象

- ワークフロー: `apps/itsm_core/zulip_gitlab_issue_sync/workflows/zulip_gitlab_issue_sync.json`
- OQ: `apps/itsm_core/zulip_gitlab_issue_sync/docs/oq/oq.md`

## 想定負荷・制約

- 投稿数増加（対象 stream/topic のメッセージ増）
- Zulip/GitLab API の rate limit / 5xx
- 同期処理が 1 分間隔の次回実行と競合するリスク

## 測定/確認ポイント（最低限）

- n8n の実行が継続的に backlog 化しないこと（収束すること）
- 失敗時に原因が追跡でき、再実行や運用上の回避（間隔変更/範囲縮小）が可能であること

## 実施手順（最小）

1. OQ 実行（`apps/itsm_core/zulip_gitlab_issue_sync/docs/oq/oq.md`）で同期成立を確認する。
2. 対象 stream/topic の投稿量を増やした状態で複数回実行し、n8n 実行時間と滞留傾向を確認する。
3. 失敗が出る場合は、原因（API 制約/権限/入力条件）を記録し、再実行で復旧できることを確認する。

## 合否判定（最低限）

- 定期同期が破綻せず、継続的な滞留が発生しないこと
- 失敗時に原因特定と復旧が可能であること

## 証跡（evidence）

- n8n 実行履歴（実行時間、成功/失敗）
- Zulip/GitLab API の失敗ログ（n8n 実行詳細）

