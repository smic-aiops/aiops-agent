# AIOps Knowledge Store 要求（Requirements）

本書は `apps/aiops_agent/knowledge_store/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/aiops_agent/README.md`、SQL（`apps/aiops_agent/knowledge_store/sql/`）、ワークフロー（`apps/aiops_agent/knowledge_store/workflows/`）、運用スクリプト（`apps/aiops_agent/knowledge_store/scripts/`）を正とします。

## 1. 対象

AIOps Agent の文脈 DB/重複検知 DB など、運用上参照される補助ストア（Knowledge Store）を提供する。

## 2. 目的

- 外部からの問い合わせ（文脈取得/重複検知）を、n8n Webhook 経由で安全に提供する。
- seed データ投入やスモークテストをスクリプト化し、再現性と証跡を担保する。

## 3. 検証成果物（最小）

- DQ/IQ/OQ/PQ: `apps/aiops_agent/knowledge_store/docs/{dq,iq,oq,pq}/`
- Usage: `apps/aiops_agent/knowledge_store/docs/usage/README.md`
