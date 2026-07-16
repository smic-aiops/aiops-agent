# IQ: ITSM HR Talent Management

## 目的

HR/Talent Management のワークフロー、資格情報参照、GitLab/Zulip/SoR 依存が対象 realm に設置できることを確認する。

## 合格基準

- 全 workflow JSON の構造、node 名、connection 参照が正しい。
- `scripts/run_oq.sh` と deploy/setup script が実行可能で、`bash -n` に合格する。
- IQ/OQ/PQ 文書が揃い、統合マニフェストに登録されている。
- `--execute` 時は本番用 workflow が対象 n8n に存在し active である。

## 実行

```bash
scripts/validation/run_all_apps_iq_oq_pq.sh --suite itsm_core --phase iq --dry-run
scripts/validation/run_all_apps_iq_oq_pq.sh --suite itsm_core --phase iq --execute --realm aiops
```
