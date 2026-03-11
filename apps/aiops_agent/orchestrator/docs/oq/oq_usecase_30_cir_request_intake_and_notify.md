# OQ-USECASE-30: 改善要望（CIR）を集約し、承認時に依頼者へ通知できる

## 目的
ユーザー要望（例: 「○○ができるようになって」）を受領し、GitLab の一般管理プロジェクトの CIR（継続的改善レジスター）Issue に重複排除しながら集約できること、さらに運用者が `Approved` に更新した際に依頼者へ通知できることを確認する。

## 前提
- Zulip の Outgoing Webhook が `POST /webhook/ingest/zulip` を指していること
- CIR 登録連携（GitLab API 連携）が有効であること
- 同一要望の重複判定に必要な保存先（`aiops_context` / `aiops_approval_history` / CIR 連携テーブル等）が利用可能であること
- 承認状態の変更（`New` -> `Approved`）を AIOpsAgent が受信できること（Webhook または定期同期）

## 手順
1. Zulip で改善要望を投稿する（例: `AIOpsAgent さん、申請時に必須項目チェックの理由を表示できるようにしてください`）
2. AIOpsAgent が受領メッセージを返し、CIR 登録対象として処理したことを確認する
3. GitLab の一般管理プロジェクトに CIR Issue が `New` で作成されることを確認する
4. 同じ要望を再投稿し、重複 Issue を新規作成しないことを確認する（既存 Issue へ集約）
5. 運用者が対象 CIR Issue を `Approved` に更新する
6. AIOpsAgent が依頼者へ「以前のご要望は承認されたので改善を進める」旨を同一会話へ通知することを確認する

## 期待出力
- 改善要望が CIR Issue（一般管理）へ登録される
- 同一内容の再投稿で重複 Issue が増えず、既存 Issue へ集約される
- `Approved` 更新後、依頼者への通知メッセージが投稿される

## 受け入れ基準
- **合格**: CIR 集約（重複排除）と `Approved` 後の依頼者通知が両方成立する
- **不合格**: CIR が未作成/重複作成される、または `Approved` 後に依頼者通知が行われない

## 証跡（evidence）
- Zulip の要望投稿・受領返信・承認後通知のスクリーンショット
- GitLab Issue（`New` 作成、重複時の集約、`Approved` 更新）の画面キャプチャまたは API レスポンス
- n8n 実行履歴（`aiops-adapter-ingest` と CIR 連携ワークフロー）
- DB 証跡（`context_id`, `trace_id`, CIR Issue ID, 重複判定キー）

## 失敗時の切り分け
- CIR が作成されない: GitLab 接続情報、対象プロジェクト ID、トークン権限、連携ワークフローの失敗ノードを確認
- 重複排除が効かない: dedupe キー（要望正規化テキスト、project_id、state）と既存検索条件を確認
- `Approved` 通知が来ない: 状態変更イベント受信（Webhook/同期ジョブ）、依頼者マッピング（reply_target/mention mapping）を確認

## 関連
- `apps/aiops_agent/orchestrator/docs/app_requirements.md`（UC-AIOPS-OFF-016）
- `apps/aiops_agent/orchestrator/docs/dq/dq.md`（DQ-OFF-014）
- `apps/aiops_agent/orchestrator/docs/oq/oq.md`
