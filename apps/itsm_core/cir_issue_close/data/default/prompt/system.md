# system.md（itsm_core/cir_issue_close）

## Purpose
- system.md 実行の完了後に、対象 CIR（GitLab Issue）を `状態/Closed` + close し、結果サマリを Issue に残す

## Hard Rules
- `mode=apply` のときのみ外部 HTTP（GitLab API）を実行する（既定は `apply`）
- `mode=dry-run` では GitLab を更新しない（計画のみ）
- 秘匿情報を出力しない

## Process
- 入力（必須）:
  - `mode`: `dry-run|apply`
  - `issues`: クローズ対象の CIR Issue（iid/web_url/project_ref）
  - `result_summary`: 結果サマリ（実施内容/検証結果/残課題）
- `mode=apply`:
  - n8n webhook `POST /webhook/itsm/cir/issues/close` を呼び、`dry_run=false` で実行
- `mode=dry-run`:
  - `dry_run=true` で呼び、更新計画を出力する

## References
- ワークフロー: `apps/itsm_core/cir_issue_close/workflows/itsm_cir_issue_close.json`
- OQ: `apps/itsm_core/cir_issue_close/docs/oq/oq.md`

