# OQ（運用適格性確認）: CIR Approved Usecase List

## 目的

一般管理プロジェクトの CIR（継続的改善レジスター）＝ GitLab Issue から、`状態/Approved` のレコードを抽出し、ユースケース（`UC-*`）を抽出して返せることを確認する。

## OQ（最小）

1. Webhook（テスト）が疎通すること
   - `POST /webhook/itsm/cir/usecases/approved/list/test` が `HTTP 200` を返す
2. Webhook（一覧）が dry-run で応答できること
   - `POST /webhook/itsm/cir/usecases/approved/list` に `{ \"dry_run\": true }` を送って `HTTP 200` を返す
3. （任意）GitLab API へ接続できる環境では、一覧が取得できること
   - `POST /webhook/itsm/cir/usecases/approved/list` に `{ \"dry_run\": false }` を送って結果 JSON を確認する

