# 11. プロジェクト管理

**人物**：PMO／プロジェクトマネージャ

## ゴール（価値）
- プロジェクトの「目的・範囲・責任・計画・進捗・意思決定」が GitLab 上で追跡できる
- 監査可能な証跡（Issue/MR/Commit）で、後から説明できる

## リポジトリの置き場（本プロジェクト）
- プロジェクト台帳（一覧）: `projects/project_register.yml`
- ロードマップ（俯瞰）: `projects/roadmap.md`
- 実行計画（粒度は段階導入）: `plans/project_plans.yml`
- RACI（責務定義）: `raci/raci.yml`
- 定期報告（状態報告/議事）: `reports/`

## 実施手順（MVP）
1. 立ち上げ: Issue（テンプレ: `project_charter`）で目的/範囲/成功条件を固定  
2. 計画: `plans/project_plans.yml` へ追記（MR でレビュー）  
3. 進捗: Issue を board と milestone で追跡（週次/隔週で status report Issue）  
4. 意思決定: Decision Issue（テンプレ: `project_decision`）で根拠を残す  
5. レビュー: 月次で `reports/monthly/` へ状態サマリを追記（MR）  

## 用意されている Issue テンプレ（例）
- `project_charter`: 立上げ（目的/範囲/成功条件/関係者）
- `project_plan`: 実行計画（WBS/マイルストーン/依存）
- `project_milestone`: マイルストーン定義
- `project_status_report`: 定期報告（週次/隔週/月次）
- `project_raci_update`: RACI 更新
- `project_decision`: 意思決定記録

