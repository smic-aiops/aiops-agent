# OQ（運用適格性確認）: Adapter（AIOps Agent）

## 目的

外部チャネル連携（入力受領/返信）を含む代表パスが、運用上の前提のもとで成立することを確認する。

## 手順（例）

```bash
# OQ 実行（Orchestrator の OQ へ委譲）
apps/aiops_agent/adapter/scripts/run_oq.sh --dry-run
```

## 証跡（最小）

- OQ 応答（JSON 等）と実行ログ

