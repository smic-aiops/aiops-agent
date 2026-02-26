# 人材・タレント管理（GitLab + Zulip）設計

対象:
- `docs/itsm/itsm_oss_features.csv` の「人材・タレント管理」カテゴリ（UC-3701〜UC-3724）

## 目的

- 人材・スキルに関する方針/合意/証跡/教育/目標を、GitLab（版管理/証跡）と Zulip（合意形成/通知）で運用できる形にする。
- HRMS（Horilla）は台帳領域を担うが、本基盤では **ITSM の正本（SoR）は GitLab/共有RDS** とし、まずは「人材運用の証跡」を GitLab に集約する。

## 役割分担

- GitLab
  - 方針（policy）、運用手順（operations）、指標定義（metrics/kpi）を `docs/` に集約（MR レビューで更新）
  - KPI/育成/改善施策/レビュー結果は Issue を正として記録（テンプレ + ボード + マイルストーン）
- Zulip
  - 相談/周知/合意形成の窓口（stream/topic）
  - 決定は `/decision`（または GitLab Issue の `[DECISION]`）で明示し、リンクで GitLab の正本へ誘導

## 最小の運用オブジェクト（GitLab）

- `docs/`（版管理の正）
  - `policy.md`（原則/禁止事項）
  - `operations.md`（レビュー頻度、責任者、承認導線）
  - `metrics_kpi.md`（KPI とターゲット）
  - `raci.md`（役割/責任）
- Issue（証跡の正）
  - KPI レビュー（月次/四半期）
  - 育成/オンボーディング計画
  - 改善施策（バックログ）
  - 例外/リスク（期限付き）

## UC 対応（この設計でカバー）

`UC-3701` `UC-3702` `UC-3703` `UC-3704` `UC-3705` `UC-3706` `UC-3707` `UC-3708` `UC-3709` `UC-3710` `UC-3711` `UC-3712` `UC-3713` `UC-3714` `UC-3715` `UC-3716` `UC-3717` `UC-3718` `UC-3719` `UC-3720` `UC-3721` `UC-3722` `UC-3723` `UC-3724`

