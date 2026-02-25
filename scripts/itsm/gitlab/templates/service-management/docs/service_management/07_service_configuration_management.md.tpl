# 07. サービス構成管理

## 目的
- 構成情報（CI）の正を CMDB に集約し、変更と整合を取る

## このテンプレでの“正”
- CMDB（正）: `cmdb/<組織ID>/<サービスID>.md`

## 運用の型（GitLab）
1. サービスの構成（依存/連絡先/監視/ダッシュボード/Runbook）を CMDB に記載  
2. 構成変更は「変更」Issue とリンクして統制する  
3. 監視導線（Grafana/AWS）や SLA 定義（`docs/sla_master.md`）の参照を揃える  

## 関連テンプレート
- ユースケース: [廃止・移行](../usecases/19_retirement_and_migration.md)
- Issue テンプレ: `04_change.md`

## Done（完了条件）
- CMDB を起点に、運用に必要な参照情報へ最短で辿れる

