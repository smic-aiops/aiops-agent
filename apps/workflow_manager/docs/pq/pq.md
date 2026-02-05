# PQ（性能適格性確認）: Workflow Manager

## 目的

- カタログ API（list/get）がクライアント利用頻度に耐え、運用上成立することを確認する。
- サービス制御要求の集中時に、失敗の可視化と復旧（再実行/権限制御）が可能であることを確認する。

## 対象

- カタログ API: `GET /webhook/catalog/workflows/list`, `GET /webhook/catalog/workflows/get`
- サービス制御 API: `POST /webhook/sulu/service-control`
- OQ: `apps/workflow_manager/docs/oq/oq.md`

## 想定負荷・制約

- クライアント（AIOps Agent 等）からの list/get の連続呼び出し
- 外部 API（n8n API/GitLab/Service Control）の rate limit / 一時的失敗

## 測定/確認ポイント（最低限）

- list/get のレイテンシ悪化やタイムアウトが発生しないこと
- 429/5xx 発生時に原因特定と復旧（再実行、トークン/権限見直し）が可能であること

## 実施手順（最小）

1. `GET /webhook/catalog/workflows/list` と `.../get` を複数回呼び出し、n8n 実行履歴で滞留が出ないことを確認する。
2. 外部 API 参照を伴うテスト（service-catalog-sync 等）を実行し、失敗時に原因が追跡できることを確認する。

## 合否判定（最低限）

- 連続呼び出しで継続的な滞留が発生しないこと
- 失敗時に原因特定と復旧が可能であること

## 証跡（evidence）

- list/get の応答（成功時 JSON、失敗時の status_code 等）
- n8n 実行履歴（件数、実行時間、成功/失敗）

