# CIR Issue Close 要求（Requirements）

本書は `apps/itsm_core/cir_issue_close/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/itsm_core/cir_issue_close/README.md`、`apps/itsm_core/cir_issue_close/workflows/`、`apps/itsm_core/cir_issue_close/scripts/` を正とします。

## 1. 対象

system.md 実行の完了後に、対象 CIR Issue を `状態/Closed` に更新して close し、結果サマリを Issue note として残す仕組み。

## 2. 目的

- 実行結果（検証/証跡）を GitLab Issue に残し、監査可能性と追跡性を担保する。
- 重複 note 抑止等により、繰り返し実行でも安全に運用できる。

