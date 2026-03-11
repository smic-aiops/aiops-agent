# OQ: GitLab CIR Status Notify

## 目的
GitLab Issue（CIR）の **`状態/Approved` / `状態/Closed`** ラベル付与を検知し、改善要求者へ **Zulip DM** を送れること、かつ **重複通知が抑止**されることを確認します。

## 前提
- n8n にワークフローを同期済み
  - `apps/itsm_core/cir_status_notify/workflows/gitlab_cir_status_notify.json`
  - `apps/itsm_core/cir_status_notify/workflows/gitlab_cir_status_notify_test.json`
- GitLab 側で Issue Hook を `POST /webhook/gitlab/cir/status/notify` に向けて設定済み
- CIR Issue description に `起票者`（Zulip のメールアドレス）が入っていること

## 手順
1. スモーク（dry-run）: `apps/itsm_core/cir_status_notify/scripts/run_oq.sh --dry-run` を実行し、叩くべき webhook が表示されることを確認する
2. 疎通（apply）: `apps/itsm_core/cir_status_notify/scripts/run_oq.sh` を実行し、`/test` が 200 で返ることを確認する
3. GitLab general-management に Issue Hook（Project Hook）を設定する
   - `apps/itsm_core/cir_status_notify/scripts/setup_gitlab_general_management_issue_hook.sh --gitlab-base-url <...> --gitlab-token <...> --n8n-base-url <...> --webhook-secret <...> --realm <...>`
4. テストプログラムで CIR Issue を作成し、ラベル `状態/Approved` を付与する（GitLab API）
   - `apps/itsm_core/cir_status_notify/scripts/e2e_approve_cir_issue.sh --gitlab-base-url <...> --gitlab-token <...> --requester-email <...> --realm <...>`
5. 起票者（メール）へ Zulip DM が届くことを確認
6. 同じ payload が再送されても DM が 2 回届かないことを確認（SoR の `integrity.event_key` で抑止）
7. （任意）運用者がラベル `状態/Closed` を付与し、同様に DM が届くことを確認

## 受け入れ基準
- `状態/Approved` / `状態/Closed` の **追加**を検知したときのみ通知される
- 同一イベントは 1 回だけ通知される（SoR 冪等）
