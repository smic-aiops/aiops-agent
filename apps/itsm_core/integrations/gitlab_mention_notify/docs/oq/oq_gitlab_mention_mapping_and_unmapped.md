# OQ: GitLab Mention Notify - 宛先解決（対応表 + unmapped）

## 対象

- アプリ: `apps/itsm_core/integrations/gitlab_mention_notify`
- ワークフロー: `apps/itsm_core/integrations/gitlab_mention_notify/workflows/gitlab_mention_notify.json`
- 対応表: `docs/mention_user_mapping.md`（GitLab 側の正）

## 受け入れ基準

- 対応表から宛先（Zulip user_id または email）を解決できる
- 対応表に無い `@username` は通知せず、`unmapped` として結果/ログに残す

## テストケース

### TC-01: mapped は通知、unmapped は通知しない

- 前提:
  - `@mapped_user` は対応表に登録済み
  - `@unknown_user` は対応表に未登録
  - `GITLAB_MENTION_NOTIFY_DRY_RUN=true`（検証時）
- 実行: 同一本文に `@mapped_user @unknown_user` を含めて webhook を送信
- 期待:
  - `mentions` に両方が含まれる
  - `unmapped` に `@unknown_user` が含まれる
  - 通知対象（results）には `mapped_user` のみが含まれる

## 証跡（evidence）

- 応答 JSON（`mentions`, `unmapped`, `results`）

