# OQ-USECASE-28: 承認リンク（クリック）を決定として扱い、履歴を参照できる

## 目的
AIOpsAgent が提示した承認導線（approve/deny）について、**リンククリックで確定した結果**を Zulip 上の `/decision` として扱い、証跡（承認履歴）を保存し、Zulip から `/decisions` で **時系列サマリ**を参照できることを確認する。

## 前提
- Zulip の Outgoing Webhook が `POST /webhook/ingest/zulip` を指していること
- 承認確定の受信口が利用可能であること
  - `POST /webhook/approval/confirm`
  - `GET /webhook/approval/click`（クリック用）
- Zulip（mess bot）送信設定が有効であること（承認確定後の `/decision` 投稿）
- ContextStore / ApprovalStore / ApprovalHistory が利用可能であること（`aiops_*`）

## 手順
1. Zulip で AIOpsAgent に対し、承認が必要になる依頼を送る（例: `run <workflow_id> {...}`）
2. 返信に次が含まれることを確認する
   - 承認コマンド（`approve <token>` / `deny <token>`）
   - （任意）承認リンク（クリック）: `.../webhook/approval/click?decision=approve|deny&token=...`
3. 承認リンク（approve）をクリックして確定する
4. Zulip の同一トピックに **`/decision`** で始まる決定ログが投稿されることを確認する
5. Zulip で `/decisions` を投稿する
6. AIOpsAgent が「決定履歴（AIOpsAgent 承認/自動承認）」の時系列サマリを返し、直前の承認が含まれることを確認する

## 期待出力
- クリックで確定した approve/deny が **Zulip の `/decision`** として可視化される
- `aiops_approval_history` に承認履歴が保存され、`comment` に `/decision` 先頭行が残る
- `/decisions` が **同一トピック（同一 context）** の履歴を時系列で返す

## 合否基準
- **合格**: クリック承認が `/decision` として投稿され、`/decisions` で履歴が参照できる
- **不合格**: クリック承認が記録されない、別トピックへ投稿される、または履歴参照が成立しない

## 証跡（evidence）
- Zulip の返信（承認コマンド/リンク）と、承認確定後の `/decision` 投稿のスクリーンショット
- n8n 実行履歴（`aiops-adapter-approval` / `aiops-adapter-ingest`）
- DB の `aiops_approval_history` 該当レコード（`context_id`, `approval_id`, `decision`, `created_at`, `comment`）

## 失敗時の切り分け
- 承認リンクが表示されない: `N8N_APPROVAL_BASE_URL` の注入、`approval_base_url` の値、`supports_links` の扱いを確認
- クリックしても確定しない: `GET /webhook/approval/click` の到達、token 署名（HMAC）、有効期限（expires_at）を確認
- `/decision` が投稿されない: Zulip（mess bot）の `N8N_ZULIP_*` 設定、送信先（reply_target）解決を確認
- `/decisions` が空: `aiops_approval_history` の `context_id` で記録されているか確認

## 関連
- `apps/aiops_agent/docs/zulip_chat_bot.md`
- `apps/itsm_core/zulip_gitlab_issue_sync/README.md`
- `docs/usage-guide.md`
