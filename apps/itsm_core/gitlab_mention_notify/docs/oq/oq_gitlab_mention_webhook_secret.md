# OQ: GitLab Mention Notify - セキュリティ（Webhook Secret 検証）

## 対象

- アプリ: `apps/itsm_core/gitlab_mention_notify`
- ワークフロー: `apps/itsm_core/gitlab_mention_notify/workflows/gitlab_mention_notify.json`

## 受け入れ基準

- `GITLAB_WEBHOOK_SECRET` が設定されている場合、`X-Gitlab-Token`（`x-gitlab-token`）が不一致のリクエストを拒否する
- 拒否時は Zulip への通知を行わない
  - 注: n8n の手前（WAF/リバースプロキシ等）で遮断される構成では `403` が返る可能性がある。その場合は n8n に到達していないため、アクセス制御層のログで拒否を確認する
- `GITLAB_WEBHOOK_SECRET` が未設定の場合は `424`（`missing=["GITLAB_WEBHOOK_SECRET"]`）で fail-fast し、通知も行わない

## テストケース

### TC-01: token 不一致で拒否

- 前提: `GITLAB_WEBHOOK_SECRET` が設定済み
- 実行: token を不一致にして webhook を送信
- 期待:
  - `ok=false`, `status_code=401`
  - Zulip へ通知されない

## 証跡（evidence）

- 応答 JSON（`status_code=401`）
