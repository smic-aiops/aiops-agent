# OQ: GitLab CIR Auto Label

## 目的
GitLab general-management の CIR Issue（テンプレ起票）について、起票直後に **`ITSM/継続的改善` と `状態/New` を自動付与**できることを確認します。

## 手順
1. スモーク（dry-run）: `apps/itsm_core/cir_auto_label/scripts/run_oq.sh --dry-run` を実行し、叩くべき webhook が表示されることを確認する
2. 疎通（apply）: `apps/itsm_core/cir_auto_label/scripts/run_oq.sh` を実行し、`/test` が 200 で返ることを確認する（424 の場合は n8n 側の env を埋める）
3. GitLab general-management に Issue Hook（Project Hook）を設定する
   - `apps/itsm_core/cir_auto_label/scripts/setup_gitlab_general_management_issue_hook.sh --gitlab-base-url <...> --gitlab-token <...> --n8n-base-url <...> --webhook-secret <...> --realm <...>`
4. CIR テンプレ（`continual_improvement_register`）で Issue を起票する
5. 起票した Issue に `ITSM/継続的改善` と `状態/New` が付与されることを確認する
6. 既に `状態/*` がある場合、`状態/New` が上書きされないことを確認する

