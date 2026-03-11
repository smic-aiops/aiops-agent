# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### CIR Approved Usecase List（n8n） / GAMP® 5 第2版（2022, CSA ベース, IQ/OQ/PQ を含む）

---

## 1. CSV / CSA ポリシー
**目的**
`apps/README.md` の共通フォーマットに従い、リスクベース（CSA）で最小限の成果物として本 README と検証証跡を維持する。

**内容**
- 一般管理プロジェクトの CIR（継続的改善レジスター）＝ GitLab Issue から、`状態/Approved` のレコードを抽出し、本文からユースケース機能ID（`UC-*`）を抽出して返す。
- 秘密情報（GitLab token）は tfvars に平文で置かず、SSM/Secrets Manager → n8n 環境変数注入を前提とする。

---

## 2. バリデーション計画（VP）
**対象**
- n8n ワークフロー（Webhook）による GitLab Issue 検索とユースケース抽出

**成果物（最小）**
- 本 README
- OQ 文書: `apps/itsm_core/cir_usecase_list/docs/oq/oq.md`
- OQ 実行補助: `apps/itsm_core/cir_usecase_list/scripts/run_oq.sh`

---

## 3. 意図した使用（Intended Use）とシステム概要
**Intended Use**
- CIR（GitLab Issue）を **承認済み（`状態/Approved`）** にしたものを一覧し、ユースケース定義（`UC-*`）を抽出して、後続のドキュメント更新や同期処理の入力にする。

上位の運用フロー（CIR→Docs→実装→クローズ）は以下を正とする:
- `apps/itsm_core/bootstrap/docs/cir_continual_improvement_flow.md`

**Webhook**
- 一覧取得: `POST /webhook/itsm/cir/usecases/approved/list`
- テスト（環境変数チェック）: `POST /webhook/itsm/cir/usecases/approved/list/test`

**ディレクトリ構成**
- `apps/itsm_core/cir_usecase_list/workflows/`: n8n ワークフロー（JSON）
- `apps/itsm_core/cir_usecase_list/scripts/`: デプロイ・OQ 実行
- `apps/itsm_core/cir_usecase_list/docs/oq/`: OQ

**環境変数（代表）**
- GitLab
  - `GITLAB_API_BASE_URL`（または `GITLAB_BASE_URL` から導出）
  - `GITLAB_TOKEN`（または `N8N_GITLAB_TOKEN`）
  - （任意）`GITLAB_GROUP_FULL_PATH`（未指定の場合、既定は `${N8N_REALM}/general-management`）

---

## 4. 検証（OQ）
`apps/itsm_core/cir_usecase_list/scripts/run_oq.sh` を実行し、テスト Webhook が 200 を返すことを確認する。

---

## 5. 同期（n8n Public API へ upsert）
```bash
apps/itsm_core/cir_usecase_list/scripts/deploy_workflows.sh
```
