# 26. 標準化

**人物**：伊藤（TL）／岡田（Ops）

## 物語（Before）
伊藤「A環境では動くけど、Bでは動かない…」  
岡田「標準がないと、運用は“祈り”になる」

## ゴール（価値）
- 標準手順・標準構成を整え、誰がやっても同じ結果になる
- 再現性が上がり、事故率が下がる

## 事前に揃っているもの（このプロジェクト）
- [`docs/`](../) に設計情報を置ける: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/tree/main/docs`
- CI の枠: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/pipelines`

## 実施手順（GitLab）
1. 標準（命名/構造/手順）を [`docs/`](../) に明文化  
2. 標準に反する例を Issue として起票し、直す  
3. CI に「標準チェック」を追加（必要なら）  
4. 運用影響がある標準変更は `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` とリンク


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `26_standardization`（標準化）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 26_standardization
      usecase_name: 標準化
      dashboard_uid: tm-standardization
      dashboard_title: Standardization Overview
      folder: ITSM - 技術管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 標準適用率
          metric: standard_adoption
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 逸脱件数
          metric: deviation_count
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: ポリシーカバレッジ
          metric: policy_coverage
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: レビューリードタイム
          metric: review_cycle_time
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 逸脱検知 / 標準適用率低下
- Zulip チャンネル: #tm-standard
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 標準が [`docs/`](../) に残り、変更履歴が GitLab に蓄積される

## 検索基盤/スナップショット（実装の扱い）

- HNSW 索引:
  - Qdrant をベクトル基盤として採用し、内部インデックス（HNSW 相当）を利用する
  - 実体は `modules/stack/` の Qdrant ECS 構成（realm 分離）で提供
- スナップショット:
  - RDS（PostgreSQL）はスナップショット/バックアップで担保
  - EFS ミラー/索引（Qdrant storage）は EFS 上のデータとしてバックアップ運用を前提（必要なら別途手順化）

対応ユースケース:
- UC-0523 HNSW索引
- UC-0524 スナップショット
- UC-1406 サービスカタログ管理のレポートの標準化
- UC-1414 サービスカタログ管理の方針/標準定義
- UC-1415 サービスカタログ管理の標準テンプレートの整備
- UC-1806 サービスレベル管理のレポートの標準化
- UC-1814 サービスレベル管理の方針/標準定義
- UC-1815 サービスレベル管理の標準テンプレートの整備

<!-- BEGIN TRACEABILITY_GENERAL_FAMILY -->
## 対応ユースケース（トレーサビリティ / general）
- UC-0121 アーキテクチャ管理の標準/ガイドライン整備
- UC-0124 アーキテクチャ管理の運用手順と標準の整備
- UC-1321 サプライヤ管理の標準/ガイドライン整備
- UC-1324 サプライヤ管理の運用手順と標準の整備
- UC-2621 サービス財務管理の標準/ガイドライン整備
- UC-2624 サービス財務管理の運用手順と標準の整備
- UC-3321 プロジェクト管理の標準/ガイドライン整備
- UC-3324 プロジェクト管理の運用手順と標準の整備
- UC-3421 ポートフォリオ管理の標準/ガイドライン整備
- UC-3424 ポートフォリオ管理の運用手順と標準の整備
- UC-3521 リスク管理の標準/ガイドライン整備
- UC-3524 リスク管理の運用手順と標準の整備
- UC-3721 人材・タレント管理の標準/ガイドライン整備
- UC-3724 人材・タレント管理の運用手順と標準の整備
- UC-4533 情報セキュリティ管理の標準/ガイドライン整備
- UC-4536 情報セキュリティ管理の運用手順と標準の整備
- UC-4621 戦略管理の標準/ガイドライン整備
- UC-4624 戦略管理の運用手順と標準の整備
- UC-4728 測定および報告の標準/ガイドライン整備
- UC-4731 測定および報告の運用手順と標準の整備
- UC-4921 知識管理の標準/ガイドライン整備
- UC-4924 知識管理の運用手順と標準の整備
- UC-5221 関係管理の標準/ガイドライン整備
- UC-5224 関係管理の運用手順と標準の整備
<!-- END TRACEABILITY_GENERAL_FAMILY -->
