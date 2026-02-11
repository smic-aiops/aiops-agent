# OQ: Zulip↔GitLab Issue 同期（Zulip GitLab Issue Sync）

## 対象

- アプリ: `apps/itsm_core/integrations/zulip_gitlab_issue_sync`
- ワークフロー: `apps/itsm_core/integrations/zulip_gitlab_issue_sync/workflows/zulip_gitlab_issue_sync.json`
- 実行方法: n8n 手動実行、または `apps/itsm_core/integrations/zulip_gitlab_issue_sync/scripts/run_oq.sh`

## 受け入れ基準

- Zulip 側の投稿/スレッドと GitLab Issue/コメントが同期される（作成/更新/クローズ等の差分が反映される）
- 決定メッセージ（例: `/decision`）が GitLab Issue に「決定（Zulip）」として証跡記録される
- GitLab 側の決定（例: `[DECISION]` / `決定:`）が Zulip の該当トピックへ通知される
- 同期結果（サマリ）が Zulip へ通知される
- 実行結果として `ok=true` 相当の完了（ワークフロー失敗で終了しない）となる

## テストケース

### TC-01: 手動同期（OQ）

- 前提:
  - `apps/itsm_core/integrations/zulip_gitlab_issue_sync/workflows/zulip_gitlab_issue_sync.json` が n8n に同期済み
  - Zulip/GitLab の接続用環境変数が設定済み
  - 同期対象の stream/topic に、ボット以外の投稿が存在する（ボット投稿のみの場合はスキップされる）
- 実行:
  - n8n から `Zulip GitLab Issue Sync` を手動実行（または `apps/itsm_core/integrations/zulip_gitlab_issue_sync/scripts/run_oq.sh` を実行して直近の実行結果を確認）
- 期待:
  - GitLab 側で Issue/コメントの作成/更新が行われる（必要な差分があれば）
  - Zulip 側へ結果が投稿される（対象 stream/topic/DM のいずれか）
  - n8n 実行が失敗終了しない

### TC-02: 決定メッセージの証跡化（OQ）

- 前提:
  - TC-01 と同じ
  - 同期対象の topic に対し、決定メッセージ（例: `/decision ...`）が投稿できる
- 実行:
  - Zulip に `/decision 決定内容...` を投稿（同一 topic）
  - n8n から `Zulip GitLab Issue Sync` を手動実行
- 期待:
  - GitLab Issue のコメントに `### 決定（Zulip）` が追記され、Zulip メッセージ URL が含まれる
  - Zulip 側へ「決定をGitLabへ証跡として記録しました」相当の通知が投稿される

### TC-03: GitLab 決定の Zulip 通知（OQ）

- 前提:
  - `apps/itsm_core/integrations/zulip_gitlab_issue_sync/workflows/gitlab_decision_notify.json` が n8n に同期済み
  - GitLab の Group Webhook が `POST /webhook/gitlab/decision/notify` を指し、Issue events / Note events が有効
  - Zulip のトピック URL（`#narrow/stream/.../topic/...`）が GitLab Issue 本文に含まれている（Zulip 起票由来なら通常含まれる）
- 実行:
  - GitLab Issue のコメント先頭に `[DECISION] ...` または `決定: ...` を投稿
- 期待:
  - Zulip の該当 stream/topic へ「GitLab で決定が記載されました」相当の通知が投稿される

## 証跡（evidence）

- n8n 実行ログ（Zulip/GitLab API 呼び出しの成功/失敗）
- GitLab Issue/コメントの差分（作成/更新/クローズ等）
- Zulip 側の通知投稿（投稿先・内容の確認）
