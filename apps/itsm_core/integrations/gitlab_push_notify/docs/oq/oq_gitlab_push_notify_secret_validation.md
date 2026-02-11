# OQ: GitLab Push Notify - webhook secret 検証（401）

## 対象

- アプリ: `apps/itsm_core/integrations/gitlab_push_notify`
- ワークフロー: `apps/itsm_core/integrations/gitlab_push_notify/workflows/gitlab_push_notify.json`
- Webhook: `POST /webhook/gitlab/push/notify`

## 受け入れ基準

- `GITLAB_WEBHOOK_SECRET` が設定されている場合、`x-gitlab-token` が不一致のリクエストを `401` で拒否する
- 拒否時は通知を行わない
- ただし、n8n の手前（WAF/リバースプロキシ等）で遮断される構成では `403` が返る可能性がある。その場合は「n8n に到達していない」ことを示すため、OQ の証跡としては許容し、別途アクセス制御層のログで確認する
- `GITLAB_WEBHOOK_SECRET` が未設定の場合は `424`（`missing=["GITLAB_WEBHOOK_SECRET"]`）で fail-fast し、通知も行わない

## テストケース

### TC-01: token 不一致で 401

- 前提: `GITLAB_WEBHOOK_SECRET` が設定済み
- 実行: `x-gitlab-token` を不一致にして `POST /webhook/gitlab/push/notify`
- 期待:
  - 応答が `ok=false`, `status_code=401`
  - Zulip へ通知されない

## 証跡（evidence）

- 応答 JSON（`status_code=401`）
- Zulip 側に投稿が無いこと（任意）
