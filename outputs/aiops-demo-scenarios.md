# AIOps Agent デモシナリオ

## 1. 目的

本書は、`SMIC_ミニセミナー資料20260716master_updated.pptx` のデモ説明（58、60、64、66、71ページ）を、2本のデモで一巡させるための実演シナリオである。

- インシデント管理
- 複数情報の相関分析
- 復旧策の優先順位付け
- AIOps Agentによる自動判断・自動復旧
- 問題管理
- 変更要求（RFC）の作成
- 影響分析、テスト、リスク評価
- CABによるHuman in the Loop
- GitLab CI/CDによる変更適用
- 構成管理（CMDB）の参照・同期
- インシデント／問題／変更の連鎖クローズ
- KEDBへのナレッジ蓄積
- 判断・承認・実行証跡の保存

デモは、機能別ではなく「AIへ委譲できる判断の範囲」で分ける。

1. **低リスクで可逆的な復旧を、AIOps Agentが自動実行する**
2. **影響の大きい変更は、AIが判断材料を準備し、CABが最終承認する**

## 2. デモ全体のメッセージ

> AIOps Agentは、すべてを無条件に自動化する仕組みではない。根拠、影響範囲、リスク、可逆性を評価し、安全な操作は自動実行し、重要な変更は人の最終判断へつなぐ。

2本は独立したデモとして実施できるが、同じSuluサービスを対象にした「一次復旧」と「恒久対策」の連続した物語として見せると理解されやすい。

## 3. 使用する環境・アプリ

| 役割 | 環境・アプリ | デモでの用途 |
| --- | --- | --- |
| 対象サービス | Sulu | サービス停止、復旧、正常性確認の対象 |
| 監視 | CloudWatch、Grafana | サービス停止、5xx、レイテンシ等の検知・確認 |
| イベント受付 | AIOps Adapter（n8n） | CloudWatch/Zulipイベントの検証、正規化、trace_id付与 |
| 判断 | AIOps Orchestrator（n8n + LLM） | CMDB、Runbook、KEDB等を参照し、次アクションを決定 |
| 実行 | Workflow Manager（n8n） | `wf.sulu_service_control` によるSuluの起動・停止・再起動 |
| 会話・承認 | Zulip | 初動通知、状況報告、承認リンク、`/decision`、`/decisions` |
| コード変更 | GitLab code project | 修正コード、fix branch、MR、GitLab CI/CDの管理 |
| サービス管理 | GitLab service-management project | Incident、Problem、Change/RFC、Known Error、承認・変更履歴の管理 |
| 構成管理 | service-management projectの`cmdb/`、RDS SoR | CI、サービス、Runbook、現行バージョン、外部参照の管理 |
| ナレッジ | Qdrant、AIOps Knowledge Store | 過去事例検索、Known Error、Workaround、解決策の蓄積 |
| 自動構成作業 | Exastro ITA（任意） | CAB承認後の構成適用先として利用可能 |
| 認証 | Keycloak | GitLab、Zulip、Grafana、Sulu等のSSO |
| 証跡 | n8n実行履歴、GitLab、RDS、`evidence/` | trace_idを軸に判断・承認・実行結果を追跡 |

実環境のURLは固定値を手入力せず、Terraform outputを正として確認する。

```bash
terraform output -json service_urls | jq .
terraform output -json n8n_realm_urls | jq .
terraform output -json grafana_realm_urls | jq .
terraform output -raw default_realm
```

## 4. 現在の実装状況

### 4.1 そのまま利用できる機能

- CloudWatch形式イベントの受信、正規化、trace_id付与
- CMDB、Runbook、KEDB/RAGのenrichment
- AIOps Agentによるワークフロー候補と次アクションの判断
- Sulu Service Control
  - workflow ID: `wf.sulu_service_control`
  - action: `up` / `down` / `restart`
- Suluの明示タグデプロイ
  - workflow ID: `wf.sulu_version_deploy`
  - dry-run、実変更ガード、ECS rollout／target health確認
- Suluバージョン間のソース差分分析
  - workflow ID: `wf.sulu_source_version_compare`
  - 変更ファイル、修正候補、推奨テストの分類
- Sulu RFC分析と修正版イメージ作成
  - workflow ID: `wf.sulu_rfc_source_analysis`
  - RFCの対象バージョン抽出、修正済みsource refのCodeBuild、PHP/Nginx ECR push
- 連続メモリイベント、OutOfMemory、直近デプロイの相関分析
- Incident、Emergency Change、Problem、恒久対策Changeの自動生成と相互リンク
- AIOps Agentによる修正ロジック、code project上のfix branch/MR、service-management project上のRFCの自動生成
- 生成コードの自己評価、影響分析、変更内容に応じたテストの自動選択・実行
- テスト結果とCMDB影響範囲を統合し、加減点根拠付きのリスクスコアを作成
- CI結果とリスク評価をRFCへ追記してからCAB証跡を記録
- GitLab commit SHAとCodeBuild参照先／push mirrorのSHA照合
- 実行後のCMDB証跡同期、入力・自動生成チケットの連鎖クローズ、Known Error／KEDB登録
- 自動実行を表す `auto_enqueue`
- 承認が必要な処理を表す `require_approval`
- Zulipの承認リンク、approve/deny
- `/decision` による決定記録と `/decisions` による履歴参照
- AIOps ContextStore、Approval History、Problem Management
- GitLab IssueからRDS SoRへのIncident/Problem/Change等の同期
- GitLabサービス管理プロジェクトのIssueテンプレート、CMDB、Runbook
- code projectとservice-management projectを分離したGitLab書込み・CI経路
- n8n実行履歴と`evidence/`への証跡保存

シナリオ1には、既存のOQと実行スクリプトがある。

- OQ: `apps/aiops_agent/orchestrator/docs/oq/oq_usecase_21_demo_sulu_night_misoperation_autorecovery.md`
- スクリプト: `apps/aiops_agent/orchestrator/scripts/run_oq_usecase_21_demo_sulu_night_misoperation_autorecovery.sh`
- 実行ワークフロー: `apps/workflow_manager/service_request/workflows/aiops_sulu_service_control.json`

### 4.2 シナリオ2の統合実行範囲

シナリオ2は「最新版デプロイ→連続メモリ兆候→OutOfMemory→Emergency rollback→Problem→恒久対策→修正版デプロイ→CMDB/KEDB同期」までを、同一`trace_id`で一巡できる統合シナリオとして実行する。

- 監視イベントと直近デプロイを相関し、Incident、Emergency Change、Problem、恒久対策Changeを自動生成・相互リンクする。
- AIOps Agentが根本原因分析をもとに修正ロジックを生成し、code projectへfix branch/MR、service-management projectへRFCを自動生成する。
- 生成コードを自己評価し、影響CI、過去変更、KEDBを参照して必要なテストを選択・実行する。
- 選択テストとGitLab Pipelineはcode projectで実行し、結果URLとリスクスコアをservice-management projectのRFCへ関連付ける。
- テスト結果、影響範囲、過去障害傾向を統合してリスクを定量評価し、CABへ統合レポートを提示する。
- CAB承認後に修正版イメージを作成・デプロイし、正常性と構成整合性を検証する。
- 検証成功後、CMDBと変更履歴を自動同期し、Problem／Change等の関連レコードを連鎖クローズしてKEDBへ登録する。

ライブデモでは、承認前に副作用のある変更が実行されないこと、各処理が同じ`trace_id`で追跡できること、修正branchがCodeBuildの参照するソースリポジトリ／push mirrorへ到達していること、最終的にサービス状態とCMDBが一致することを合格条件とする。

## 5. 共通のデモ設計

### 5.1 役割

| 役割 | 担当 |
| --- | --- |
| デモ進行 | 画面切り替え、状況説明、コマンド実行 |
| 運用担当 | Zulipで状況確認。シナリオ1では原則操作しない |
| CAB承認者 | シナリオ2で変更内容をレビューし、承認リンクを操作 |
| 監視担当 | Grafana/CloudWatchで異常と復旧を確認 |

### 5.2 共通の相関ID

すべての画面で同一の`trace_id`または`correlation_id`を見せる。

- CloudWatchイベント
- AIOps ContextStore
- n8n実行履歴
- Zulipトピック
- GitLab Issue/MR
- RDS SoRのaudit event/approval
- `evidence/`の実行結果

観客に「複数ツールを使っているが、1件の事象として追跡できる」ことを伝える。

### 5.3 自動実行と人承認の境界

| 条件 | 判断 |
| --- | --- |
| Runbookがあり、操作が既知・可逆・サービス単位 | 自動実行候補 |
| 監視イベントとワークフローカタログが一致 | 自動実行候補 |
| Service Windowが24x7で、計画停止ではない | 自動実行候補 |
| 入力と対象realmが確定し、confidenceが基準以上 | 自動実行候補 |
| 高リスク、インフラ／テナント全体への影響 | CAB承認 |
| セキュリティ、データ、不可逆変更を伴う | CAB承認 |
| Runbook不足、CMDB不整合、曖昧性が高い | 追加質問または手動トリアージ |

現在の標準ポリシーは、`risk_level=high`、`impact_scope=infra|tenant`等を承認対象とする。詳細は次を正とする。

- `apps/aiops_agent/orchestrator/data/default/policy/approval_policy_ja.json`
- `apps/aiops_agent/orchestrator/data/default/policy/decision_policy_ja.json`

## 6. 共通事前準備

### 6.1 安全条件

- 本番利用中のrealmではなく、デモ用realmを使用する。
- Sulu停止を伴うため、利用者と実施時間を事前確認する。
- コントロールサイトの自動起動スケジュールとデモ時間が競合しないことを確認する。
- GitLabのcode projectとservice-management projectを明示し、デモ用branch／Issueだけを使用して通常運用の`main`へ誤マージしない。
- Terraform stateや`*.tfvars`、APIキー、Webhook tokenを投影しない。
- n8n実行データを見せる場合は、token、cookie、authorization等をマスクした証跡を使う。
- 復旧不能に備え、コントロールサイトからSuluを手動起動できることを確認する。

### 6.2 サービス起動

1. AWS SSOへログインする。

   ```bash
   aws sso login --profile "$(terraform output -raw aws_profile)"
   ```

2. コントロールサイトで次を起動する。

   - Keycloak
   - Zulip
   - n8n
   - GitLab
   - Grafana
   - Sulu
   - Exastro ITA（シナリオ2で使う場合）

3. Terraform outputで各URLを確認する。
4. Suluへアクセスし、開始時点で正常表示されることを確認する。
5. GrafanaのSulu関連ダッシュボードを開く。
6. Zulipの`#itsm-incident` / topic `sulu`を開く。
7. GitLabのcode projectとservice-management projectを別タブで開く。
8. n8nでAIOps AgentとWorkflow Managerの対象ワークフローがActiveであることを確認する。

### 6.3 シナリオ1の事前リハーサル

既存スクリプトをdry-runする。dry-runではHTTPリクエストは送信しない。

```bash
bash apps/aiops_agent/orchestrator/scripts/run_oq_usecase_21_demo_sulu_night_misoperation_autorecovery.sh
```

次を確認する。

- realmが解決できる
- n8n URLが解決できる
- 必須コマンドが存在する
- 秘密情報がログに表示されない

## 7. シナリオ1：夜間のSulu誤停止をAIOps Agentが自動復旧

### 7.1 狙い

低リスクで可逆的な既知操作について、AIOps Agentが根拠を確認し、人の承認待ちをせずに復旧できることを示す。

### 7.2 物語

夜間メンテナンス中、運用担当者が対象サービスを取り違え、24x7で稼働すべきSuluを停止してしまう。CloudWatchがサービス停止を検知する。AIOps Agentは、操作ログ、CMDB、Service Window、Runbook、過去事例を参照し、計画停止ではなく誤操作の可能性が高いと判断する。再起動は既知・可逆・サービス単位の操作であるため、自動実行し、復旧結果と判断証跡を記録する。

### 7.3 前提データ

GitLabのSulu CMDB/Runbookに次が記載されていること。

- サービス: Sulu
- 環境: デモ環境
- 重要度: 高
- Service Window: 24x7
- 自動復旧: 可
- 誤停止・一時停止の場合は再起動を優先
- Runbook: Sulu Service Down時は`wf.sulu_service_control`を`action=restart`で実行

### 7.4 実演手順

| No. | 実演者の操作 | 画面 | システムの期待動作 | 説明ポイント |
| ---: | --- | --- | --- | --- |
| 1 | Suluの正常画面とGrafanaを表示 | Sulu / Grafana | サービス正常 | 「最初は正常です」 |
| 2 | デモ用realmのSuluを停止 | コントロールサイト、またはSulu Service Control | Suluが停止 | 人為ミスを再現。共有環境では必ず事前合意する |
| 3 | CloudWatch Alarm相当イベントを投入 | ターミナル | `source=cloudwatch`でイベント受信 | 実アラームを待たず、再現可能な入力を使用 |
| 4 | AIOps Contextを表示 | n8n / DB証跡 | trace_id、alarmName、対象サービスを保存 | 署名・正規化・冪等化も裏側で実施 |
| 5 | enrichment結果を表示 | n8n実行履歴 | CMDB、Runbook、操作ログ、KEDBを参照 | AIが監視メッセージだけで判断していないことを見せる |
| 6 | jobs/previewを表示 | n8n実行履歴 | `wf.sulu_service_control`、`action=restart`を選択 | 原因候補と復旧策を根拠付きで決定 |
| 7 | 自動実行決定を表示 | Zulip | `auto_enqueue`が`/decision`として投稿 | 人が承認したように装わず「AIOpsAgent 自動承認」と記録 |
| 8 | Workflow Manager実行を表示 | n8n | Sulu Service Controlがrestartを実行 | 判断系と実行系を分離していることを説明 |
| 9 | SuluとGrafanaを再表示 | Sulu / Grafana | HTTP応答と監視が正常化 | 実行成功ではなく、サービス正常化を復旧完了条件にする |
| 10 | 通知と履歴を表示 | Zulip | 復旧完了、trace_id、job_idを通知 | `/decisions`で自動判断履歴を表示 |
| 11 | チケット・証跡を表示 | GitLab / RDS / evidence | Incident、判断、実行結果を追跡可能 | 後から「なぜ自動実行したか」を説明できる |

### 7.5 実行コマンド

既存OQスクリプトはCloudWatchイベントを投入し、AIOps Orchestratorの実行に`wf.sulu_service_control`と`restart`が含まれることを確認する。

```bash
run_id="demo-s1-$(date +%Y%m%d-%H%M%S)"

bash apps/aiops_agent/orchestrator/scripts/run_oq_usecase_21_demo_sulu_night_misoperation_autorecovery.sh \
  --execute \
  --evidence-dir "evidence/demo/${run_id}"
```

注意事項:

- このスクリプトの合格条件は、主にOrchestratorが`wf.sulu_service_control`と`restart`を選択したことの確認である。
- Suluが実際に正常化したことは、SuluのHTTP応答、Grafana/CloudWatch、Workflow Managerの実行結果で別途確認する。
- `evidence/`へ保存されるn8n実行データはスクリプト内で機微情報をマスクする。

### 7.6 見せるべき判断根拠

最低限、次の4点を同じ画面または短い順番で見せる。

1. CloudWatchのサービス停止アラーム
2. 直近操作が手動停止であること
3. CMDBの24x7／自動復旧可
4. Runbookの再起動手順

KEDBに過去の同一事例を登録しておける場合は、5点目として「過去にも再起動で復旧した」を表示する。

### 7.7 復旧完了条件

- SuluのHTTP応答が正常
- Grafana/CloudWatchの停止アラームが解消
- Workflow Managerの実行が成功
- Zulipへ復旧完了通知
- 自動判断が`/decision`として記録
- trace_idでn8n、Zulip、GitLab、RDS、evidenceを関連付け可能

### 7.8 異常系の説明

時間に余裕があれば、実行はせず口頭または事前キャプチャで次を示す。

- CMDBが計画停止を示す場合は自動再起動しない
- Runbookが「要承認」の場合は`require_approval`へ進む
- realmが不明、confidence不足の場合は追加質問または手動トリアージ
- Service Controlが失敗した場合はオンコールへエスカレーション

## 8. シナリオ2：Sulu更新後のメモリ障害を検知し、承認付きロールバックと恒久対策へつなぐ

### 8.1 狙い

Suluのバージョン更新後にメモリ逼迫とOutOfMemoryが発生した状況を再現し、AIOps Agentが直近変更、連続した監視兆候、CMDB、Runbookを相関して原因候補を提示する。サービス復旧はEmergency Changeとして人の承認後に旧バージョンへロールバックする。復旧後はProblem Managementで原因を調査し、修正ロジック、MR、RFC、テスト、リスク評価を自動生成する。CAB承認後に修正版をデプロイし、CMDB同期、関連プロセスのクローズ、KEDB登録まで完了する。

ITIL 4上の主な流れは次のとおりとする。

1. **Change Enablement**: 最新版への更新をNormal Changeとして評価・承認・実施する。
2. **Monitoring and Event Management**: メモリ逼迫の連続イベントとOutOfMemoryを受信・相関する。
3. **Incident Management**: ユーザー影響の早期復旧を最優先し、旧版への切戻しを提案する。
4. **Emergency Change**: CMDBのサービスオーナーまたは変更権限者がロールバックを承認する。
5. **Problem Management**: 復旧後もProblemをオープンのまま維持し、根本原因と恒久対策を調査する。
6. **Change Enablement**: 修正版を新規タグで作成し、別のNormal Changeとして評価・承認・再デプロイ・検証する。
7. **Configuration Management / Knowledge Management**: 検証済みの実態をCMDBへ同期し、関連プロセスを連鎖クローズしてKEDBへ登録する。

### 8.2 バージョンと成果物の定義

デモ開始時に可変な`latest`タグを使わず、次の明示タグを記録する。

| 識別子 | 意味 | 例 |
| --- | --- | --- |
| `V_PREVIOUS` | 最新版の一つ前で、開始時に稼働中の既知正常版 | `3.0.3` |
| `V_LATEST` | デモ開始時点で確認した上流最新版 | `3.0.4` |
| `V_FIXED` | `V_LATEST`をベースに修正した社内ビルドの新規・不変タグ | `3.0.4-smic.1` |

「最新版」はデモ実行日にGitHub/ECRで再確認する。`V_FIXED`は上流に存在しないバージョンを装わず、「3.0.4をベースにした修正版成果物」と説明する。既存タグは上書きせず、RFCビルドではECRの`latest`タグも変更しない。

### 8.3 前提条件

- Suluが`V_PREVIOUS`で稼働し、ECSが`desiredCount>=1`、`runningCount>=1`、外形HTTPが2xxである。
- ECRのSulu PHP/Nginx両リポジトリに`V_PREVIOUS`と`V_LATEST`が存在する。
- CMDBにSuluのサービスオーナー、変更承認者、関連CI、Runbook、現行バージョンを登録している。
- `wf.sulu_version_deploy`、`wf.sulu_source_version_compare`、`wf.sulu_rfc_source_analysis`がActiveである。
- 最新版デプロイChange、Emergency rollback Change、Incident、Problem、恒久対策Changeを同一`trace_id`で関連付けられる。
- ダミーCloudWatchイベントはすべて異なる`event_id`を持ち、同じrealm、ECS service、task definition、image tag、deployment/change IDを含む。

### 8.4 推奨プロセス

#### フェーズA：最新版デプロイ（Normal Change）

1. Suluが`V_PREVIOUS`で正常稼働していることを確認する。
2. チャットで「Suluを`V_LATEST`へ更新したい」と要求する。
3. AIOps Agentは単なる再起動指示として扱わず、最新版デプロイChangeを作成または参照し、対象realm、現在値、目標タグ、影響CI、テスト、ロールバック先`V_PREVIOUS`を提示する。
4. 高リスク変更として`next_action=require_approval`を返し、CAB承認用トークンを発行する。
5. CAB承認後、承認者、承認時刻、理由、`trace_id`をApproval History／監査イベントへ保存する。
6. 承認済みジョブとして`wf.sulu_version_deploy`を`image_tag=V_LATEST`、`dry_run=false`、`allow_service_change=true`で実行する。
7. ECSローリング更新の完了、PHP/Nginxの明示タグ、`desiredCount>=1`、`runningCount>=1`、ALB target正常、外形HTTP 2xxを確認する。
8. Change IssueとCMDBの実行履歴へ結果を追記し、Zulipへ通知する。

#### フェーズB：監視兆候とIncident検知

1. デプロイ完了時刻より後に、メモリ利用率90%以上を示すダミーCloudWatchイベントを2回、1分間隔で投入する。
2. 2イベントは「同じ障害の継続」を表すが、冪等化で片方が消えないよう異なる`event_id`を使用する。
3. 続けて`V_LATEST`のSulu taskでOutOfMemoryが発生したことを示すダミーイベントを投入する。
4. AIOps Adapterはイベントを正規化し、`trace_id`、realm、service、task definition、image tag、発生時刻を保存する。
5. AIOps Agentは次の根拠を相関する。
   - 直近の承認済みデプロイが`V_PREVIOUS → V_LATEST`である。
   - デプロイ後にメモリ90%以上が一定時間継続した。
   - 同じservice/image tagでOutOfMemoryが発生した。
   - CMDB／Runbookにロールバック先とサービスオーナーがある。
6. Agentは「`V_LATEST`の更新に起因するメモリ回帰」を有力な原因候補として提示する。ただし事実確定ではなく、根拠、反証条件、confidenceをIncidentへ記録する。
7. ユーザー影響が発生した時点でIncident Issueを作成し、Problem調査より先に復旧へ進む。

#### フェーズC：承認付きロールバック（Emergency Change）

1. IncidentにリンクしたEmergency Changeを作成し、次を記載する。
   - 原因仮説と監視時系列
   - ロールバック先`V_PREVIOUS`
   - 影響CIとサービス影響
   - ECSローリング更新、HTTP smoke、メモリ監視のテスト
   - ロールバック失敗時の手動復旧／エスカレーション
2. CMDBに登録されたサービスオーナー／変更権限者へZulipで承認を依頼する。
3. Agentは`wf.sulu_version_deploy`を高リスク操作として`next_action=require_approval`にし、承認トークンを発行する。
4. 管理者はチャットのapprove操作で承認する。承認者、時刻、判断理由、対象タグ、`trace_id`を記録する。
5. CAB/eCAB承認後、ジョブエンジンまたは承認済み専用呼び出しから`wf.sulu_version_deploy`を`image_tag=V_PREVIOUS`で実行する。
6. Suluを事前停止しない。現行ワークフローは稼働中サービスのECSローリング更新を前提とし、停止中のバージョン変更を拒否する。
7. ECS rollout完了、PHP/Nginxの`V_PREVIOUS`、running count、target health、HTTP 2xx、メモリ正常化を確認する。
8. Zulipへ復旧結果、リスク、影響CI、テスト、ロールバック計画、Incident／Emergency Change URLを通知する。
9. Incidentはサービス復旧、監視正常化、利用者確認後にResolvedからClosedへ進める。Emergency Changeも実行証跡を追記してレビュー後にクローズする。

#### フェーズD：Problem Managementと根本原因分析

1. IncidentにリンクしたProblem Issueをオープンし、Incidentを閉じてもProblemは閉じない。
2. `wf.sulu_source_version_compare`を`base_version=V_PREVIOUS`、`target_version=V_LATEST`で実行する。
3. 変更ファイル、依存関係、設定、管理画面資産、削除／改名、推奨テストをProblem Issueへ追記する。
4. メモリ増加と直接関係するコード／依存変更は、アプリログ、メモリメトリクス、再現テストで追加検証する。ソース差分だけで根本原因を断定しない。
5. 調査結果がアプリ修正を必要とする場合、Known Error／回避策として「`V_PREVIOUS`へ維持」を記録し、恒久対策Changeへ進む。

#### フェーズE：RFC、修正版イメージ、再デプロイ

1. service-management projectに、リスク、影響CI、テスト内容、ロールバック計画、Incident／Problemリンクを含む恒久対策Change/RFC Issueを作成する。
2. AIOps Agentが根本原因、KEDB、ソース差分をもとに修正ロジックを生成し、code projectにfix branchとMRを自動作成する。
3. Agentが生成コードを自己評価し、影響分析、潜在リスク検出、変更内容に応じたテスト選択を行う。
4. code projectのGitLab CI/CDで選択したテストを自動実行し、結果、品質、影響CIを統合してリスクスコアを算出する。
5. service-management projectのRFCへ、対象サービス、現行／修正対象バージョン、code projectのMR/source ref、Pipeline URL、影響、テスト、リスク、ロールバック計画を記録する。
6. `wf.sulu_rfc_source_analysis`でRFC内容と差分を検証し、CABへ統合レポートと承認リンクを提示する。
7. code projectの修正branchがCodeBuildの参照するソースリポジトリまたはpush mirrorへ到達し、同一commit SHAを参照できることを確認する。未到達の場合はECR pushへ進まない。
8. CAB承認済みの`source_ref`に対して、`push_images=true`、`allow_ecr_push=true`を指定してCodeBuild経路を実行する。
9. Sulu PHP/Nginxの両リポジトリに`V_FIXED`が存在し、既存タグと`latest`が上書きされていないことを確認する。
10. 承認済みNormal Changeとして`wf.sulu_version_deploy`を実行し、`V_FIXED`をECSへローリングデプロイする。
11. rollout、target health、HTTP 2xx、メモリ正常化、回帰テストを確認し、service-management projectのCMDB、CI状態、変更履歴を自動同期する。
12. 修正版の有効性を確認した後、service-management projectのProblem／恒久対策Change／RFCを連鎖クローズし、Known Errorを作成してKEDBへ登録する。
13. このシナリオの終点は「`V_FIXED`のデプロイ完了、CMDB同期、関連プロセスのクローズ、KEDB登録完了」とする。

### 8.5 ワークフローと合格条件

| 目的 | 使用ワークフロー | 非破壊OQ | フルOQ／実行時 |
| --- | --- | --- | --- |
| 最新版デプロイ／旧版ロールバック | `wf.sulu_version_deploy` | `status=validated`, `dry_run=true`, `applied=false` | `dry_run=false`, `allow_service_change=true`、ECS rollout/HTTP確認 |
| バージョン差分調査 | `wf.sulu_source_version_compare` | `status=analyzed`、変更ファイルと`findings`を確認 | 読み取り専用 |
| RFC分析・修正版ECR push | `wf.sulu_rfc_source_analysis` | `status=analyzed_from_rfc`, `image_publish.status=validated`, `dryRun=true`, `applied=false` | 明示承認後に新規タグをPHP/Nginxへpush |
| 修正ロジック／MR／RFC生成 | AIOps Agent、GitLab | code projectの一時branch/MRとservice-management projectのRFCを検証 | 2プロジェクトへ役割別に自動作成 |
| テスト最適化・リスク評価 | AIOps Agent、code projectのGitLab CI/CD、RDS SoR | テスト計画とリスクスコアを検証 | code projectで選択テストを実行し、RFCへ結果を統合 |
| CMDB同期・連鎖クローズ・KEDB登録 | AIOps Problem Management、service-management project、RDS SoR、Qdrant | 更新予定レコードを検証 | 正常性確認後にservice-management projectで同期・クローズ・登録 |
| 構成誤設定の復旧 | `wf.sulu_configuration_recovery` | `status=validated`, `dry_run=true`, `simulated=true`, `applied=false` | `desired_state`誤設定の復旧に限定 |

`simulated=true`は`wf.sulu_configuration_recovery`固有であり、バージョンデプロイ／ロールバックの合格条件には使用しない。

### 8.6 AIOps Agent承認シーケンス

高リスクの最新版デプロイ、Emergency rollback、修正版ECR push、修正版デプロイは、次の共通シーケンスを使う。

1. AIOps Agentへ対象workflow IDと明示パラメータを渡す。
2. Agentが`next_action=require_approval`を返す。
3. AgentがCAB/eCAB承認用トークンを発行する。
4. 管理者がZulipのapprove/denyで判断する。
5. 承認者、承認時刻、判断理由、workflow ID、対象タグ、`trace_id`をApproval History／audit eventへ保存する。
6. 承認後のみジョブを投入する。
7. 実行結果をZulipとGitLab Change Issueへ追記する。

ジョブエンジンは`wf.sulu_service_control`、`wf.sulu_configuration_recovery`、`wf.sulu_version_deploy`、`wf.sulu_rfc_source_analysis`を承認状態とともにdispatchする。各処理は同じ`trace_id`を引き継ぎ、承認前の変更実行を拒否する。

### 8.7 OQ実行モード

#### デフォルトの非破壊OQ

- 実際のSuluタグ、ECS service、ECRを変更しない。
- CloudWatchイベントはダミーpayloadを使用する。
- 最新版デプロイとロールバックは`wf.sulu_version_deploy`のdry-runで計画を確認する。
- RFCビルドはCodeBuildを開始せず、push計画と既存タグ判定だけを確認する。
- code projectのOQ専用MR／branchとservice-management projectのOQ専用Issueを区別し、それぞれ最後に削除する。

#### フルOQ

- 対象realm、`V_PREVIOUS`、`V_LATEST`、ロールバック許可を明示確認する。
- Suluを停止せず、承認後に`V_LATEST → V_PREVIOUS`のECSローリング更新を実行する。
- `desiredCount>=1`、`runningCount>=1`、rollout完了、target health正常、HTTP 2xxを確認する。
- 根本原因分析、修正ロジック／MR／RFC生成、テスト最適化、リスク評価を連続実行する。
- code projectの修正branchがCodeBuildソースリポジトリ／push mirrorへ到達し、commit SHAが一致することを確認する。
- 未使用の`V_FIXED`とCAB承認を確認して修正版をECRへpushし、ECSへデプロイする。
- デプロイ後の正常性と構成整合性を検証し、CMDB同期、関連プロセスの連鎖クローズ、KEDB登録まで確認する。
- 途中失敗時は追加の自動変更を停止し、現行稼働タグとHTTP状態を確認してオンコールへエスカレーションする。

### 8.8 Issue／MRのライフサイクル

- Incident: サービス復旧後、監視正常化と利用者確認を経てクローズする。
- Emergency Change: ロールバック結果と事後レビューを追記してクローズする。
- Problem: 根本原因と`V_FIXED`の有効性が確認されるまでオープンを維持し、確認後に自動クローズする。
- 恒久対策Change/RFC: `V_FIXED`の承認、デプロイ、PIR完了後に自動クローズする。
- code projectのfix MRは自己評価とCIテスト合格後にCAB判断へ進み、service-management projectのRFC承認後にmergeする。
- 最終検証を起点に、CMDB、Incident、Problem、Change、KEDBの状態を同一`trace_id`で連鎖更新する。
- OQ専用の一時MR／Issue／branchだけをOQ終了時にクリーンアップする。

### 8.9 現行実装とデモ上の扱い

| 項目 | 現行状態 | デモでの扱い |
| --- | --- | --- |
| 明示タグのSuluデプロイ | 実装済み | `wf.sulu_version_deploy`を使用 |
| バージョン間ソース比較 | 実装済み | `wf.sulu_source_version_compare`を使用 |
| RFC解析と新規ECRタグ作成 | 実装済み | `wf.sulu_rfc_source_analysis`を使用 |
| ソースコード自動修正 | 実装済み | 根本原因をもとに修正ロジック、fix branch/MRを自動生成 |
| GitLabプロジェクト責務分離 | 実装済み | code projectへbranch/MR/CI、service-management projectへRFC/CMDB/チケット/Known Errorを書込む |
| CodeBuildソース到達確認 | 実装済み | GitLab commit SHAとCodeBuild参照先／push mirrorのSHAを自動照合し、一致した場合だけECR pushへ進む |
| テスト最適化・リスク評価 | 実装済み | 自己評価、影響分析、選択テスト、リスクスコアをCAB資料へ統合 |
| 連続メモリイベント＋OOM＋直近デプロイの専用相関OQ | 実装済み | 同一`trace_id`で統合シナリオを実行 |
| Incident／Problem／Change／CMDB／KEDBの完全連鎖更新 | 実装済み | 最終検証後に自動同期・クローズ・登録 |
| Agentキューから新規workflowへのdispatch | 実装済み | 承認状態を検証し、同一`trace_id`でWorkflow Managerへdispatch |

統合シナリオ2の正本は次のとおり。

- workflow: `wf.sulu_memory_regression_demo`
- webhook: `POST /webhook/sulu/memory-regression-demo`
- OQ: `apps/aiops_agent/orchestrator/docs/oq/oq_usecase_32_demo_sulu_memory_regression_full_cycle.md`
- 実行スクリプト: `apps/aiops_agent/orchestrator/scripts/run_oq_usecase_32_demo_sulu_memory_regression_full_cycle.sh`
- 固定フィクスチャ: `apps/aiops_agent/orchestrator/scripts/tests/fixtures/sulu_memory_regression_full_cycle.json`
- 復旧候補Schema: `apps/workflow_manager/service_request/schemas/aiops.recovery_candidates.v1.schema.json`

#### 8.9.1 4画面の30秒録画

全動画で同じ`trace_id`を表示し、固定フィクスチャの`V_PREVIOUS=3.0.3`、`V_LATEST=3.0.4`、`V_FIXED=3.0.4-smic.1`を使う。秒単位の操作表はOQ-USECASE-32を正とする。

| 動画 | PPTX | 0〜10秒 | 10〜20秒 | 20〜30秒 |
| --- | ---: | --- | --- | --- |
| 相関分析 | 58 | メモリ92%・94%・OOM | 直近Deployとの4証拠 | confidenceとtrace_id |
| 復旧候補 | 60 | 障害要約 | 順位・根拠・risk | 1位選択とCABリンク |
| 変更・影響 | 64 | branch/MR | 修正コードと選択テスト | CI・RFC・risk score |
| CMDB/KEDB | 71 | 修正版の正常化 | CMDBとチケットClosed | Known Error・同期結果 |

66ページのCAB承認画面は、既存OQ-31の承認リンク、`/decision`、Approval Historyを流用する。

### 8.10 既存OQ-31（構成誤設定復旧）の位置付け

以下の既存OQ-31は`desired_state: down`というGitLab構成誤設定を対象とする別テストであり、本節のバージョン回帰／OutOfMemoryシナリオを直接検証するものではない。構成変更の相関、CAB承認、証跡保存、EXITガードの再利用可能な参考実装として残す。

#### 8.10.1 狙い

サービス障害の原因がGitLab管理の構成変更にある場合、AIOps Agentが差分、影響範囲、テスト、リスク、ロールバックを整理し、人が最終判断した後に変更を適用できることを示す。

#### 8.10.2 推奨するデモ用障害

デモ用GitLabプロジェクトに、Suluの運用状態を表す次のような構成ファイルを用意する。

```yaml
service: sulu
realm: demo
desired_state: up
auto_recovery: true
run_window: 24x7
```

誤変更として`desired_state: down`をマージし、デモ用GitLab PipelineまたはExastro MovementがSulu Service Controlを呼び出してSuluを停止する。

```diff
- desired_state: up
+ desired_state: down
```

この構成にすると、次の因果関係を観客に明確に示せる。

> GitLabの構成変更 → CI/CDまたはExastroによる反映 → Sulu停止 → CloudWatch異常 → AIOps Agentが直前差分を原因候補として特定

本番Terraformや通常運用のサービス制御設定を変更せず、デモ用プロジェクト／デモ用realmでのみ実施する。

#### 8.10.3 シナリオ2用デモフィクスチャ

完全なライブデモには、次を事前準備する。

1. **GitLab構成リポジトリ**
   - `demo/sulu-runtime.yml`
   - `desired_state`の変更履歴が分かること
2. **GitLab CI/CD**
   - validate: YAML、realm、許可値の検証
   - impact: CMDBから影響CI／サービスを取得
   - test: デモ環境で適用前テスト
   - deploy: protected environment + manual job
   - verify: SuluのHTTP/監視を確認
   - rollback: 直前値へ戻すmanual job
3. **Change Issue/RFCテンプレート**
   - 目的、差分、影響、テスト、リスク、実施時間、ロールバック、承認者
4. **AIOps Agent連携**
   - CloudWatchイベントから直近GitLab commit/MRをenrichment
   - 修正MRとChange Issueを作成または既存テンプレートから生成
   - `risk_level=high`または`impact_scope=infra`として`require_approval`へ分岐
5. **承認導線**
   - Zulipのapprove/denyリンク
   - 承認結果を`/decision`、GitLab Issue、RDS SoRへ保存

##### 8.10.3.1 実装済みの非破壊OQ／フルOQ

シナリオ2の安全なリハーサルとして、次を実装済みである。

- OQ仕様: `apps/aiops_agent/orchestrator/docs/oq/oq_usecase_31_demo_gitlab_misconfiguration_cab_recovery.md`
- 実行スクリプト: `apps/aiops_agent/orchestrator/scripts/run_oq_usecase_31_demo_gitlab_misconfiguration_cab_recovery.sh`
- 復旧ワークフロー: `wf.sulu_configuration_recovery`
- セルフテスト: `Test Sulu Configuration Recovery`

非破壊OQは、GitLabの既定ブランチを変更せず、OQ専用ブランチ間の修正MR、Change Issue、Agent承認要求、CAB承認、dry-run復旧、検証、Issue/MRクローズを実行する。2026-07-16の実行では `trace_id=9d4ddb0b-d8ee-4ddd-9555-0caa987866c0` で合格し、証跡を `outputs/oq/usecase-31-20260716-145836/` に保存した。

フルOQは `--full-oq --confirm-service-stop aiops` を明示した場合のみ、実際にSuluを停止する。CloudWatchイベント時刻を起点にGitLab全refの対象ファイル差分を自動検索し、CAB承認後に復旧し、ECSのrunning countと外形HTTPまで確認する。途中失敗時もEXITガードがSulu起動と一時GitLab資材のクリーンアップを行う。

2026-07-16のフルOQは `trace_id=4df35d54-d0ec-4ee4-8937-ce859a702d66` で合格し、証跡を `outputs/oq/usecase-31-full-pass-20260716-155658/` に保存した。承認後Zulip通知も成功した。

Exastro ITAについては、復旧ワークフローにConductor API実行経路を追加済みである。ただし現環境は `ita-api-organization`、Conductor同期ワーカー、Ansible実行ワーカーが未配備であるため、今回の合格実行はService Controlバックエンドを使用した。これらのExastro実行コンポーネントとorganization/workspace、Conductor、Operation、Movementを配備した後に `EXASTRO_ITA_DEFAULT_BACKEND=exastro` を有効化する。

#### 8.10.4 物語

担当者がGitLab上のSulu構成を誤って`desired_state: down`へ変更し、CI/CDがデモ環境へ反映する。Suluが停止し、CloudWatchが異常を検知する。AIOps Agentは、監視情報、操作履歴、GitLab差分、CMDB、サービスマップ、Runbook、過去事例を分析し、直前の構成変更を原因候補として特定する。

Agentは`desired_state: up`へ戻す修正MRとChange Issueを準備し、必要なテストを実行する。対象が本番相当の構成変更であるため、自動適用せずCABへ統合レポートを提示する。CABが承認すると、GitLab CI/CDまたはExastroが修正を適用し、Agentがサービス正常性と構成整合性を確認する。最後にCMDB、Incident、Problem、Change、KEDBを更新する。

#### 8.10.5 実演手順

| No. | 実演者の操作 | 画面 | システムの期待動作 | 説明ポイント |
| ---: | --- | --- | --- | --- |
| 1 | 正常な構成とSuluを表示 | GitLab / Sulu / Grafana | `desired_state=up`、サービス正常 | 構成と実態が一致 |
| 2 | 誤変更MRをマージ | GitLab | Pipelineがデモ環境へ`down`を反映 | GitLabが変更・証跡の起点 |
| 3 | Sulu停止を確認 | Sulu / Grafana | Service Down、アラーム発生 | 構成変更と障害の時系列を明確にする |
| 4 | AIOps Agentの相関分析を表示 | n8n | 監視、ログ、GitLab差分、CMDB、KEDBを統合 | 「直前変更」を経験ではなくデータで特定 |
| 5 | 影響分析を表示 | GitLab Change Issue / CMDB | 影響CI、依存サービス、ユーザー影響を表示 | サービスマップとCMDBを判断に使う |
| 6 | 修正案を表示 | GitLab MR | `desired_state=up`、再発防止validationを提案 | 修正だけでなく再発防止も含める |
| 7 | RFCを表示 | GitLab Change Issue | 目的、差分、影響、テスト、リスク、ロールバックを記録 | 変更要求を自動で準備 |
| 8 | テストを表示 | GitLab Pipeline | validate、smoke、回帰、セキュリティ等を実行 | 影響に必要なテストだけ選ぶ |
| 9 | リスク評価を表示 | Change Issue / Zulip | risk、残存リスク、推奨条件を提示 | AIは判断材料を統合する |
| 10 | CAB資料を表示 | Zulip / GitLab | approve/denyリンクを提示 | AIは最終承認者を置き換えない |
| 11 | CAB担当者が承認 | Zulip | `/decision`投稿、Approval History/SoR更新 | 誰が・いつ・何を承認したかを記録 |
| 12 | 修正を適用 | GitLab CI/CD / Exastro | protected deployを実行 | 承認前には副作用のある変更を行わない |
| 13 | 正常性と整合性を確認 | Sulu / Grafana / GitLab CMDB | サービス正常、構成と実態が一致 | 実行成功ではなく結果を検証 |
| 14 | 関連プロセスをクローズ | GitLab / RDS | Incident、Problem、Changeを連鎖更新 | 複雑なステータス同期を自動化 |
| 15 | KEDBを表示 | Qdrant / GitLab Issue | 原因、兆候、解決策、再発防止策を登録 | 次回は自動復旧または判断高速化に使える |

#### 8.10.6 CABへ提示する統合レポート

デモでは、CAB画面に最低限次を表示する。

| 項目 | 内容例 |
| --- | --- |
| 事象 | Sulu Service Down |
| 原因候補 | 直前MRで`desired_state: up`から`down`へ変更 |
| Agent確信度 | 高。変更時刻とアラーム発生時刻が一致 |
| 影響サービス | Sulu、認証後のコンテンツ閲覧 |
| 影響CI | Sulu ECS Service、ALB target、関連監視CI |
| 修正 | `desired_state: up`へ戻し、禁止値検証を追加 |
| テスト | YAML validation、dry-run、Sulu HTTP smoke、監視確認 |
| リスク | 本番相当のサービス制御変更のためHigh |
| 残存リスク | 起動失敗、依存サービス未起動、監視反映遅延 |
| ロールバック | 修正MRをrevertし、コントロールサイトから手動復旧 |
| Agent推奨 | 条件付き承認。監視担当立会い、適用後5分監視 |

#### 8.10.7 Zulipでの承認例

AIOps Agentの承認リンクを使う。承認後、同一トピックへ次の趣旨の決定ログが残ることを確認する。

```text
/decision CAB承認: Sulu構成修正を実施する
- 対象: demo realm / Sulu
- Change: CHG-xxxx
- MR: !xx
- 条件: 適用後5分間の監視、異常時は即時ロールバック
- correlation_id: <trace_id>
```

承認履歴はZulipで次を投稿して確認する。

```text
/decisions
```

#### 8.10.8 復旧完了条件

- CAB承認前に本番相当の修正が適用されていない
- 承認者、承認時刻、判断理由、correlation_idが記録されている
- GitLab PipelineまたはExastroの適用が成功
- SuluのHTTP応答が正常
- Grafana/CloudWatchの異常が解消
- GitLab構成と実態が一致
- CMDBの状態・変更履歴が更新
- Incident、Problem、Changeが適切な状態へ更新
- 原因、修正、再発防止策がKEDBへ登録

#### 8.10.9 ライブ実演失敗時の証跡フォールバック

ライブ環境の一時的な障害に備え、統合シナリオの成功証跡を事前に用意する。

1. イベント相関、修正ロジック／MR／RFC生成、テスト、リスク評価のn8n実行証跡を保存する。
2. CAB承認、GitLab CI/CD、修正版デプロイ、CMDB同期、連鎖クローズの画面キャプチャを用意する。
3. CloudWatchイベントからKEDB登録までを同じ`trace_id`で追跡できる証跡を用意する。
4. ライブ実行が中断した場合は、停止地点を明示したうえで保存済み証跡へ切り替える。

保存済み証跡を使用する場合も、どの処理がライブ実行され、どの処理を過去の成功結果で説明したかを明示する。

## 9. 資料53〜69ページとの対応

| 資料の説明 | シナリオ1 | シナリオ2 |
| --- | --- | --- |
| インシデント自動起票・通知 | 主 | 主 |
| 複数情報の相関分析 | 主 | 主 |
| 直前変更との相関特定 | 操作ログ中心 | 承認済みバージョンデプロイと監視時系列 |
| 原因候補提示 | 誤停止 | 新版のメモリ回帰 |
| 復旧策の優先順位付け | 主 | 旧版ロールバックを最優先、恒久修正は復旧後 |
| Agentによる自動判断・自動復旧 | 主 | 承認後のみ自動ロールバック |
| 問題管理連携 | 起票・Known Error参照 | 根本原因・恒久対策・クローズ |
| 修正案／MR生成 | 対象外 | 主 |
| RFC自動生成 | 緊急変更の事後記録 | 主 |
| 影響分析 | CMDB確認 | 主 |
| テスト最適化・実行 | 復旧後ヘルス確認 | 主 |
| リスク評価 | 自動実行可否 | CAB判断材料 |
| Human in the Loop | 例外時のみ | 主 |
| GitLab CI/CD | 証跡または実行経路 | fix MR／テスト、CodeBuild/ECR、Workflow Manager |
| CMDB参照・自動同期 | 主 | 主 |
| プロセス連鎖クローズ | 主 | 主 |
| KEDB蓄積・次回事例活用 | 主 | 主 |

## 10. 推奨する当日の進行

| 時間 | 内容 |
| ---: | --- |
| 1分 | 2シナリオとAI／人の責任分界を説明 |
| 7分 | シナリオ1：誤停止→相関分析→自動再起動→正常性確認 |
| 2分 | 自動実行の条件と、実行しない条件を説明 |
| 12分 | シナリオ2：最新版更新→メモリ兆候/OOM→CABロールバック→修正生成・テスト→CAB→再デプロイ→CMDB/KEDB同期 |
| 2分 | Incident/Problem/Change/CMDB/KEDBの連携を確認 |
| 1分 | `/decisions`とtrace_idで証跡を振り返る |

合計目安は25分。時間が短い場合は、最新版デプロイ、2回のメモリイベント、ソース差分分析を事前実施し、OutOfMemory相関、CAB承認、旧版ロールバック、修正生成・テスト結果、`V_FIXED`デプロイ、CMDB/KEDB同期を中心に見せる。

## 11. 当日チェックリスト

### 環境

- [ ] AWS SSOログイン済み
- [ ] デモ用realmを確認
- [ ] Sulu、GitLab、Zulip、n8n、Grafanaが起動
- [ ] Sulu正常状態を確認
- [ ] コントロールサイトから手動復旧可能
- [ ] 自動起動スケジュールと競合しない

### AIOps Agent

- [ ] CloudWatch ingestが有効
- [ ] `aiops-orchestrator`がActive
- [ ] Workflow ManagerのSulu Service ControlがActive
- [ ] `wf.sulu_service_control`がカタログから取得可能
- [ ] CMDBとRunbookがGitLabから参照可能
- [ ] Qdrant/Knowledge Storeが参照可能
- [ ] ContextStore/Approval Historyが利用可能

### シナリオ1

- [ ] OQ-USECASE-21をdry-run済み
- [ ] 実行用evidenceディレクトリを決定
- [ ] Sulu停止の実施者と復旧責任者を決定
- [ ] `auto_enqueue`が許可されるポリシーを確認
- [ ] Sulu正常性確認方法を決定

### シナリオ2

- [ ] 実行日時点の`V_PREVIOUS`、`V_LATEST`、未使用の`V_FIXED`を確認
- [ ] PHP/Nginxの両ECRリポジトリで開始タグを確認
- [ ] 最新版デプロイChange、Emergency rollback Change、Incident、Problem、恒久対策Changeのテンプレートを準備
- [ ] メモリ90%以上のイベント2件とOutOfMemoryイベント1件に異なる`event_id`を設定
- [ ] `wf.sulu_version_deploy`、`wf.sulu_source_version_compare`、`wf.sulu_rfc_source_analysis`がActive
- [ ] 統合シナリオOQと修正ロジック／MR／RFC自動生成が利用可能
- [ ] `gitlab.code_project_path`と`gitlab.service_project_path`が別々に解決され、書込み権限がある
- [ ] GitLab CI/CDで選択テストを実行し、リスクスコアを生成可能
- [ ] rollback先、影響CI、サービスオーナー、承認者をCMDBで確認
- [ ] CAB承認者がZulipへログイン済み
- [ ] 承認リンクの到達性を確認
- [ ] バージョンデプロイのdry-runとECS/HTTP確認方法を確認
- [ ] code projectのfix branch/MRとservice-management projectのRFC/CMDB/Issue経路を確認
- [ ] 修正branchがCodeBuildの参照先／push mirrorへ到達し、commit SHAが一致することを確認
- [ ] CodeBuild/ECR、`V_FIXED`デプロイ経路を確認
- [ ] Problem/KEDB、CMDB変更履歴の自動同期・連鎖クローズを確認

### 表示・証跡

- [ ] ブラウザタブを実演順に並べる
- [ ] APIキー、token、cookie、tfvars、stateを画面に出さない
- [ ] trace_idをコピーできる場所を用意
- [ ] 失敗時用の事前キャプチャを用意
- [ ] 実行結果を`evidence/demo/<run_id>/`へ保存

## 12. 失敗時のフォールバック

| 失敗 | フォールバック |
| --- | --- |
| CloudWatchイベントが届かない | 保存済みpayloadとn8n実行証跡を表示し、Sulu Service Controlを直接実行 |
| enrichmentが取得できない | GitLabのCMDB/Runbook画面を直接表示し、取得すべき根拠を説明 |
| LLMが期待ワークフローを選ばない | OQ-USECASE-21の成功証跡とjob_planを表示 |
| Sulu再起動が失敗 | コントロールサイトから手動起動し、エスカレーション動作として説明 |
| CAB承認リンクが動かない | `approve <token>`のテキスト承認またはGitLabの決定コメントを使用 |
| GitLab Pipelineが失敗 | 失敗ログとrollback jobを見せ、安全側に止まることを価値として説明 |
| `wf.sulu_version_deploy`をジョブエンジンがdispatchできない | CAB承認履歴を残したうえで専用Webhookを同じ`trace_id`で呼び出す |
| 修正版CodeBuildが失敗 | 既知正常版を維持し、Problemと恒久対策Changeをオープンのままにする |
| Qdrant/KEDBを表示できない | GitLab Problem/Known Error IssueとKnowledge Store同期結果を表示 |

## 13. デモ終了時のまとめ

最後に次の2点を対比して締める。

- **シナリオ1**：既知・可逆・限定影響の復旧は、AIOps Agentが根拠を確認して自動実行する。
- **シナリオ2**：新版障害では、AIOps Agentが旧版ロールバックを提案し、人がEmergency Changeを承認する。復旧後は修正ロジック、MR、RFC、テスト、リスク評価を自動生成し、CAB承認後に`V_FIXED`をデプロイする。正常性確認後はCMDB同期、関連プロセスの連鎖クローズ、KEDB登録まで自動で完了する。

> 自動化の価値は、人を完全に外すことではない。機械が得意な収集・相関・実行・記録を自動化し、人はリスクと責任を伴う判断に集中する。

## 14. 参照実装

- `apps/workflow_manager/service_request/workflows/aiops_sulu_memory_regression_demo.json`
- `apps/workflow_manager/service_request/workflows/test_aiops_sulu_memory_regression_demo.json`
- `apps/workflow_manager/service_request/workflow_sources/sulu_memory_regression_demo.code.js`
- `apps/workflow_manager/service_request/scripts/tests/test_sulu_memory_regression_demo.mjs`
- `apps/aiops_agent/orchestrator/docs/oq/oq_usecase_32_demo_sulu_memory_regression_full_cycle.md`
- `apps/aiops_agent/orchestrator/scripts/run_oq_usecase_32_demo_sulu_memory_regression_full_cycle.sh`
- `apps/aiops_agent/orchestrator/docs/oq/oq_usecase_21_demo_sulu_night_misoperation_autorecovery.md`
- `apps/aiops_agent/orchestrator/scripts/run_oq_usecase_21_demo_sulu_night_misoperation_autorecovery.sh`
- `apps/workflow_manager/service_request/workflows/aiops_sulu_service_control.json`
- `apps/workflow_manager/service_request/workflows/aiops_sulu_version_deploy.json`
- `apps/workflow_manager/service_request/workflows/aiops_sulu_source_version_compare.json`
- `apps/workflow_manager/service_request/workflows/aiops_sulu_rfc_source_analysis.json`
- `apps/workflow_manager/service_request/docs/oq/oq_sulu_version_deploy.md`
- `apps/workflow_manager/service_request/docs/oq/oq_sulu_source_version_compare.md`
- `apps/workflow_manager/service_request/docs/oq/oq_sulu_rfc_source_analysis.md`
- `apps/itsm_core/bootstrap/data/templates/service-management/cmdb/sulu.md.tpl`
- `apps/itsm_core/bootstrap/data/templates/service-management/cmdb/runbook/sulu.md.tpl`
- `apps/aiops_agent/orchestrator/data/default/policy/approval_policy_ja.json`
- `apps/aiops_agent/orchestrator/data/default/policy/decision_policy_ja.json`
- `apps/aiops_agent/orchestrator/docs/oq/oq_usecase_28_approval_link_decision_history.md`
- `apps/aiops_agent/orchestrator/docs/oq/oq_usecase_29_auto_approval_as_decision.md`
- `apps/aiops_agent/knowledge_store/workflows/aiops_problem_management_sync.json`
- `apps/itsm_core/bootstrap/docs/data-model.md`
- `apps/itsm_core/bootstrap/data/templates/service-management/issue_templates/01_incident.md.tpl`
- `apps/itsm_core/bootstrap/data/templates/service-management/issue_templates/03_problem.md.tpl`
- `apps/itsm_core/bootstrap/data/templates/service-management/issue_templates/04_change.md.tpl`
- `apps/itsm_core/bootstrap/data/templates/technical-management/docs/usecases/34_iac_drift_detection.md.tpl`
- `docs/itsm/designs/gitlab_exastro_runner_without_n8n.md`
- `docs/change-management.md`
- `docs/usage-guide.md`
