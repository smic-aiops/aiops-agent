# OQ: GitLab Issue Metrics Sync - シナリオ3（S3 出力: メトリクス + events）

## 目的

S3 に出力されるキー/形式が期待通りであることを確認します。

## 受け入れ基準（AC）

- `N8N_S3_BUCKET` / `N8N_S3_PREFIX` に従って、以下のキーへ出力される
  - `.../daily_metrics/dt=<YYYY-MM-DD>/realm=<realm>/metrics.json`
  - `.../events/dt=<YYYY-MM-DD>/realm=<realm>/gitlab_issues.jsonl`
- `metrics.json` は JSON（UTF-8）として読める
- `gitlab_issues.jsonl` は 1 行 1 JSON の JSONL（UTF-8）として読める

## テストケース（TC）

| case_id | 実行内容 | 期待結果 |
| --- | --- | --- |
| OQ-GIMS-S3-001 | 実行後に S3 のオブジェクトキーを確認 | 期待のキーが存在する |
| OQ-GIMS-S3-002 | `metrics.json` を取得して JSON として parse | 文字化けなく parse できる |
| OQ-GIMS-S3-003 | `gitlab_issues.jsonl` を取得して各行を JSON として parse | 文字化けなく parse できる |

