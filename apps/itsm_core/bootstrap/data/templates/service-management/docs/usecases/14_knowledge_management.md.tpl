# 14. ナレッジ管理

**人物**：渡辺（新人）／木村（ベテラン）

## 物語（Before）
渡辺「木村さん、これどうやるんでしたっけ…」  
木村「また同じ質問だな。手順を残そう」

## ゴール（価値）
- “人待ち”を減らし、対応品質と速度を上げる
- 例: FAQ/手順書/事例が運用資産として蓄積される

## 事前に揃っているもの（このプロジェクト）
- ナレッジラベル群（例: `ナレッジ：FAQ` / `ナレッジ：手順書`）: [ラベル]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/labels)
- ドキュメント置き場: [ドキュメント置き場]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/tree/main/docs)

## 関連テンプレート
- [ナレッジ管理]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}}/-/wikis/practice/06_knowledge_management)

## 実施手順（GitLab）
1. 解決した Issue にナレッジラベルを付与  
2. 再利用可能な形に整形（前提/手順/注意/復旧）  
3. 必要なら [docs/](../) に手順書として残し、Issue からリンク  


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `14_knowledge_management`（ナレッジ管理）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 14_knowledge_management
      usecase_name: ナレッジ管理
      dashboard_uid: knowledge-management
      dashboard_title: Knowledge Management Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 新規ナレッジ作成数
          metric: kb_created
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 再利用率
          metric: kb_reuse_rate
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 公開までの時間
          metric: time_to_publish
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 未解決記事
          metric: kb_open
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: ナレッジ未公開滞留 / 再利用率低下 / FAQ更新期限超過
- Zulip チャンネル: #itsm-knowledge
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 次の担当者が “同じIssueを読んで” 解決できる
- 手順書が [docs/](../) に蓄積され、検索・参照できる

## 検索性向上（ベクトル基盤 + API）

検索は「ナレッジの保持（GitLab）」「索引（Qdrant）」「検索API（n8n/Agent）」を分離して実装する。

- ベクトル基盤: Qdrant（`var.enable_n8n_qdrant=true` で ECS に同居）
- 収集/索引: GitLab EFS mirror を indexer で同期し、Qdrant に投入（`modules/stack/gitlab_efs_indexer.tf`）
- 検索API: n8n webhook / AIOps Agent knowledge_store から利用（必要に応じて拡張）

対応ユースケース:
- UC-1404 サービスカタログ管理のナレッジの更新
- UC-1804 サービスレベル管理のナレッジの更新
- UC-3103 バッチ検索
- UC-3104 メタデータ管理
- UC-3105 コレクション管理
- UC-3106 ペイロード更新
- UC-3107 ポイント管理
- UC-3108 検索API
- UC-3109 ベクトル基盤
- UC-3110 レコメンド（検索結果の候補提示として扱う）
- UC-3111 スクロール取得

<!-- BEGIN AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
## 対応ユースケース（トレーサビリティ / 移設: 99_missing_usecases）

- 元は `99_missing_usecases.md.tpl` に集約していた未設計ユースケースを、既存の詳細テンプレ（章）へ移設した一覧です。
- 「プラクティス」は `docs/itsm/itsm_oss_features.csv` をソースとし、コンポーネント/操作はそれに基づく設計上の割当です（未実装は命名規約で明示）。

### ナレッジ管理（検索性向上）（8）
#### プラクティス: gitlab_issue_rag; n8n; GitLab; Qdrant / アプリ: Issue ingest; Embedding; Upsert; Similarity search（6）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - n8n workflow: `apps/itsm_core/gitlab_issue_rag/workflows/gitlab_issue_rag_sync.json`（Issue→Embedding→Qdrant）
  - indexer: `modules/stack/gitlab_efs_indexer.tf` / `scripts/itsm/gitlab/start_gitlab_efs_indexer.sh`（GitLab→EFS→Qdrant）
  - （新規）n8n workflow 命名規約: `itsm_ナレッジ管理（検索性向上）_uc3112_*`（各UCのCron/Webhookを作成）
  - Qdrant: ベクタDB（`scripts/itsm/qdrant/*` / `modules/stack/ecs_tasks.tf`）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-3112 | UC-RAG-02 | GitLab Issue/notes を取得し、チャンク化して pgvector へ upsert する（通常同期） | ⭕️ |
| UC-3113 | UC-RAG-01 | `/test` で pgvector の疎通を確認する（DB 依存の早期検知） | ⭕️ |
| UC-3114 | UC-RAG-05 | embedding を skip/dry-run して、検証・運用の安全性とコストを制御する | ⭕️ |
| UC-3115 | UC-RAG-06 | 取り込み対象プロジェクト/領域を変更した場合、誤取り込みを防ぐため OQ 観点で再検証する | ⭕️ |
| UC-3116 | UC-RAG-03 | 差分同期（例: `updated_at`）で更新分のみを取り込み、同期時間と負荷を抑える | ⭕️ |
| UC-3117 | UC-RAG-04 | 強制フル同期へ切り替え、欠落・不整合を回復できる | ⭕️ |

#### プラクティス: GitLab; Qdrant; indexer(ECS/Step Functions) / アプリ: Git mirror; Vector embeddings; Points Upsert（1）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - Qdrant: ベクタDB（`scripts/itsm/qdrant/*` / `modules/stack/ecs_tasks.tf`）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-3101 | UC-GL-881 | Qdrant-インデックス更新 | ⭕️ |

#### プラクティス: GitLab; n8n; Qdrant / アプリ: Similarity search; Query API; References（1）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - （新規）n8n workflow 命名規約: `itsm_ナレッジ管理（検索性向上）_uc3102_*`（各UCのCron/Webhookを作成）
  - Qdrant: ベクタDB（`scripts/itsm/qdrant/*` / `modules/stack/ecs_tasks.tf`）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-3102 | UC-GL-882 | ナレッジ管理（検索性向上）: 類似事例・Runbook提案 | ⭕️ |


<!-- END AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
