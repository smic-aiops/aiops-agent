# OQ: ユースケース別カバレッジ（gitlab_issue_rag）

## 目的

`apps/itsm_core/gitlab_issue_rag/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

## 対象

- アプリ: `apps/itsm_core/gitlab_issue_rag`
- OQ 正: `apps/itsm_core/gitlab_issue_rag/docs/oq/oq.md`

## ユースケース別 OQ シナリオ

### 14_knowledge_management（14. ナレッジ管理）

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/14_knowledge_management.md.tpl`
- 実施:
  - `oq_s1_fetch_format.md`
  - `oq_s2_chunk_embed_upsert.md`
  - `oq_s5_system_notes_toggle.md`
- 受け入れ基準:
  - Issue/notes が取得・整形され、検索に使える形で upsert される
- 証跡:
  - 取り込み件数、サンプルレコード確認（秘匿はマスク）

### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- 実施:
  - `oq_s3_scheduled_diff_sync.md`
- 受け入れ基準:
  - 定期/差分同期が成立し、負荷と時間を制御できる
- 証跡:
  - 差分条件と同期件数のログ

### 27_data_platform（27. データ基盤）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/27_data_platform.md.tpl`
- 実施:
  - `oq_s2_chunk_embed_upsert.md`
  - `oq_s7_webhook_test_pgvector.md`
- 受け入れ基準:
  - 保存先（pgvector）の疎通/格納が成立する
- 証跡:
  - `/test` あるいは疎通結果ログ

### 28_poc（28. PoC（技術検証））

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/28_poc.md.tpl`
- 実施:
  - `oq_s4_embedding_skip_dryrun.md`
- 受け入れ基準:
  - embedding を抑止/切替でき、コストと検証を制御できる
- 証跡:
  - skip/dry-run の結果ログ

### 30_developer_experience（30. 開発者体験（Developer Experience））

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/30_developer_experience.md.tpl`
- 実施:
  - `oq_s8_observability_and_retry.md`
  - `oq_s6_metadata_domain_routing.md`
- 受け入れ基準:
  - 失敗時の追跡/再実行が可能で、取り込み対象の誤りを抑止できる
- 証跡:
  - リトライ/失敗ログ、ルーティング結果ログ

