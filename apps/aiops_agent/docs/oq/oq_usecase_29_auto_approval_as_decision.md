# OQ-USECASE-29: 自動承認（auto_enqueue）を決定として扱い、履歴を参照できる

## 目的
AIOpsAgent が `auto_enqueue`（自動承認/自動実行）を選択した場合に、**自動承認の結果**を Zulip 上の `/decision` として扱い、証跡（承認履歴）を保存し、Zulip から `/decisions` で **時系列サマリ**を参照できることを確認する。

## 前提
- Zulip の Outgoing Webhook が `POST /webhook/ingest/zulip` を指していること
- Zulip（mess bot）送信設定が有効であること（自動承認後の `/decision` 投稿）
- ContextStore / ApprovalHistory が利用可能であること（`aiops_*`）
- `auto_enqueue` になるポリシー/ワークフローが用意されていること（例: 低リスクで承認不要な実行）

## 手順
1. Zulip で AIOpsAgent に対し、`auto_enqueue` が選択される依頼を送る（例: 低リスクの runbook 実行）
2. AIOpsAgent の処理結果として、同一トピックへ **`/decision`** で始まる決定ログが投稿されることを確認する
   - `correlation_id`（`context_id`/`trace_id` 等）や `job_id`、要約（`summary`）が含まれること
3. Zulip で `/decisions` を投稿する
4. AIOpsAgent が「決定履歴（AIOpsAgent 承認/自動承認）」の時系列サマリを返し、直前の自動承認が含まれることを確認する

（任意）GitLab 証跡も確認する（環境により無効な場合あり）:
5. 対応する GitLab Issue に `### 決定（Zulip）` の証跡コメントが追加されていることを確認する
   - 決定メッセージへのリンク
   - 要約
   - `correlation_id`（`context_id`/`trace_id`/`job_id` 等）

## 期待出力
- `auto_enqueue` の結果が **Zulip の `/decision`** として可視化される
- `aiops_approval_history` に履歴が保存され、`comment` に `/decision` 先頭行が残る
- `/decisions` が **同一トピック（同一 context）** の履歴を時系列で返す

## 合否基準
- **合格**: 自動承認が `/decision` として投稿され、`/decisions` で履歴が参照できる
- **不合格**: 自動承認が記録されない、別トピックへ投稿される、または履歴参照が成立しない

## 証跡（evidence）
- Zulip の依頼と、自動承認後の `/decision` 投稿のスクリーンショット
- n8n 実行履歴（`aiops-adapter-ingest`）
- DB の `aiops_approval_history` 該当レコード（`context_id`, `approval_history_id`, `decision`, `created_at`, `comment`）
- （任意）GitLab Issue の証跡コメント

## 失敗時の切り分け
- 自動承認が発生しない: 該当ポリシー（承認要否/閾値）と `next_action` を確認
- `/decision` が投稿されない: Zulip（mess bot）の `N8N_ZULIP_*` 設定、送信先（reply_target）解決、`AIOPS_ZULIP_APPROVAL_AS_DECISION` を確認
- `/decisions` が空: `aiops_approval_history` に `context_id` で記録されているか確認（`approval_history_id` が重複していないかも確認）

## 関連
- `apps/aiops_agent/docs/zulip_chat_bot.md`
- `apps/itsm_core/integrations/zulip_gitlab_issue_sync/README.md`
- `docs/usage-guide.md`

