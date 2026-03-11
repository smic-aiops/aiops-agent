# 23. 予兆検知（プロアクティブ検知）

**人物**：岡田（Ops）／高橋（運用）／斉藤（Dev）

## 物語（Before）
深夜。突然アプリが落ちる。  
高橋「またか…原因追う前に復旧だ」  
岡田「“落ちてから”じゃ遅い。兆候を拾って手を打てないか？」

## ゴール（価値）
- 障害を「起きてから」ではなく「起きる前」に潰す
- KPI例: `KPI/展開後インシデント数`、`KPI/MTTR`

## 事前に揃っているもの（このプロジェクト）
- 技術管理プロジェクト: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}`
- Issue（テンプレ: `04_技術調査（Spike）` / `08_ソフトウェア開発管理` など）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/issues/new`
- ボード（状態の見える化）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/boards`

## 事前準備（Grafana連携の例）
- 認証: Keycloak の OIDC で Grafana にSSO（閲覧権限はロールで制御）
- 導線: 技術管理 Issue に `{{GRAFANA_BASE_URL}}` とダッシュボードUIDを記載
- 監視データ: S3 へは sulu の CloudWatch Logs のみを集約し、Athena で集計 → Grafana が参照
- 通知: Grafana Alerting → n8n → Zulip 通知 + GitLab Issue 起票

## 実施手順（GitLab / n8n / Grafana）
1. Grafana にアクセス（`{{GRAFANA_BASE_URL}}`）して予兆検知ダッシュボード（CPUスパイク/キュー滞留/エラーレート/レイテンシ）を確認し、アラートを定義（兆候を先に拾う）  
   - 例: CPUスパイク、エラーレート上昇、キュー滞留  
2. アラート→Issue 自動起票（n8n）  
   - 起票先: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/issues`  
   - Issue本文に Grafana の該当パネルURLを貼る（判断を速くする）
3. 兆候の原因を「技術タスク」へ分解  
   - 例: 閾値調整、リソース調整、コード改善、キャパ見直し
4. 運用上の影響がある対策はサービス管理へリンク  
   - `{{SERVICE_MANAGEMENT_PROJECT_PATH}}#XXX`（変更の判断・承認の証跡）


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `23_proactive_detection`（プロアクティブ検知）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 23_proactive_detection
      usecase_name: プロアクティブ検知
      dashboard_uid: tm-proactive-detection
      dashboard_title: Proactive Detection Overview
      folder: ITSM - 技術管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: アラートノイズ
          metric: alert_noise
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 異常検知率
          metric: anomaly_detection_rate
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 誤検知率
          metric: false_positive_rate
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 検知リードタイム
          metric: time_to_detect
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 検知遅延 / 誤検知増加 / アラートノイズ増加
- Zulip チャンネル: #tm-detection
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- アラートから Issue が起票され、Grafana への導線がある
- 対策がMR/CIの履歴として残り、運用判断がリンクされている

## 監査/リアルタイム連携

- 監査イベント: 重要操作（承認、反映、同期）を SoR/ログへ残し、必要ならダッシュボードで追えるようにする（運用 + ETL）
- リアルタイム連携: CloudWatch / webhook を入口にし、n8n で即時に Zulip/GitLab へ反映する

対応ユースケース:
- UC-4505 監査イベント
- UC-4825 リアルタイム連携

<!-- BEGIN TRACEABILITY_GENERAL_FAMILY -->
## 対応ユースケース（トレーサビリティ / general）
- UC-1101 GitLab Push イベントを受信し、必要情報を整形して Zulip に通知する
- UC-4505 監査イベント
<!-- END TRACEABILITY_GENERAL_FAMILY -->

<!-- BEGIN AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
## 対応ユースケース（トレーサビリティ / 移設: 99_missing_usecases）

- 元は `99_missing_usecases.md.tpl` に集約していた未設計ユースケースを、既存の詳細テンプレ（章）へ移設した一覧です。
- 「プラクティス」は `docs/itsm/itsm_oss_features.csv` をソースとし、コンポーネント/操作はそれに基づく設計上の割当です（未実装は命名規約で明示）。

### オブザーバビリティ（1）
#### プラクティス: Grafana; n8n; cloudwatch_event_notify / アプリ: Dashboards; Annotations; Webhook (optional)（1）
- コンポーネント/操作:
  - n8n workflow: `apps/itsm_core/cloudwatch_event_notify/workflows/cloudwatch_event_notify.json`（CloudWatch→分類→通知）
  - （新規）n8n workflow 命名規約: `itsm_オブザーバビリティ_uc0601_*`（各UCのCron/Webhookを作成）
  - Grafana: ダッシュボード/アラート/アノテーション（CMDBの `grafana.usecase_dashboards` で紐付け）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-0601 | UC-GF-100 | Grafana参照/注釈連携 | 🔺 |


<!-- END AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
