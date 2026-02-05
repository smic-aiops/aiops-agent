# OQ: GitLab Mention Notify - DRY_RUN と OQ 実行（再現性のある検証）

## 対象

- アプリ: `apps/gitlab_mention_notify`
- ワークフロー: `apps/gitlab_mention_notify/workflows/gitlab_mention_notify.json`
- スクリプト: `apps/gitlab_mention_notify/scripts/run_oq.sh`

## 受け入れ基準

- `GITLAB_MENTION_NOTIFY_DRY_RUN=true` で Zulip 送信を抑止しつつ、抽出/宛先解決/整形の確認ができる
- `apps/gitlab_mention_notify/scripts/run_oq.sh` により、webhook 疎通（OQ）を再現性のある手順で確認できる

## テストケース

### TC-01: dry-run で結果確認

- 前提: `GITLAB_MENTION_NOTIFY_DRY_RUN=true`
- 実行: webhook へテスト payload を送信
- 期待:
  - `results[].dry_run=true` が返る
  - Zulip への送信が行われない

### TC-02: run_oq.sh で OQ 実行

- 実行: `apps/gitlab_mention_notify/scripts/run_oq.sh`
- 期待: 実行ログにより、疎通確認が再現性をもって行える

## 証跡（evidence）

- dry-run 応答 JSON
- run_oq.sh の実行ログ

