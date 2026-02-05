# 19. 廃止・移行（Retirement & Migration）

**人物**：IT責任者／田中（IT企画）

## 物語（Before）
IT責任者「誰も使ってないのに、維持費だけかかる」  
田中「でも、止めるときの影響が怖い…」

## ゴール（価値）
- 廃止判断を“感覚”ではなく、根拠と合意で進める
- 移行を変更管理として統制し、事故を防ぐ

## 事前に揃っているもの（このプロジェクト）
- 変更管理ボード/テンプレ: [変更管理ボード/テンプレ]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/boards)
- CMDB（対象サービスの構成）: [CMDB（対象サービスの構成）]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/tree/main/cmdb)

## 関連テンプレート
- [サービス継続管理](../service_management/10_service_continuity_management.md)
- [サービス構成管理](../service_management/07_service_configuration_management.md)

## 実施手順（GitLab）
1. 廃止の根拠を Issue 化（利用率/コスト/リスク/代替）  
2. 対象サービスの CMDB を参照し、影響分析を残す  
3. 移行は「変更」Issue に落とし込み、ロールバックを必須化  
4. 実施後、結果（コスト削減/リスク低減）を月次へ反映  


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `19_retirement_and_migration`（リタイアメントと移行）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 19_retirement_and_migration
      usecase_name: リタイアメントと移行
      dashboard_uid: retirement-migration
      dashboard_title: Retirement & Migration Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 移行進捗
          metric: migration_progress
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 移行中インシデント
          metric: migration_incidents
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: データ同期遅延
          metric: data_sync_lag
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 切替完了率
          metric: cutover_completion
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 移行遅延 / データ同期遅延 / 移行中障害
- Zulip チャンネル: #itsm-migration
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- 廃止判断の根拠と、移行の統制（変更Issue）が揃っている
