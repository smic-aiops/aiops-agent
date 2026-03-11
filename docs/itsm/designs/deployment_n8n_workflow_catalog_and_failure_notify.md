# デプロイメント管理（n8n 関連）設計: Workflow catalog / 失敗時通知

対象:
- `docs/itsm/itsm_oss_features.csv`（デプロイメント管理）のうち、n8n を前提とするもの
  - `UC-2901`（失敗時通知）
  - `UC-3029` `UC-3030` `UC-3031` `UC-3032` `UC-3033`（workflow_catalog / workflow_manager / n8n）

## 目的

- 実行失敗時に、通知とチケット更新を必ず行い、再実行導線を提供する。
- workflow catalog API を「参照/実行導線の正」として提供し、認証・互換性・安全側の失敗を保証する。

## 失敗時通知（UC-2901）

- 起点: Exastro ITA Conductor 実行失敗（API のステータス、または webhook/ポーリング）
- 連携: n8n が失敗イベントを受け取り、以下を実行
  - GitLab Issue を更新（失敗要約・ジョブリンク・再実行手順リンク）
  - Zulip に通知（stream/topic へ集約、必要なら `/decision` 導線）
- 証跡: GitLab Issue コメント + Exastro 実行ログ（参照リンク）を残す

## workflow catalog（UC-3029〜UC-3033）

- 認証:
  - `N8N_WORKFLOWS_TOKEN` を shared secret とし、未認証は拒否（UC-3029）
- API:
  - `list`: 利用可能なワークフロー一覧を返す（UC-3031）
  - `get`: ワークフロー詳細を返す（UC-3030）
- 互換性:
  - list/get の contract を維持し、変更時は OQ で互換性確認（UC-3032）
- サービス制御:
  - 代表例（Sulu 起動/停止）を実行し、入力 validation と安全側の失敗を保証（UC-3033）

## UC 対応（この設計でカバー）

`UC-2901` `UC-3029` `UC-3030` `UC-3031` `UC-3032` `UC-3033`

