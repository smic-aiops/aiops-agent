# DQ（設計適格性確認）: Adapter（AIOps Agent）

## 目的

- Adapter の入出力契約（schema）と、外部チャネル連携における前提/制約を明文化する。
- ワークフロー変更時の再検証観点（IQ/OQ）を明確にする。

## 対象（SSoT）

- 全体: `apps/aiops_agent/README.md`
- 契約（正）: `apps/aiops_agent/adapter/schema/`
- ワークフロー（正）: `apps/aiops_agent/adapter/workflows/`
- 同期: `apps/aiops_agent/adapter/scripts/deploy_workflows.sh`
- OQ 実行（委譲）: `apps/aiops_agent/adapter/scripts/run_oq.sh`

## 設計スコープ（要約）

- 外部入力の受領 → 正規化 → downstream へ引き渡し（契約準拠）
- 外部への返信（初期応答/結果/追記）の導線
- 認証情報/トークン等の秘匿情報は平文で docs に書かない（SSM/環境変数を前提）

## 出口条件（Exit）

- IQ 合格: `apps/aiops_agent/adapter/docs/iq/iq.md`
- OQ 合格: `apps/aiops_agent/adapter/docs/oq/oq.md`

