# OQ（運転時適格性確認）: ITSM HR Talent Management

本 OQ は、MVP の成立（Horilla/GitLab/Zulip への最小 read/write と承認フローの最小パス）を確認するための最小ケースを定義する。

## OQ-1: 接続確認（read-only）
- Horilla: 人/組織の取得（方式Aの場合）
- GitLab: プロジェクト参照（read）
- Zulip: Bot での投稿（write）

## OQ-2: スキル更新（承認→反映）
- Webhook でスキル更新要求を投入できる
- GitLab Issue が作成される
- 承認コメント（`/approve`）を検出して MR が作られる

## OQ-3: 定期レポート（手動実行）
- 手動トリガでレポート生成ができ、`reports/` に MR で反映される

### 実行手順（MVP）
- n8n への同期: `bash apps/itsm_core/itsm_hr_talent_management/scripts/deploy_workflows.sh`
- OQ（スモーク）: `bash apps/itsm_core/itsm_hr_talent_management/scripts/run_oq.sh`
- 月次レポート生成（dry-run の例）:
  - `POST /webhook/hr/talent/report/monthly/generate/request` body: `{"month":"2026-02","dry_run":true}`

### 合格基準（MVP）
- dry-run の応答が `ok=true` を返し、`report_markdown` と `counts` が妥当
- `dry_run:false` 実行で MR が作成され、`reports/monthly/<YYYY-MM>.md` が差分として含まれる
