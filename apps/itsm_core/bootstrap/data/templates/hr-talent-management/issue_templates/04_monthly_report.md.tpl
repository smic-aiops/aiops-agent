## 月次レポート生成（レビュー用Issue）

### 対象月（YYYY-MM）
<!-- 例: 2026-02 -->

### 目的
- 月次レポート（`reports/monthly/<YYYY-MM>.md`）の生成・レビュー・承認を追跡する

### 手順（MVP）
1. n8n の webhook で生成を実行（dry-run で内容確認推奨）
   - `POST /webhook/hr/talent/report/monthly/generate/request`
   - body 例: `{"month":"YYYY-MM","dry_run":true}`
2. dry-run の結果を確認し、`dry_run:false` で MR を作成する
3. 作成された MR をレビューしてマージする

### 期待する証跡
- 本Issue（計画/合意）
- 生成された MR（差分）

