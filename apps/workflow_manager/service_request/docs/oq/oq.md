# OQ（運用適格性確認）: Service Request（Workflow Manager）

## 目的

サービスリクエスト系ワークフロー（例: GitLab サービスカタログ同期、Sulu サービス制御）の外部接続（n8n API/GitLab/Service Control/GitHub）を確認します。

## 前提

- n8n に次のワークフローが同期済みであること
  - `apps/workflow_manager/service_request/workflows/` 配下の各ワークフロー
- 環境変数（`apps/workflow_manager/README.md` 記載）が設定済みであること

## OQ ケース（接続パターン別）

| case_id | 接続パターン | 実行内容 | 期待結果 |
| --- | --- | --- | --- |
| OQ-WSR-DEP-001 | オペレーター → n8n Public API | ワークフロー群を upsert（dry-run→本番） | 差分が確認でき、upsert が完了して active になる |
| OQ-WSR-EXT-001 | n8n → GitLab API | `/webhook/tests/gitlab/service-catalog-sync?dry_run=true` を実行 | `ok=true`、missing が空 |
| OQ-WSR-EXT-002 | n8n → Service Control API | `/webhook/sulu/service-control` を実行 | `status=ok` を返し、API 呼び出しが成功 |
| OQ-WSR-EXT-003 | n8n → Service Control API/ECR | `/webhook/tests/sulu/version-deploy` を実行 | 指定タグのPHP/Nginxイメージが検証され、実変更なしで`ok=true` |
| OQ-WSR-EXT-004 | n8n → GitHub Compare API | `/webhook/tests/sulu/source-version-compare` を実行 | 比較元・比較先のソース差分と修正候補が返り、`ok=true` |
| OQ-WSR-EXT-005 | n8n → GitLab/Service Control/CodeBuild/ECR | `/webhook/tests/sulu/rfc-source-analysis` を実行 | RFC対象バージョンが分析され、ECR push計画が非破壊で検証される |
| OQ-WSR-SEC-001 | 未認証クライアント → n8n/Service Control | BearerなしでSulu build/deployを要求 | HTTP 401で拒否される |
| OQ-WSR-GRD-001 | n8n/Service Control | `latest`、実行許可なし、既存タグ、PHP/Nginx片系を検証 | 変更前に拒否される |
| OQ-WSR-ERR-001 | CodeBuild/ECS/ALB | build失敗・timeout、rollout失敗・timeout、unhealthyを検証 | 成功扱いにせず失敗証跡を返す |
| OQ-WSR-LIVE-001 | GitLab → CodeBuild/ECR → ECS/ALB | 承認済み実RFCで新規タグをbuild/pushし実デプロイ | CAB署名、両ECR、task definition、rollout、healthy targetの証跡が揃う |

<!-- OQ_SCENARIOS_BEGIN -->
## OQ シナリオ（詳細）

このセクションは同一ディレクトリ内の `oq_*.md` から自動生成されます（更新: `scripts/generate_oq_md.sh`）。
個別シナリオを追加/修正した場合は、まず `oq_*.md` を更新し、最後に本スクリプトで `oq.md` を更新してください。

### 一覧
- [oq_gitlab_service_catalog_sync.md](oq_gitlab_service_catalog_sync.md)
- [oq_sulu_memory_regression_demo.md](oq_sulu_memory_regression_demo.md)
- [oq_sulu_rfc_source_analysis.md](oq_sulu_rfc_source_analysis.md)
- [oq_sulu_service_control.md](oq_sulu_service_control.md)
- [oq_sulu_source_version_compare.md](oq_sulu_source_version_compare.md)
- [oq_sulu_version_deploy.md](oq_sulu_version_deploy.md)
- [oq_workflow_sync_deploy.md](oq_workflow_sync_deploy.md)

---

### OQ: GitLab サービスカタログ同期（dry-run）（source: `oq_gitlab_service_catalog_sync.md`）

#### 目的
GitLab のサービスカタログ（workflow catalog）情報を同期し、missing が解消されることを確認する（テスト用 webhook の dry-run）。

#### 受け入れ基準
- `GET /webhook/tests/gitlab/service-catalog-sync?dry_run=true` が `HTTP 200` を返す
- 応答 JSON が `ok=true` を含む
- `missing_workflow_names` が空配列である（空にできない場合は理由が `error` に出る）

#### テスト手順（例）
```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
TOKEN="$(terraform output -raw N8N_WORKFLOWS_TOKEN)"
curl -sS -H "Authorization: Bearer ${TOKEN}" \
  "${N8N_BASE_URL%/}/webhook/tests/gitlab/service-catalog-sync?dry_run=true" | jq .
```

---

### OQ: Suluメモリ回帰統合デモ（source: `oq_sulu_memory_regression_demo.md`）

#### 目的

直近デプロイ、同一対象のメモリ高騰2件、OOMを相関し、復旧候補、修正branch/MR/RFC、選択テスト、CI、リスク評価、CMDB／チケット／KEDB連携を1つの応答で追跡できることを確認する。

#### 安全設計

- `POST /webhook/sulu/memory-regression-demo`の既定はdry-runである。
- ライブGitLab書込み、CI、ECR push、ECS変更、状態変更は個別の明示許可を必要とする。
- `gitlab.code_project_path`にはfix branch、commit、MR、Pipelineを作成し、`gitlab.service_project_path`にはRFC、CMDB、Incident/Problem/Change、Known Errorを作成する。ライブ経路では両プロジェクトを分離する。
- CodeBuild実行前に、code projectの修正branchがCodeBuildの参照するソースリポジトリまたはpush mirrorへ到達し、期待するcommit SHAを取得できることを確認する。
- サービス変更にはCAB/eCABの`decision_id`、必須テスト合格、High以外のリスク評価を必要とする。
- セルフテストは固定フィクスチャだけを使用し、外部HTTPを呼ばない。

#### 受入基準

- 4証拠が同一realm・service・image tag、デプロイ後30分以内である。
- `aiops.recovery_candidates.v1`に3候補以上あり、第1候補が旧版へのVersion Deployである。
- code projectのbranch／MR／CIとservice-management projectのRFC、選択テスト、テスト結果、リスクスコアを返す。
- 応答の`artifacts.code_project_path`と`artifacts.service_project_path`が入力した別プロジェクトを示す。
- 4動画に対応する`demo_screens`がすべて`ready`である。
- 別realmのOOM、時間窓外のOOM、`..`を含む修正パス、認証不一致を拒否する。

#### 非破壊テスト

```bash
node apps/workflow_manager/service_request/scripts/tests/test_sulu_memory_regression_demo.mjs
bash apps/aiops_agent/orchestrator/scripts/run_oq_usecase_32_demo_sulu_memory_regression_full_cycle.sh --realm aiops
```

詳細なライブOQと30秒録画手順は`apps/aiops_agent/orchestrator/docs/oq/oq_usecase_32_demo_sulu_memory_regression_full_cycle.md`を正とする。

---

### OQ: Sulu RFC差分分析・修正版ECR push（source: `oq_sulu_rfc_source_analysis.md`）

#### 目的

GitLab Change Issueまたは入力RFCからSuluの修正対象バージョンを抽出し、現行バージョンとの差分と修正ポイントを特定したうえで、対象バージョンのソースと管理済みoverrideからPHP/Nginxイメージを自動生成し、新規タグとしてECRへpushできることを確認する。

#### 安全設計

- RFCは`種別：変更`、RFCラベル、タイトル等で変更要求と確認できることを必須とする。
- `対象サービス=Sulu`と`修正対象バージョン`を必須とする。
- 現行バージョンがRFCにない場合はService Control APIの稼働タグを使用する。
- 既定は`push_images=false`で、差分分析とCodeBuild計画だけを検証する。
- `source_ref`はビルド定義を取得するGit refであり、未指定時は`main`を使う。対象SuluソースはRFCの修正対象バージョンからCodeBuildが自動生成する。
- 実pushには`push_images=true`、`allow_ecr_push=true`、Bearer認証、実在するGitLab Change Issueの承認ラベルと`/approve`相当の承認ノートを必須とする。
- CAB証跡は変更ID、Issue URL、承認者、承認日時、対象タグをHMAC署名し、Service Control APIで再検証する。
- 既存タグは上書きせず、`latest`タグも更新しない。
- PHPとNginxの両イメージが同一の新規タグでECRに存在することを完了条件とする。

#### 受入基準

- `POST /webhook/tests/sulu/rfc-source-analysis`がHTTP 200を返す。
- RFCから比較元3.0.3、比較先3.0.4が抽出される。
- ソース差分と修正候補が返る。
- `image_publish.status=validated`、`dryRun=true`、`applied=false`である。
- dry-runではCodeBuildを開始せず、ECRタグを作成しない。
- 実OQではCodeBuildが成功し、PHP/Nginx双方の新規タグがECRに存在する。

#### 非破壊テスト手順

```bash
REALM="$(terraform output -raw default_realm)"
N8N_BASE_URL="$(terraform output -json n8n_realm_urls | jq -r --arg realm "${REALM}" '.[$realm]')"
TOKEN="$(terraform output -raw N8N_WORKFLOWS_TOKEN)"

curl -sS -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"realm":"aiops","base_version":"3.0.3","target_version":"3.0.4"}' \
  "${N8N_BASE_URL%/}/webhook/tests/sulu/rfc-source-analysis" | jq .
```

#### 実push OQ

承認済みGitLab RFCの作成、異常系、実CodeBuild/ECR push、実ECSデプロイ、明示的なOQ後片付けは次で一括実行し、`summary.json`を生成する。

```bash
apps/workflow_manager/service_request/scripts/run_sulu_release_oq.sh \
  --execute-change \
  --source-version 3.0.4 \
  --source-ref "$(git branch --show-current)"
```

---

### OQ: Service Control（Sulu 制御）（source: `oq_sulu_service_control.md`）

#### 目的
`POST /webhook/sulu/service-control` が `action`/`realm` 等を受け取り、Service Control API 呼び出しが成功して `status=ok` を返すことを確認する。

#### 受け入れ基準
- `POST /webhook/sulu/service-control` が `HTTP 200` を返す
- 応答 JSON が `status=ok` を含む

#### テスト手順（例）
```bash
N8N_BASE_URL="$(terraform output -json service_urls | jq -r '.n8n')"
curl -sS -H 'Content-Type: application/json' \
  -d "{\"action\":\"restart\",\"realm\":\"$(terraform output -raw default_realm)\"}" \
  "${N8N_BASE_URL%/}/webhook/sulu/service-control" | jq .
```

---

### OQ: Suluソースバージョン比較（source: `oq_sulu_source_version_compare.md`）

#### 目的

`POST /webhook/sulu/source-version-compare`が比較元・比較先の明示タグを受け取り、`sulu/skeleton`のソース差分から修正候補と推奨テストを特定することを確認する。

#### 安全設計

- GitHub Compare APIを使用する読み取り専用処理とする。
- `latest`は受け付けず、比較元・比較先の明示タグを必須とする。
- ソース、GitLab、ECR、ECSおよび稼働中のSuluを変更しない。
- GitHub APIが返せる上限に達した場合は`comparison.truncated=true`を返す。

#### 受入基準

- `POST /webhook/tests/sulu/source-version-compare`がHTTP 200を返す。
- 応答が`ok=true`、`status=analyzed`を含む。
- 比較元と比較先が応答に記録され、変更ファイル数が1以上である。
- `findings`に修正候補、影響ファイル、理由、推奨対応、推奨テストが含まれる。

#### テスト手順

```bash
REALM="$(terraform output -raw default_realm)"
N8N_BASE_URL="$(terraform output -json n8n_realm_urls | jq -r --arg realm "${REALM}" '.[$realm]')"
TOKEN="$(terraform output -raw N8N_WORKFLOWS_TOKEN)"

curl -sS -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"base_version":"3.0.3","target_version":"3.0.4"}' \
  "${N8N_BASE_URL%/}/webhook/tests/sulu/source-version-compare" | jq .
```

---

### OQ: Suluバージョン指定デプロイ（source: `oq_sulu_version_deploy.md`）

#### 目的

`POST /webhook/sulu/version-deploy`が明示されたイメージタグを受け取り、Sulu PHP/NginxのECRイメージ存在確認、ECSタスク定義更新計画、実行ガードを正しく処理することを確認する。

#### 安全設計

- 既定は`dry_run=true`で、ECSタスク定義とサービスを変更しない。
- `latest`は受け付けず、明示的なイメージタグを必須とする。
- 実変更には`dry_run=false`と`allow_service_change=true`の両方が必要。
- 本番webhookとService Control APIの双方でBearer認証を必須とする。
- 実変更では、実在するGitLab Change Issueの承認ラベルと承認ノートから生成した署名付きCAB証跡を必須とする。
- 実変更時はSuluが起動中であることを必須とする。
- Sulu PHPとSulu Nginxの両方に指定タグが存在しない場合は失敗する。

#### 受入基準

- `POST /webhook/tests/sulu/version-deploy`がHTTP 200を返す。
- 応答が`ok=true`、`status=validated`、`dry_run=true`、`applied=false`を含む。
- PHPコンテナとNginxコンテナの双方が指定タグへ更新される計画になっている。
- dry-runでは新しいECSタスク定義が登録されず、ECSサービスも更新されない。
- 実OQでは新しいタスク定義が登録され、ロールアウト完了、稼働数、対象タグ、ALBターゲット正常性がすべて確認される。
- ロールアウト失敗、タイムアウトまたはunhealthyターゲットを成功として扱わない。

#### テスト手順

```bash
REALM="$(terraform output -raw default_realm)"
N8N_BASE_URL="$(terraform output -json n8n_realm_urls | jq -r --arg realm "${REALM}" '.[$realm]')"
TOKEN="$(terraform output -raw N8N_WORKFLOWS_TOKEN)"

curl -sS -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d "{\"realm\":\"${REALM}\",\"image_tag\":\"3.0.4\"}" \
  "${N8N_BASE_URL%/}/webhook/tests/sulu/version-deploy" | jq .
```

#### 実デプロイ例

実行前にCAB等の変更承認を取得し、対象realmとタグを確認する。

```bash
curl -sS -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d "{\"realm\":\"${REALM}\",\"image_tag\":\"3.0.4-oq-YYYYMMDD\",\"rfc_issue_url\":\"https://gitlab.example/group/project/-/issues/123\",\"dry_run\":false,\"allow_service_change\":true}" \
  "${N8N_BASE_URL%/}/webhook/sulu/version-deploy" | jq .
```

旧タスク定義への自動ロールバックは今回の実装対象外である。異常時はワークフローを失敗終了し、ECS/ALB状態を証跡へ残す。OQ後の復元は、承認済みRFCを用いた明示的な再デプロイとして実行する。

---

### OQ: ワークフロー同期（n8n Public API upsert）（source: `oq_workflow_sync_deploy.md`）

#### 目的
`apps/workflow_manager/service_request/workflows/` のワークフロー群が n8n Public API へ upsert されることを確認する（dry-run の差分確認も含む）。

#### 受け入れ基準
- `N8N_DRY_RUN=true` で差分（計画）が表示され、API 書き込みなしで終了できる
- 実行時（dry-run なし）に upsert が完了し、必要なワークフローが active になる

#### テスト手順（例）
```bash
# dry-run
N8N_AGENT_REALMS="$(terraform output -raw default_realm)" \
N8N_DRY_RUN=true \
apps/workflow_manager/service_request/scripts/deploy_workflows.sh

# 実行
N8N_AGENT_REALMS="$(terraform output -raw default_realm)" \
apps/workflow_manager/service_request/scripts/deploy_workflows.sh
```


---
<!-- OQ_SCENARIOS_END -->

## 証跡（evidence）

- ワークフロー同期（OQ-WSR-DEP-001）の実行ログ（dry-run の差分、upsert 完了）
- service-catalog-sync テストの応答 JSON（OQ-WSR-EXT-001）
- 代表サービス制御の応答（OQ-WSR-EXT-002）
