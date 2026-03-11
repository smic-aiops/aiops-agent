# 詳細設計（UC-3701〜UC-3724）: 人材・タレント管理

本書は、UC-3701〜UC-3724（人材・タレント管理）を `Horilla + GitLab + n8n` で実現するための詳細設計（実装/運用の置き場、証跡、手順）をまとめる。

設計の正:
- `docs/itsm/usecase_new_component_fitgap_gitlab_horilla_n8n_2026-02-25.md`
- `apps/itsm_core/itsm_hr_talent_management/docs/cs/cs.md`

## 1. 設計方針（重複回避）

- `general-management` は「全体ガバナンス/方針/導線」
- `hr-talent-management` は「人材・スキル・育成・RACI の台帳 + 証跡」

本ドメインの正:
- HR の事実（人/組織）: Horilla
- 変更の証跡/台帳（スキル・計画・RACI・方針・標準・レポート）: GitLab

## 2. トレーサビリティ（UC→成果物）

記号:
- `n8n` = ワークフロー（自動化）
- `tpl` = GitLab テンプレ/初期ファイル（台帳・方針）
- `proc` = 手順/運用（自動化しないが証跡を残す）

| UC | 要約 | 実現手段 | 主成果物（例） |
|---|---|---|---|
| UC-3701 | KPI/指標定義 | n8n + tpl | `workflows/hr_talent_monthly_report_*`, `reports/monthly/<YYYY-MM>.md` |
| UC-3702 | ガバナンスと方針運用 | tpl + proc | `docs/policy.md`, `docs/standard.md`（MR 審査） |
| UC-3703 | ステークホルダー調整 | proc | GitLab Issue（議事/合意）、Zulip 連携（任意） |
| UC-3704 | ツール/データ整備 | tpl + proc | `catalog/`, `people/`, `ledger/`, `plans/`, `raci/`, `reports/` |
| UC-3705 | リスク/例外レビュー | proc | 例外は Issue/MR で記録（ラベル/テンプレ運用） |
| UC-3706 | リスクと例外の管理 | proc | 例外の棚卸し（定期レビュー）、是正 MR |
| UC-3707 | レビュー/監査 | proc | MR レビュー + Issue 承認コメント（証跡） |
| UC-3708 | ロードマップ策定 | tpl + proc | `plans/development_plans.yml` + Issue |
| UC-3709 | 合意形成 | proc | Decision を Issue に残す（承認者/日付/根拠リンク） |
| UC-3710 | 変更影響分析 | proc | 変更提案 Issue + 影響欄（テンプレ運用） |
| UC-3711 | 定期レビュー/報告 | n8n + proc | 月次レポート MR + レビュー Issue（任意） |
| UC-3712 | 実行計画 | tpl + proc | `plans/development_plans.yml` |
| UC-3713 | RACI 定義 | tpl + proc | `raci/raci.yml`（MR 審査） |
| UC-3714 | 意思決定基準 | proc | `docs/policy.md`/`docs/standard.md` に明文化 |
| UC-3715 | 成果物の記録/版管理 | tpl | GitLab リポジトリ（履歴は commit/MR） |
| UC-3716 | 指標の定義と可視化 | n8n + proc | `reports/monthly/*.md`（最小の可視化） |
| UC-3717 | 改善優先順位 | proc | Issue に優先度/根拠、MR で反映 |
| UC-3718 | 教育/オンボーディング | proc | 手順書/チェックリスト（docs/）+ Issue |
| UC-3719 | 教育/展開/浸透 | proc | 教育計画 Issue、実施記録 |
| UC-3720 | 方針/ポリシー策定 | tpl + proc | `docs/policy.md` |
| UC-3721 | 標準/ガイドライン整備 | tpl + proc | `docs/standard.md` |
| UC-3722 | 現状評価/ギャップ分析 | proc | アセスメント結果を `reports/` へ MR |
| UC-3723 | 目標/ターゲット設定 | proc | KPI/目標を `docs/` or `plans/` で管理 |
| UC-3724 | 運用手順/標準 | tpl + proc | `docs/oq/oq.md`, OQ 実行結果（evidence） |

## 3. 監査・証跡の最小ルール（MVP）

- 変更の入口は Issue（テンプレで入力項目固定）
- 反映は MR（差分が監査証跡）
- 自動化で作られる MR も、人がレビューできる前提（remove source branch 等）

## 4. 未決事項（設計の余白）

- Horilla の read-only 同期（方式A/B）の確定
- PII の取り扱いルール（`people/people.yml` の項目上限など）
- KPI の定義粒度（スキル更新以外の KPI をどう扱うか）

