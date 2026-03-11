# 運用判断・実行ハブ（Signal Fusion / Change Guard / Agent Actions）

このページは「運用の判断」と「実行」を同じ導線で回すためのハブです。  
判断材料の詳細は Grafana、承認と記録は GitLab を正とします。

## まず見る場所
- Grafana: `{{GRAFANA_BASE_URL}}`

## 画面の狙い（3レイヤ）
- Signal Fusion: 相関分析でイベントを集約し、状況を一言で示す
- Change Guard: 変更管理の自動リスク評価と差分提示
- Agent Actions: 自動復旧候補を提示し、承認後に実行

## ダッシュボード設計（例）
| 領域 | 目的 | 主な表示 | 参照 |
| --- | --- | --- | --- |
| Signal Fusion | 状況の要約 | 重要イベント束ね、影響範囲、要約文 | Grafana |
| Change Guard | 変更リスクの可視化 | 変更差分、影響範囲、リスクスコア | Grafana |
| Agent Actions | 実行候補の比較 | 復旧候補、想定影響、承認状況 | Grafana |

## GitLab との連携（基本ルール）
- 判断の根拠は Grafana のリンクとして Issue に貼る
- 承認は GitLab の Issue/MR/Change Issue で実施し、結果を記録する

## CMDB との紐付け例
CMDB の `grafana.usecase_dashboards` に UID とタイトルを登録します。

```yaml
grafana:
  usecase_dashboards:
    - dashboard_uid: ops-decision-hub
      dashboard_title: Ops Decision Hub
    - dashboard_uid: signal-fusion
      dashboard_title: Signal Fusion Overview
    - dashboard_uid: change-guard
      dashboard_title: Change Guard Overview
    - dashboard_uid: agent-actions
      dashboard_title: Agent Actions Overview
```

## 運用フロー（例）
1. Issue を起票し、状況/変更/作業のラベルを付与
2. 本ページから Grafana に遷移し、根拠を確認
3. Issue に Grafana へのリンクと判断コメントを残す
4. 承認後、実行結果を Issue に記録する

## 参照
- 監視参照の統一ガイド: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md`
