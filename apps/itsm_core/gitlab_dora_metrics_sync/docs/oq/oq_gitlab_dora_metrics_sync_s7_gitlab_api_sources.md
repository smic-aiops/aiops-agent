# OQ: GitLab DORA Metrics Sync - シナリオ7（GitLab API ソース）

## 目的

本ワークフローが参照する GitLab API の主要エンドポイントを明確にし、運用で必要な権限範囲が過不足ないことを確認します。

## 参照エンドポイント（代表）

- Deployments
  - `GET /projects/:id/deployments`
- Merge Requests
  - `GET /projects/:id/merge_requests`（`state=merged`）
- Commit → Merge Requests（デプロイSHAから紐付け）
  - `GET /projects/:id/repository/commits/:sha/merge_requests`

## 受け入れ基準
- 上記エンドポイントが API token で参照でき、集計が成立する

