# OQ: GitLab backfill（integration）のスモークテスト（任意）

> NOTE: 本ファイルは互換のため残しています（統合/移動）。正の OQ は `apps/itsm_core/gitlab_backfill_to_sor/docs/oq/oq_gitlab_backfill_smoke_test.md` を参照してください。

## 目的

GitLab backfill（integration）が提供するテスト投入 Webhook により、SoR（`itsm.*`）へのバックフィル系投入が成立することを確認する。

## 受け入れ基準

- `POST /webhook/gitlab/decision/backfill/sor/test` が `HTTP 200` を返す
- `POST /webhook/gitlab/issue/backfill/sor/test` が `HTTP 200` を返す

## テスト手順（例）

本テストは `apps/itsm_core/gitlab_backfill_to_sor` の OQ 実行補助で実行する（統合後も SoR core とは別に同期/運用するため）。

```bash
apps/itsm_core/gitlab_backfill_to_sor/scripts/run_oq.sh
```
