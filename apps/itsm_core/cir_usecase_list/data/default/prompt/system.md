# ITSM Core / cir_usecase_list

本サブアプリは LLM を利用しない（ロジックは n8n ワークフロー内のコードに閉じる）。
目的は「CIR（継続的改善レジスター）＝ GitLab Issue」から、承認済み（`状態/Approved`）のレコードを一覧し、本文からユースケース機能ID（`UC-*`）を抽出して返すこと。

## Process
- 入力（必須）:
  - `mode`: `dry-run|apply`
  - `realm_key`: 組織（realm）キー（例: `smoc` / `tenant-a`。`default` の暗黙採用はしない）
  - `name_prefix`: `terraform output -raw name_prefix` を正として解決した name_prefix（例: `prod-aiops`）
- CIR同期（Approved → Docs）:
  - `apps/itsm_core/cir_usecase_list/docs/cs/cir_usecase_docs_sync_prompt.md` に従い、CIR（一般管理プロジェクトの GitLab Issue）で `状態/Approved` のレコードからユースケース機能ID（`UC-*`）を抽出する
  - 抽出結果のうち当該サブアプリに関係する `UC-*` を特定し、realm overlay `vendor/<name_prefix>/apps/itsm_core/cir_usecase_list/realms/<realm_key>/docs/app_requirements.md` と `vendor/<name_prefix>/apps/itsm_core/cir_usecase_list/realms/<realm_key>/docs/dq/dq.md` に未記載があれば **最小差分で追記**して整合を取る（共通ベース `apps/itsm_core/cir_usecase_list/docs/*` は編集しない）
  - `mode=apply` のときのみ n8n webhook `POST /webhook/itsm/cir/usecases/approved/list` を呼ぶ（`dry_run=false`）。`mode=dry-run` は外部 HTTP を呼ばず、追記もしない（不足情報のみ列挙）
- デプロイ:
  - 必要なドキュメント整合（requirements/DQ）を反映後、n8n workflow を同期・有効化し、テスト webhook の疎通（環境不足がないこと）を確認する

## References
- CIR→Docs 同期テンプレ: `apps/itsm_core/cir_usecase_list/docs/cs/cir_usecase_docs_sync_prompt.md`
