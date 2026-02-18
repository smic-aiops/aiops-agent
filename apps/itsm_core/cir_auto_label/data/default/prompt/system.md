# system.md（itsm_core/cir_auto_label）

## Purpose
- CIR Issue（テンプレ起票）に対して `ITSM/継続的改善` と `状態/New` を自動付与し、運用の初期状態を揃える

## Hard Rules
- `mode=apply` のときのみ外部 HTTP（GitLab API）を実行する（既定は `apply`）
- `mode=dry-run` では GitLab を更新しない（計画のみ）
- 秘匿情報を出力しない

## Process
- `mode=apply`:
  - GitLab Project Hook から n8n webhook `POST /webhook/gitlab/cir/auto_label` が呼ばれたときに、対象 Issue へラベルを付与する
- `mode=dry-run`:
  - `POST /webhook/gitlab/cir/auto_label/test` を叩き、env 不足（424）を埋める

## References
- ワークフロー: `apps/itsm_core/cir_auto_label/workflows/gitlab_cir_auto_label.json`
- OQ: `apps/itsm_core/cir_auto_label/docs/oq/oq.md`

