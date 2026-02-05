# DQ（設計適格性確認）: Workflow Manager

## 目的

- ワークフローカタログ API（list/get）および代表的サービス制御の設計前提・制約・主要リスク対策を明文化する。
- クライアント（AIOps Agent 等）とのインターフェース変更時に、再検証観点を明確にする。

## 対象（SSoT）

- 本 README: `apps/workflow_manager/README.md`
- ワークフロー:
  - `apps/workflow_manager/workflows/aiops_workflows_list.json`
  - `apps/workflow_manager/workflows/aiops_workflows_get.json`
  - `apps/workflow_manager/workflows/service_request/` 配下
- 同期スクリプト: `apps/workflow_manager/scripts/deploy_workflows.sh`
- OQ: `apps/workflow_manager/docs/oq/oq.md`
- CS: `apps/workflow_manager/docs/cs/ai_behavior_spec.md`

## 設計スコープ

- 対象:
  - カタログ API により、利用可能なワークフローの一覧/取得を提供する
  - サービス制御（例: Sulu 起動/停止）などの運用手順をワークフロー化して提供する
- 非対象:
  - n8n/GitLab/Service Control 自体の製品バリデーション
  - すべてのサービス制御ユースケースの完全網羅（ただし、代表操作は OQ で確認する）

## 主要リスクとコントロール（最低限）

- 不正参照（カタログ API の漏えい）
  - コントロール: `N8N_WORKFLOWS_TOKEN` による認証、トークン管理の徹底（README 設計）
- 誤制御（誤ったサービス停止/起動）
  - コントロール: 入力 validation、認証/認可、OQ で代表操作を確認
- 変更による破壊的影響（クライアント互換崩れ）
  - コントロール: 後方互換を意識し、OQ で API 互換（list/get）を確認

## 入口条件（Entry）

- `apps/workflow_manager/README.md` に Intended Use / Webhook / 認証方式が明記されている
- カタログ API の contract（パラメータ/返却 JSON）が OQ で検証可能である

## 出口条件（Exit）

- IQ 合格: `apps/workflow_manager/docs/iq/iq.md`
- OQ 合格: `apps/workflow_manager/docs/oq/oq.md`（list/get + 代表 service control）

## 変更管理（再検証トリガ）

- カタログ API のパス/クエリ/返却 JSON の変更
- 認証方式（token 形式、ヘッダ）の変更
- サービス制御ワークフローの追加・変更（特に副作用のある操作）

## 証跡（最小）

- カタログ API 応答 JSON（list/get）
- n8n 実行ログ（GitLab/Service Control の成功）
- 代表サービス制御の応答（`status=ok` 等）

