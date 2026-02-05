# 環境構築ガイド

## AIOps エージェント アーキテクチャ（正の情報源）
- 本環境は [AIOps エージェント仕様](../apps/aiops_agent/docs/aiops_agent_design.md) を正として構築します。Adapter/Orchestrator/ジョブ実行エンジン（ワークフロー API + n8n Queue Mode）間の `jobs.Preview`/`jobs.enqueue`、ContextStore (`aiops_*` テーブル) の TTL（7日程度）、承認トークン・RAG ルーター・Callback の流れなどはすべてこの設計に従います。
- n8n 側のワークフロー（`apps/aiops_agent/workflows/aiops_*`）や OpenAI/PLaMo ノードの設定、ContextStore 参照、ApprovalStore への書き込みもこのドキュメントに沿って調整してください。インフラの設定・フラグを変更する際は、必ずこちらの記載と整合性を確認したうえでパラメータを渡してください。

## このガイドの使い分け
infra / itsm の詳細は分離しました。必要な箇所を参照してください。

- インフラ（Terraform）: `infra/README.md`
- ITSM（サービス）: `itsm/README.md`
- アプリ（ワークフロー同期/デプロイ）: `apps/README.md`

## 運用・利用ガイド
利用手順・監視メモ・トラブルシューティングは `usage-guide.md` を参照してください。
