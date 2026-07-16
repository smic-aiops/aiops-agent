# Service Request 要求（Requirements）

本書は `apps/workflow_manager/service_request/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/workflow_manager/README.md`、`apps/workflow_manager/service_request/workflows/`、`apps/workflow_manager/service_request/scripts/` を正とします。

## 1. 対象

サービスリクエスト系ワークフロー（例: GitLab サービスカタログ同期、Sulu サービス制御、Suluバージョン指定デプロイ）を提供する。

## 2. 目的

- 運用者/クライアントが実行できるサービスリクエストを、ワークフローとして標準化する。
- 外部 API 連携（GitLab/Service Control）を OQ で検証可能な形で維持する。
- Suluのバージョン指定デプロイは明示タグのみを受け付け、既定をdry-runとし、実変更には明示許可を要求する。
- Sulu PHPとNginxのイメージタグを同一バージョンへ更新し、ECSロールアウトと外形ターゲット正常性を確認する。
- Suluソース比較は比較元・比較先の明示タグを受け取り、`sulu/skeleton`の差分を取得して依存関係、設定、DB、管理画面資産、削除・改名などの修正候補を分類する。
- ソース比較は読み取り専用とし、ソース、ECR、ECS、GitLabを変更しない。
- Sulu RFC分析はGitLab Change Issueまたは入力RFCから修正対象バージョンを抽出し、現行タグとの差分分析を実行する。
- 修正後のECR pushは、RFCの対象バージョンから上流ソースを取得し、リポジトリ管理のSulu overrideをCodeBuildで決定論的に適用してPHP/Nginx双方を自動生成する。`source_ref`未指定時は`main`を使用する。
- 実ECR pushには`push_images=true`と`allow_ecr_push=true`、実ECS変更には`dry_run=false`と`allow_service_change=true`を必須とする。
- 実ECR/ECS変更ではBearer認証に加え、実在するGitLab Change Issueの承認ラベルと承認ノートを取得し、変更ID・Issue URL・承認者・承認日時・対象タグを署名したCAB証跡を必須とする。
- RFC経路では既存のイメージタグを上書きせず、`latest`タグを変更しない。
- Suluメモリ回帰の統合経路は、同一realm・service・image tagかつデプロイ後30分以内のメモリ90%以上の異なる2イベントとOOMを、直近デプロイに相関する。
- 復旧候補は`aiops.recovery_candidates.v1`で順位、根拠、リスク、可逆性、承認要否、実行workflowを返す。
- 統合経路はfix branch、commit、MR、RFC、変更内容に応じたテスト選択、GitLab CI、リスクスコアを同一`trace_id`で追跡する。
- Version DeployとRFC AnalysisはJob EngineからWorkflow Managerへdispatchできること。
- CAB承認、必須テスト合格および明示的な変更ガードが揃った場合だけ、ECR/ECS、CMDB、チケット、KEDBの状態を変更する。
- CMDB、チケット、KEDBの状態変更には、同一実行の修正版デプロイまたは外部正常性確認の`verification_id`を必須とする。
- 既定はdry-runとし、外部書込み、CI、ECR push、サービス変更、状態変更を個別の許可フラグで防護する。
- ECS異常時の旧タスク定義への自動ロールバックは本要求の対象外とし、失敗検知・停止・証跡化までを自動化する。
