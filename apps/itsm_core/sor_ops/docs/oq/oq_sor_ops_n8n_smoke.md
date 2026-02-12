# OQ: SoR Ops - n8n スモークテスト（保持/PII redaction）

## 目的

SoR ops の定期運用（保持/PII redaction）が、n8n ワークフローとして **デプロイ可能**であり、Webhook の dry-run エンドポイントが成立することを確認する。

## 受け入れ基準

- `apps/itsm_core/sor_ops/scripts/deploy_workflows.sh` が dry-run で成立する（差分確認ができる）
- Webhook テストが `HTTP 200` を返し、`ok=true` を返す
- 既定では DB への破壊的変更（保持削除/匿名化）が実行されない（n8n 側の `*_EXECUTE` が false である）
- Cron の既定スケジュールが把握できる（retention: 毎日 03:10 / PII redaction: 毎時 15分）

## 手順（例）

### 1. ワークフロー同期（dry-run）

```bash
DRY_RUN=true WITH_TESTS=false apps/itsm_core/sor_ops/scripts/deploy_workflows.sh
```

### 2. Webhook テスト（dry-run）

`apps/itsm_core/sor_ops/scripts/run_oq.sh` の n8n スモークテストを使う。

```bash
apps/itsm_core/sor_ops/scripts/run_oq.sh --realm-key default --with-n8n --dry-run
```

### 3. Webhook テスト（実行）

テスト用の n8n に対して、HTTP リクエストを実行する（保持/PII redaction 自体は DB 側が dry-run で動く）。

```bash
apps/itsm_core/sor_ops/scripts/run_oq.sh --realm-key default --with-n8n --run
```

### 4. （任意）PII redaction 要求 enqueue の確認

この手順は SoR に書き込みを行うため、**検証環境のテスト principal** に限定して実施する。

```bash
apps/itsm_core/sor_ops/scripts/run_oq.sh \\
  --realm-key default \\
  --with-n8n \\
  --run \\
  --allow-db-write \\
  --enqueue-pii-principal-id "user:test@example.com"
```
