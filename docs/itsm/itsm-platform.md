# サービス運用基盤の想定

## はじめに

ここに方針のまとめを置くので、迷ったらまずここを見てね。詳しい表は下に続くよ。

- プラクティスカテゴリごとに利用ツールを明確に分離し、責務の重複を避ける  
  - 認証/認可：**Keycloak**  
  - コミュニケーション：**Zulip**  
    - デフォルトで構築する Zulip は、この基盤の構築・運用チーム（Platform/SRE）の利用を想定（顧客/サービス利用者との会話は原則 `#cust-` 接頭辞のストリーム等で分離する）
    - Zulip の接続情報/認証情報は **mess（送信用 Bot）** と **outgoing（受信用 Webhook）** で分け、Terraform/tfvars の変数名も用途ごとに統一する（旧 `aiops_zulip_*_yaml` / `zulip_bot_tokens_yaml` は廃止）
      - mess（送信用 Bot）: `zulip_mess_bot_tokens_yaml`, `zulip_mess_bot_emails_yaml`, `zulip_api_mess_base_urls_yaml`
      - outgoing（受信用 Webhook）: `zulip_outgoing_tokens_yaml`, `zulip_outgoing_bot_emails_yaml`
  - 連携/自動化：**n8n**  
  - ベクトルDB（検索/類似度/埋め込みインデックス）：**Qdrant（n8n 連携）**  
    - n8n の realm ごとのタスク内サイドカーとして起動し、n8n から `QDRANT_URL` で参照する（詳細: `docs/itsm/README.md` の Qdrant 節）
  - サービス管理/CMDB：**GitLab サービス管理（CMDB/Issue, `cmdb/`）**  
  - 構成自動化/構成情報取得：**Exastro ITA Web / Exastro ITA API**  
  - クラウド側ログ分析基盤：**CloudWatch → * → Athena → Grafana（＋CloudWatch datasource）**  
  - クラウド側ログ通知基盤：**CloudWatch → *（Webhook）→ n8n**
- 監視・オブザーバビリティはクラウド側ログ分析/通知基盤を前提とし、GitLab/Zulip/n8n は「記録・起票・通知・自動処理」を担当
- テスト自動化・実行基盤は各プロジェクトが自由に選択（例：GitLab CI）。本方針では特定ツールを規定しない
- 似た機能を持つツールは採用・非採用の根拠を明示し、利用しない機能を明確化する
- ナレッジ/設計/運用手順は GitLab（リポジトリ/Markdown）に集約し、会話は Zulip に集約する
- CMDBのマスターはレルム対応のGitLabグループ「サービス管理プロジェクト」内 `cmdb/`。他ツールは参照・同期のみで正は持たない
- カレンダー機能の使い分け：サービス変更・リリース・アウトージ予定は GitLab サービス管理（Issue/ボード/マイルストーン）に登録し、必要に応じて n8n で外部カレンダーへ同期する（専用ERP/グループウェアは本構成には含めない）

関連ドキュメント:
- [GitLab更新イベントの@メンション通知（Zulip DM）](../../apps/gitlab_mention_notify/README.md)

## 共通メッセージング仕様（Zulip / n8n / Qdrant / GitLab / クラウド側ログ基盤 / Exastro ITA）

誰でも追えるように、プラクティスをまたいでツール間がどうメッセージ交換するか（イベント→起票→通知→証跡化）を共通仕様としてまとめる。

- 本ドキュメントは「全体の役割分担/連携経路」を定義する。プラクティスごとの詳細なガイドは GitLab 管理プロジェクトのテンプレート（`scripts/itsm/gitlab/templates/*-management/docs/*_management/`）を正とする。
  - 一般管理: `scripts/itsm/gitlab/templates/general-management/docs/general_management/`
  - サービス管理: `scripts/itsm/gitlab/templates/service-management/docs/service_management/`
  - 技術管理: `scripts/itsm/gitlab/templates/technical-management/docs/technical_management/`
  - 監視参照の統一（Grafana）: `scripts/itsm/gitlab/templates/service-management/docs/monitoring_unification_grafana.md.tpl`

- 適用範囲: 一般管理 / サービス管理 / 技術管理プラクティクスを実現するための、ツール間データ連携（通知・起票・CMDB同期・実行要求）
- 中核経路:
  - **クラウド側ログ通知基盤**: CloudWatch → *（Webhook）→ n8n → GitLab（起票/更新）→ Zulip（通知）
  - **クラウド側ログ分析基盤**: CloudWatch Logs → *（Firehose等）→ S3 → Glue Data Catalog → Athena → Grafana（可視化/検索/ダッシュボード、必要に応じてアラート→Webhook）
    - 補足: 低遅延の監視系は Grafana の CloudWatch datasource（メトリクス/アラーム）で参照し、ログの長期検索・集計は Athena を正とする（CloudWatch Logs を Grafana から直接参照しない）
  - **CMDB同期**: Exastro ITA API（CMDB情報の取得）→ n8n（差分/正規化）→ GitLab サービス管理プロジェクト `cmdb/`（MR/コミット）→ Zulip（同期結果通知）
  - **ナレッジ検索（ベクトル）**: GitLab（Runbook/FAQ/CMDB/Issue等の本文）→ n8n（抽出/分割/埋め込み）→ Qdrant（インデックス）→ n8n（類似検索）→ GitLab/Zulip（提案/リンク）
  - **運用イベント**: GitLab（Issue/MR/Webhook）→ n8n → Zulip（変更/インシデント/承認の通知）
- 正のデータ:
  - CMDB: GitLab サービス管理プロジェクト `cmdb/`
  - （将来/改善）統合データモデルの正: ITSM コア DB（PostgreSQL）。詳細は `docs/itsm/data-model.md` を参照
  - 会話/調整/最終決定: Zulip（経緯記録/証跡は GitLab へ）
  - 監視参照: Grafana（状態参照の中心。Issue/レポートの参照リンクも Grafana に統一する）
  - ログ検索/可視化: Athena/Grafana（ログの本文や検索結果をGitLabへ複製しない）
  - ベクトルインデックス: Qdrant（ただし「文書/台帳の正」はGitLab。Qdrantは検索用の派生データ）
  - 運用手順（Runbook）: GitLab サービス管理プロジェクトの `cmdb/runbook/` を正とする（例: Sulu は `cmdb/runbook/sulu.md`。n8n から参照するパスは `N8N_GITLAB_RUNBOOK_MD_PATH` で指定）

### ヘッダ項目（共通）

メッセージ/イベントの共通項目。Webhook payload / GitLab Issue本文 / Zulip通知本文のどこに載せるかは経路ごとに異なるが、意味は揃える。

- `message_id`: メッセージ一意ID（再送・重複排除のキー）
- `correlation_id`: 一連の対応を束ねるID（インシデントID、変更ID、アラーム名+発火時刻など）
- `event_type`: 種別（例：`cloudwatch.alarm` / `cloudwatch.log_match` / `gitlab.issue.created` / `exastro.cmdb.sync`）
- `severity`: 重要度（例：`info` / `warning` / `critical`）
- `occurred_at`: 発生時刻（ISO 8601）
- `source_system`: 発生源（CloudWatch / Grafana / GitLab / Exastro ITA / n8n / Qdrant）
- `target_system`: 配送先（n8n / GitLab / Zulip / Qdrant）
- `environment`: 対象環境（例：`dev` / `stg` / `prd`）
- `service`: 対象サービス名（GitLab CMDBのサービスCI名に寄せる）
- `ci_ref`: CI参照（GitLab CMDBのCI ID/パス/識別子。複数可）
- `summary`: 1行要約（Zulip通知の先頭に使う）
- `links`: 根拠URL（Grafanaパネル、Athenaクエリ、CloudWatchログ、GitLab Issue/MR、Exastroジョブ履歴など）
- `payload`: 詳細（必要最小限。PII/機微は含めない）
- `vector_index`: ベクトル検索用の識別子（コレクション名、namespace、フィルタ条件など）

### 共通ルール（矛盾防止）

- **起票/状態の正**: 対応が必要な事象は GitLab サービス管理（Issue）に集約し、状態（ステータス/担当/期限）と証跡は GitLab を正に寄せる。
- **会話/最終決定の正**: 速度重視のため最終決定は Zulip のトピック上で行う（決定メッセージに根拠リンクを含め、GitLab にはリンク付き要約を残す）。
- **決定マーカー**: 最終決定は Zulip メッセージとして明示し、`/decision`（既定）で始まる投稿は `apps/zulip_gitlab_issue_sync` が GitLab Issue に「決定（Zulip）」コメントとして証跡化する（マーカーは `ZULIP_GITLAB_DECISION_PREFIXES` で変更可）。
- **GitLab 側の決定通知（補助）**: 例外的に GitLab 側で決定（`[DECISION]` / `決定:`）を記録した場合は、Zulip へ通知して関係者へ到達させる（詳細: `apps/zulip_gitlab_issue_sync/README.md`）。
- **根拠リンク優先**: ログ本文の貼り付けではなく、Athena/Grafana/CloudWatch へのリンクを根拠とする（GitLabには要約と参照URL）。
- **PII取り扱い**: PIIはZulipへ貼らない。必要ならGitLabのConfidential Issueに限定し、n8n通知はマスキング済みの要約のみ。
- **冪等性**: n8nは `message_id` / `correlation_id` で重複起票・重複通知を抑止する。
- **権限**: 連携はKeycloakのロールに基づき、n8n/GitLab/Exastroのservice accountを用途別に分離する。
- **インデックス整合性**: Qdrant は再生成可能な派生データとして扱い、GitLabの更新（MR/Issue更新）を起点に n8n が再インデックスする（検索結果には常にGitLabの参照URLを含める）。
- **監視参照の統一**: 監視の参照先は Grafana に統一し、Issue/レポートの根拠リンクも Grafana を基本にする（詳細: `scripts/itsm/gitlab/templates/service-management/docs/monitoring_unification_grafana.md.tpl`）。
- **SLA/OLA/UCの参照**: SLA/OLA/UC マスターは「参照ダッシュボード（URL/UID/データソース）」を含め、算出根拠の参照先を固定する（`scripts/itsm/gitlab/templates/service-management/docs/sla_master.md.tpl` / `scripts/itsm/gitlab/templates/service-management/docs/ola_master.md.tpl` / `scripts/itsm/gitlab/templates/service-management/docs/uc_master.md.tpl`）。
- **CMDBの監視メタデータ**: CMDB の `grafana` セクションに、ダッシュボードUID/対象メトリクス/集計期間/データソース等を整備し、`aws_monitoring` は参考扱いとする（テンプレのCI検証で欠落を検知できる状態にする）。

### Grafana の ITSM ユースケースダッシュボード同期手順

Grafana のフォルダ/ダッシュボードは `scripts/itsm/grafana/sync_usecase_dashboards.sh` で同期する。API トークンが未設定/期限切れの場合は先に更新する。

1. SSO ログイン  
   - `aws sso login --profile "$(terraform output -raw aws_profile)"`
2. Grafana API token 更新（`terraform.itsm.tfvars` を更新し、最後に `terraform apply --refresh-only` を実行）  
   - `bash scripts/itsm/grafana/refresh_grafana_api_tokens.sh`
3. dry-run で対象/影響確認（レルム指定）  
   - `GRAFANA_DRY_RUN=true GRAFANA_TARGET_REALM=<realm> scripts/itsm/grafana/sync_usecase_dashboards.sh`
4. 本適用（レルム指定）  
   - `GRAFANA_TARGET_REALM=<realm> scripts/itsm/grafana/sync_usecase_dashboards.sh`

注意:
- `terraform.itsm.tfvars` はローカル管理（Git 管理外）。更新後にコミットしないこと。
- ダッシュボード同期は **レルム単位** で行い、対象レルムを必ず指定すること。

### メッセージング一覧（主要ワークフロー）

テーブルは「この運用基盤で必ず使う経路」に絞る（不要なツールや経路を増やさない）。

#### 一般管理プラクティクス

| プラクティスカテゴリ | プラクティクス | ワークフロー名 | 処理内容 | データ内容（例） | データ送信元 | データ送信先 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 一般管理プラクティクス | 測定および報告 | KPI-週次レポート生成 | Athena集計結果を週次レポートIssueへ反映し通知 | 集計値、期間、リンク | n8n | GitLab / Zulip | ログ根拠はAthena/Grafana |
| 一般管理プラクティクス | 継続的改善 | ポストモーテム起票 | 重大インシデント解決後に振り返りIssueを起票 | インシデントID、要約 | GitLab | n8n / Zulip | テンプレートはGitLab側で管理 |
| 一般管理プラクティクス | リスク管理 | リスクレビュー通知 | 期限到来リスクIssueを抽出し通知 | リスクID、期限 | n8n | Zulip | 実体はGitLab Issue |
| 一般管理プラクティクス | 情報セキュリティ管理 | 権限変更監査通知 | Keycloakの変更イベントを要約し通知/記録 | 変更種別、対象ロール | Keycloak | n8n / GitLab / Zulip | PIIはマスキング |

#### サービス管理プラクティクス

| プラクティスカテゴリ | プラクティクス | ワークフロー名 | 処理内容 | データ内容（例） | データ送信元 | データ送信先 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| サービス管理プラクティクス | 監視およびイベント管理 | アラート自動起票 | CloudWatchイベントを受信しインシデントを起票 | アラーム、CI、重大度、リンク | CloudWatch | n8n → GitLab / Zulip | 重複抑止（`correlation_id`） |
| サービス管理プラクティクス | インシデント管理 | 重大インシデント周知 | 重大度判定後に周知し、専用トピックへ誘導 | インシデントID、影響 | GitLab | n8n → Zulip | 進捗はGitLabに集約 |
| サービス管理プラクティクス | 変更管理 | 承認結果通知 | 承認フローの結果を通知し実行ゲートを開閉 | 変更ID、承認者、結果 | GitLab | n8n → Zulip / Exastro ITA API | 承認済みのみ実行 |
| サービス管理プラクティクス | サービス構成管理 | CMDB同期（定期） | Exastro/クラウドAPIの構成情報をGitLab CMDBへ同期 | CI属性、差分、リンク | Exastro ITA API | n8n → GitLab / Zulip | `cmdb/` はMRで更新 |
| サービス管理プラクティクス | サービス要求管理 | 受付→起票 | Zulip/Issueフォームの要求を起票し担当割当 | 要求種別、要約 | Zulip / GitLab | n8n → GitLab / Zulip | 外部フォームはWebhook経由 |
| サービス管理プラクティクス | コミュニケーション（例外処理） | GitLabメンション通知の宛先解決 | GitLabの `@username` を Zulip 宛先へ解決して通知 | mention、宛先、通知内容 | GitLab | n8n → Zulip | 原則メール/username一致、例外は対応表（`scripts/itsm/gitlab/templates/service-management/docs/mention_user_mapping.md.tpl`） |

#### 技術管理プラクティクス

| プラクティスカテゴリ | プラクティクス | ワークフロー名 | 処理内容 | データ内容（例） | データ送信元 | データ送信先 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 技術管理プラクティクス | デプロイメント管理 | 変更→デプロイ要求 | 承認済み変更からExastroジョブ/パイプラインを起動 | 変更ID、対象、パラメータ | GitLab | n8n → Exastro ITA API / GitLab | 実行結果はGitLabへ記録 |
| 技術管理プラクティクス | デプロイメント管理 | 失敗時通知 | 実行失敗をZulipへ通知し、Issueを更新 | ジョブID、ログリンク | Exastro ITA API | n8n → GitLab / Zulip | 再実行はGitLabから |
| 技術管理プラクティクス | インフラ管理 | ドリフト検出 | 構成差分を検出しCMDB/変更Issueへ反映 | 差分、影響CI | Exastro ITA API | n8n → GitLab / Zulip | 差分はCMDBへ集約 |
| 技術管理プラクティクス | オブザーバビリティ | Grafanaアラート配送 | GrafanaアラートをWebhookで受け、起票/通知 | アラート名、リンク | Grafana | n8n → GitLab / Zulip | CloudWatch経由でも可 |
| 技術管理プラクティクス | ナレッジ管理（検索性向上） | Qdrant-インデックス更新 | GitLabのナレッジ/Issue/Runbookを抽出しベクトル化してQdrantへ反映 | ドキュメントID、チャンク、埋め込み、参照URL | GitLab | n8n → Qdrant | 「正」はGitLab。Qdrantは検索用 |
| 技術管理プラクティクス | ナレッジ管理（検索性向上） | Qdrant-類似検索 | インシデント/変更Issueから類似事例・Runbookを検索し提案 | クエリ、上位候補、参照URL | GitLab | n8n → Qdrant → GitLab / Zulip | 提案はリンク中心（本文複製しない） |

## 一般管理プラクティクス（Strategy〜Supplier）

### 使用ツール：GitLab / Zulip / n8n / Qdrant / Keycloak / クラウド側ログ分析基盤（CloudWatch→*→Athena→Grafana）

| プラクティスカテゴリ | プラクティクス | ツール名 | プラクティスのなかでのツールのユースケース | ツールの保持する機能の中で利用する機能 | 重要な判断分岐 |
| --- | --- | --- | --- | --- | --- |
| 一般管理プラクティクス | 戦略管理（Strategy management） | GitLab | 方針/戦略/ADRをMarkdownで版管理し、戦略テーマをEpic/Issueで追跡 | リポジトリ、MRレビュー、Epic/Issue、ラベル/マイルストーン | - |
| 一般管理プラクティクス | 戦略管理 | GitLab | 中長期ロードマップ・戦略テーマをEpic/Issueとして管理し、進捗とKPIを可視化 | Epic/Issue、ボード、マイルストーン、ラベル | - |
| 一般管理プラクティクス | ガバナンス（Governance） | GitLab | 方針/規程/標準、例外、承認フロー、監査証跡を版管理し、透明性と説明責任を担保 | MR承認、Issueテンプレート、監査ログ、ラベル | 標準化と例外運用の境界／承認速度と統制のバランス |
| 一般管理プラクティクス | 組織と体制（Organization and roles） | GitLab | 役割/責任/権限、会議体、RACIの前提を整備し、運用判断の遅延を防ぐ | ドキュメント、Issue、承認 | 役割分担の見直し頻度／兼務の許容範囲 |
| 一般管理プラクティクス | ポートフォリオ管理（Portfolio management） | GitLab | サービス/改善テーマの優先度・依存関係・ロードマップを一元管理 | Epic/Issue、マイルストーン、ボード、ラベル | - |
| 一般管理プラクティクス | アーキテクチャ管理（Architecture management） | GitLab | 全体/サービスアーキテクチャ図・ADR・標準を版管理 | Markdown、Mermaid、MRレビュー | - |
| 一般管理プラクティクス | アーキテクチャ管理 | GitLab | アーキテクチャ改善ロードマップをIssueとして管理し、完了まで追跡 | Issue、ボード、マイルストーン | - |
| 一般管理プラクティクス | 意思決定記録（Decision records） | GitLab | 意思決定（ADR/決裁ログ）を一元管理し、後追い可能にする | MRレビュー、Markdown、Issueリンク | 何を意思決定記録に残すか／例外をどう扱うか |
| 一般管理プラクティクス | サービス財務管理（Service financial management） | GitLab | コスト/予算の要約（前提・根拠・意思決定）をIssueで管理し、変更と紐付け | Issue、ラベル、テンプレート、リンク | 課金モデル（ショーバック/チャージバック/配賦）／予算超過時に削減か追加予算か／CapExかOpExか |
| 一般管理プラクティクス | 継続的改善（Continual improvement） | GitLab | 改善提案・CSIレジスタ・ふりかえり（ポストモーテム）をIssue/Markdownで記録 | Issue、テンプレート、ラベル、MR | 改善選定（価値/リスク/容易性）／クイックウィンか長期ロードマップか／KPI/OKRで継続か終了か |
| 一般管理プラクティクス | 継続的改善 | GitLab | 承認済み改善案件をIssueとして管理し完了まで追跡 | Issue、ボード、担当者/期限管理 | - |
| 一般管理プラクティクス | 測定および報告（Measurement and reporting） | クラウド側ログ分析基盤（Athena/Grafana） | 運用KPIの根拠となるログ/メトリクスの可視化・検索・期間集計 | CloudWatch Logs、S3/Glue/Athena、Grafanaダッシュボード | - |
| 一般管理プラクティクス | 測定および報告 | GitLab | KPI定義・測定方式・算出ロジックなどメタ情報の版管理 | Markdown、Issue、MRレビュー | - |
| 一般管理プラクティクス | リスク管理（Risk management） | GitLab | リスク登録簿、評価（頻度/影響）、対応計画をIssueで管理 | Issue、ラベル、担当/期限、承認 | - |
| 一般管理プラクティクス | リスク管理 | GitLab | リスクマネジメント方針・標準・手順・チェックリストの版管理 | Markdown、MRレビュー | - |
| 一般管理プラクティクス | 情報セキュリティ管理（Information security management） | GitLab | ISMS文書/ポリシー/標準手順書/教育資料を版管理（アクセス制御はKeycloak連携を前提） | リポジトリ、MR承認、アクセス制御 | アクセス要求をRBACで処理するか例外付与か／重大度に応じCSIRT召集が要るか／ポリシー例外をどこまで許容し期間をどう限定するか |
| 一般管理プラクティクス | ナレッジ管理（Knowledge management） | GitLab | ITSMナレッジ、トラブルシュートガイド、FAQ、HOWTOの一元管理 | Markdown、検索、MRレビュー | コンテンツを簡易FAQに留めるか詳細手順と原因まで含めるか／内部限定か外部公開か／インシデント・変更後のレビューを必須にするか |
| 一般管理プラクティクス | 組織変更管理（Organizational change management） | GitLab | 組織改編・役割変更・大規模プロセス変更をIssueとして計画・進捗管理 | Issue、マイルストン、ボード | - |
| 一般管理プラクティクス | 組織変更管理 | GitLab | 変更影響分析、コミュニケーション計画、FAQの文書化 | Markdown、リンク、履歴、コメント | - |
| 一般管理プラクティクス | プロジェクト管理（Project management） | GitLab | 導入・改善・移行などのスコープ/スケジュール/コスト（要点）をIssueで管理 | Issue、マイルストン、ボード | - |
| 一般管理プラクティクス | プロジェクト管理 | GitLab | プロジェクト憲章、WBSドラフト、議事録などの情報共有 | Markdown、リンク | - |
| 一般管理プラクティクス | リレーションシップ管理（Relationship management） | Zulip | ビジネス部門・ステークホルダとのコミュニケーション窓口（会議/合意形成） | ストリーム/トピック、メンション、検索 | - |
| 一般管理プラクティクス | リレーションシップ管理 | GitLab | 重要ステークホルダとの合意事項・期待値・コミュニケーションルールの文書化 | Markdown、Issue、リンク | - |
| 一般管理プラクティクス | サプライヤ管理（Supplier management） | GitLab | ベンダ契約・SLA・更新期日・評価・連絡履歴をIssueで管理 | Issue、期限、テンプレート、ラベル | 契約形態（SLA付きかベストエフォートか）／KPI報告頻度（月次/四半期/例外）／罰則・補償を行使するか再交渉か |
| 一般管理プラクティクス | 外部連携/契約（External relationships） | GitLab | 契約/依存関係/エスカレーション経路をサービス（CI）に紐付けて管理 | ドキュメント、UCマスター、リンク | 契約更新と運用SLA/OLAの整合／委託境界の明確化 |

---

## サービス管理プラクティクス（Business analysis〜IT asset）

### 使用ツール：GitLab サービス管理（CMDB/Issue） / n8n / Zulip / Exastro ITA Web / Exastro ITA API / クラウド側ログ通知基盤 / クラウド側ログ分析基盤（Athena/Grafana）

※ 監視・オブザーバビリティはクラウド側ログ分析/通知基盤（CloudWatch→*→Athena/Grafana、CloudWatch→*（Webhook）→n8n）で実施し、ここでは連携・記録に限定する。

| プラクティスカテゴリ | プラクティス | ツール名 | プラクティスのなかでのツールのユースケース | ツールの保持する機能の中で利用する機能 | 重要な判断分岐 |
| --- | --- | --- | --- | --- | --- |
| サービス管理プラクティクス | ビジネス分析（Business analysis） | GitLab サービス管理（CMDB/Issue） | サービス/ビジネスプロセス/ステークホルダをCIとしてモデリングし、as-is/to-be構造を可視化 | サービス/プロセス/組織CI定義、属性管理、関係管理 | - |
| サービス管理プラクティクス | ビジネス分析 | Zulip | ビジネス部門との要件ヒアリング・レビューのコミュニケーションチャネル | ストリーム/トピックのスレッド、メンション、添付、検索 | - |
| サービス管理プラクティクス | サービスカタログ管理（Service catalogue management） | GitLab サービス管理（CMDB/Issue） | 提供サービス一覧・属性・SLAクラスのカタログ管理 | サービスCI、属性（提供時間/SLA等）、ビュー、レポート | - |
| サービス管理プラクティクス | サービス設計（Service design） | GitLab サービス管理（CMDB/Issue） | 新サービスのCI構造、依存関係、環境構成の設計モデル管理 | サービス構成図（CIと関係）、バージョン属性、設計資料添付 | - |
| サービス管理プラクティクス | サービス設計 | Zulip | サービス設計レビューや設計変更の議論 | トピック単位スレッド、メンション、ファイル共有 | - |
| サービス管理プラクティクス | サービスレベル管理（Service level management） | GitLab サービス管理（CMDB/Issue） | サービスごとのSLA/OLA定義と合意内容を管理 | サービスCI属性にSLA/OLA項目追加、履歴、レポート | SLA/OLAを新規に定義するかテンプレ適用か／メトリクスは結果指標か体験指標か／計画停止やフォースマジュールを算定除外するか |
| サービス管理プラクティクス | サービスレベル管理 | n8n | 監視基盤からのSLA違反イベントを受信し、CMDB/チケット登録とZulip通知を自動化 | Webhookトリガ、REST API、条件分岐、スケジュール実行 | - |
| サービス管理プラクティクス | 可用性管理（Availability management） | GitLab サービス管理（CMDB/Issue） | 可用性設計（冗長構成/SPOF）とサービス影響範囲を構成情報として管理 | CI依存関係、タグ（冗長/単一）、レポート | 冗長化/フェイルオーバ/リージョン分散が必要か／RTO/RPO目標に現行設計が足りるか／可用性向上コストを許容するか |
| サービス管理プラクティクス | 可用性管理 | n8n | 監視アラートを受信し、インシデント登録と担当チーム通知を自動化 | Webhook、条件分岐、Zulip/GitLab API連携 | - |
| サービス管理プラクティクス | キャパシティ＆パフォーマンス管理（Capacity and performance management） | n8n | クラウドメトリクスAPIから容量・性能指標を取得し、集計結果をGitLab（CMDB/Issue）へ連携 | スケジュールジョブ、API呼び出し、データ変換 | - |
| サービス管理プラクティクス | キャパシティ＆パフォーマンス管理 | GitLab サービス管理（CMDB/Issue） | サービスごとの容量計画（閾値、増設計画）の記録 | CI属性（想定負荷/上限値/増設計画）、レポート | 需要予測による先行増強かオートスケール追随か／ボトルネックの優先度（アプリ/DB/ネット）／リザーブド・スポット・オンデマンド配分をどうするか |
| サービス管理プラクティクス | サービス継続管理（Service continuity management） | GitLab サービス管理（CMDB/Issue） | サービスごとのRTO/RPO・BCP・復旧手順を構成情報に紐付けて管理 | サービスCI属性（RTO/RPO）、BCP文書添付、代替サイト等の関係 | - |
| サービス管理プラクティクス | サービス継続管理 | Zulip | BCP訓練時の連絡・状況共有チャネル | ストリーム/トピック、メンション、ファイル共有 | - |
| サービス管理プラクティクス | 監視およびイベント管理（Monitoring and event management） | n8n | 監視イベントを受信し、重要度に応じてインシデント化・通知・自動復旧フロー起動 | Webhook、条件分岐、リトライ、外部API | シグナルを情報/警告/例外でどこまで分けるか／相関・抑制・デダプをどこまで自動化するか／閾値超過時に自動チケット化するか |
| サービス管理プラクティクス | 監視およびイベント管理 | Zulip | 重大イベントのアラート通知チャネル | チャットメッセージ、メンション、ピン留め | - |
| サービス管理プラクティクス | サービスデスク（Service desk） | Zulip | 利用者からの問い合わせ・依頼を受け付ける一次窓口チャネル | ストリーム/トピック、フォーム連携（ボット経由）、検索 | - |
| サービス管理プラクティクス | サービスデスク | n8n | Zulip専用トピックやフォーム入力を検知し、GitLab Issueへ自動登録 | Zulip連携、HTTPノード、条件分岐 | 受付チャネルの優先（電話/チャット/ポータル）／初回解決率を狙うか専門チームへ振るか／影響×緊急度でどのキューに送るか |
| サービス管理プラクティクス | サービスデスク | GitLab サービス管理（CMDB/Issue） | インシデント・サービス要求等のチケット記録と状態/SLA管理 | チケットクラス定義、ワークフロー、レポート、SLA属性 | - |
| サービス管理プラクティクス | インシデント管理（Incident management） | GitLab サービス管理（CMDB/Issue） | インシデント記録、影響サービス/CIの紐付け、SLA計測 | インシデントクラス、関係（影響サービス/CI）、ワークフロー | - |
| サービス管理プラクティクス | インシデント管理 | Zulip | インシデント対応用専用ストリーム/トピックで対応状況をリアルタイム共有 | トピックスレッド、メンション、ファイル共有 | - |
| サービス管理プラクティクス | インシデント管理 | n8n | 監視イベントから自動インシデント起票、エスカレーション、クローズ処理の自動化 | ワークフロー、タイマ、条件分岐、REST API連携 | 重大度判定（即時エスカレか標準対応か）／影響範囲（単一/全体/外部顧客）／ワークアラウンド優先か恒久対応待ちか／SLA通知やステークホルダー告知の要否 |
| サービス管理プラクティクス | サービス要求管理（Service request management） | GitLab サービス管理（CMDB/Issue） | 標準サービス要求（アカウント発行等）のカタログとワークフロー管理 | サービス要求クラス、テンプレート、ワークフロー | - |
| サービス管理プラクティクス | サービス要求管理 | n8n | 定型要求の自動処理（例：権限追加要求からKeycloak/クラウドAPIを呼び出す） | トリガ、外部API連携、条件分岐 | カタログ項目か新規フローか／自動化レベル（自動/セルフ/手動）／承認省略の可否（権限・コスト・リスク）／依頼者区分や業務優先度で順序を変えるか |
| サービス管理プラクティクス | サービス要求管理 | Zulip | 利用者からの要求受付・ステータス連絡 | ストリーム/トピック、ボット連携 | - |
| サービス管理プラクティクス | 問題管理（Problem management） | GitLab サービス管理（CMDB/Issue） | 問題記録・原因調査・既知エラーDB管理 | 問題クラス、既知エラークラス、インシデントリンク、ワークフロー | - |
| サービス管理プラクティクス | 問題管理 | Zulip | 問題レビュー会議・恒久対策の議論 | トピック、メンション、ファイル共有 | 調査着手のトリガ（繰り返し/重大/規制要件）／既知エラーDB登録で済むか詳細RCAか／恒久対策の価値（リスク・コスト・再発確率）／再発観察期間を設けるか即クローズか |
| サービス管理プラクティクス | リリース管理（Release management） | GitLab サービス管理（CMDB/Issue） | 本番リリースカレンダ、内容、影響範囲、承認状況を管理 | リリースクラス、カレンダビュー、承認ワークフロー | - |
| サービス管理プラクティクス | リリース管理 | n8n | リリースレコード状態に応じてGitLab/Exastro ITA APIを呼び出しデプロイ連携 | GitLab API、GitLab/Exastro API連携、条件分岐 | デプロイ方式（段階/ブルーグリーン/カナリア/ビッグバン）／依存サービス・データ移行を分けるか同時か／本番前の検証範囲／ロールバック判定の閾値とタイミング |
| サービス管理プラクティクス | 変更管理（Change enablement） | GitLab サービス管理（CMDB/Issue） | 変更要求（RFC）の登録・評価・CAB承認・実施・レビュー管理 | RFCクラス、承認ステップ、関係（影響サービス/CI）、レポート | - |
| サービス管理プラクティクス | 変更管理 | Zulip | 変更諮問委員会（承認者）議論・緊急変更時の合意形成 | トピック、メンション、ファイル共有 | 変更タイプ（標準/通常/緊急）／リスク評価で承認経路を簡略化できるか／変更諮問委員会（承認者）/ECAB要否／実行ウィンドウはフリーズ期間外か／バックアウト手順がリハーサル済みか |
| サービス管理プラクティクス | 変更管理 | n8n | 承認済み変更のみExastro ITAやGitLabに渡すゲートを実装 | 条件分岐、API連携、ロールバックフロー | - |
| サービス管理プラクティクス | サービス妥当性確認およびテスト（Service validation and testing） | n8n | 各プロジェクトのテスト結果を集約し、GitLabのリリース/変更Issueへ自動登録 | Webhook受信（外部CI: GitLab等）、API連携、条件分岐 | - |
| サービス管理プラクティクス | サービス構成管理（Service configuration management） | GitLab サービス管理（CMDB/Issue） | 運用対象のCI（サーバ、DB、アプリ、ネットワーク等）と関係性をCMDBとして一元管理 | CMDBクラス定義、リレーション、バージョン管理、レポート | CI粒度をどの単位にするか／自動収集か手動登録か／変更完了時にCI更新を強制するか |
| サービス管理プラクティクス | サービス構成管理 | n8n | GitLab/Exastro ITA/クラウドAPIから構成情報を取得しGitLab CMDBへ同期 | API連携、スケジュール、差分検出（ワークフロー実装） | - |
| サービス管理プラクティクス | IT資産管理（IT asset management） | GitLab サービス管理（CMDB/Issue） | ハードウェア/ソフトウェア/ライセンス/クラウドリソースの資産台帳管理 | 資産クラス、ライフサイクル属性、レポート、契約情報 | 資産をCIとしてCMDB管理するか台帳のみか／調達・配布・廃棄の承認やワイプを必須にするか／ライセンス違反を即是正するか |
| サービス管理プラクティクス | IT資産管理 | n8n | クラウドAPIやスプレッドシートから資産情報を取り込み、GitLab CMDBに登録/更新 | 外部データソース連携、データ変換、条件分岐 | - |

---

## 技術管理プラクティクス（Deployment〜Software development）

### 使用ツール：GitLab / Exastro ITA Web / Exastro ITA API / Keycloak / クラウド側ログ分析基盤 / クラウド側ログ通知基盤

| プラクティスカテゴリ | プラクティス | ツール名 | プラクティスのなかでのツールのユースケース | ツールの保持する機能の中で利用する機能 | 重要な判断分岐 |
| --- | --- | --- | --- | --- | --- |
| 技術管理プラクティクス | デプロイメント管理（Deployment management） | GitLab | Keycloak/Zulip/n8n/Exastro など運用基盤コンポーネントのビルド/デプロイを行うCI/CD基盤 | リポジトリ管理、CI/CDパイプライン、環境/ブランチ戦略、アーティファクト管理 | - |
| 技術管理プラクティクス | デプロイメント管理 | Exastro ITA Web | サーバ設定・ミドルウェア構成・ジョブをGUIで定義し、GitLabパイプラインから呼び出す実行基盤 | 作業パターンテンプレート、パラメータシート、ジョブ実行/履歴管理 | 配布順序（DEV→STG→PRDかロールアウト波か）／パイプライン化し手動ゲートを残すか／部分ロールアウトで健康チェックを挟むか |
| 技術管理プラクティクス | デプロイメント管理 | Exastro ITA API | GitLabやn8nから自動デプロイ/ロールバック要求を受けるAPIエンドポイント | REST API、ジョブトリガ、実行ステータス取得 | - |
| 技術管理プラクティクス | インフラストラクチャおよびプラットフォーム管理（Infrastructure and platform management） | Exastro ITA Web | サーバ/ミドルウェア/ネットワーク設定の標準化とプロビジョニング自動化 | 構成テンプレート、パラメータ管理、ジョブスケジューラ | - |
| 技術管理プラクティクス | インフラストラクチャおよびプラットフォーム管理 | Exastro ITA API | IaCツールやn8nからの自動プロビジョニング要求のAPI窓口 | APIトリガ、認証、結果取得 | - |
| 技術管理プラクティクス | インフラストラクチャおよびプラットフォーム管理 | Keycloak | GitLab/Zulip/n8n/Exastro/Grafana/Qdrant へのSSO・認可基盤 | ユーザ/グループ管理、RBAC、OIDC/SAML、外部ディレクトリ連携 | - |
| 技術管理プラクティクス | インフラストラクチャおよびプラットフォーム管理 | クラウド側ログ分析基盤（CloudWatch→*→Athena→Grafana） | ログの収集/長期保管/検索/ダッシュボード化（調査・監査・傾向分析） | CloudWatch Logs、（Kinesis Firehose等）→S3、Glue Data Catalog、Athena、Grafana | - |
| 技術管理プラクティクス | インフラストラクチャおよびプラットフォーム管理 | クラウド側ログ通知基盤（CloudWatch→*（Webhook）→n8n） | アラーム/ログイベント/イベントをWebhookでn8nへ配送し、自動起票・通知・復旧を起動 | CloudWatch Alarms/Logs/EventBridge、（SNS/Lambda等）→Webhook、再送/抑止 | - |
| 技術管理プラクティクス | ソフトウェア開発および管理（Software development and management） | GitLab | 運用基盤のソースコード管理、レビュー、CI/CD、バージョン管理の中心 | Gitリポジトリ、マージリクエスト、コードレビュー、CI/CD、パッケージレジストリ | - |

---

## ツールの役割と「似た機能の使い分け」の要約（根拠）

似た機能を持つツールの採用方針（役割分担）の整理。

- **GitLab サービス管理（CMDB/Issue） vs Exastro ITA（構成・自動化）**  
  - GitLab：CMDB（`cmdb/`）とチケットの正。変更/承認/証跡を残す中心  
  - Exastro ITA：構成パラメータ・作業手順の定義と実行（Web/API）  
  - 方針：Exastro ITA から取得できる構成情報は n8n で差分化し、GitLab CMDB を随時更新（MR/コミット）して「参照先の一元化」を担保する

- **Zulip（会話） vs GitLab（長期記録）**  
  - Zulip：インシデント/依頼/合意形成のリアルタイム窓口（トピックで整理）  
  - GitLab：経緯記録/証跡（決定の要約・根拠リンク・承認ID）・Runbook・設計・台帳の長期保管（版管理）  
  - 方針：会話と最終決定はZulip、経緯記録/証跡はGitLab。n8n が会話→起票/要約→記録を補助する

- **クラウド側ログ分析基盤（Athena/Grafana） vs GitLab（起票/追跡）**  
  - ログ分析：検索・可視化・集計は Athena/Grafana を正とする  
  - 起票/追跡：対応が必要な事象は GitLab Issue に集約し、Zulip に通知する  
  - 方針：分析はクラウド側、運用アクションはGitLab/Zulipへ寄せる（データの二重管理を避ける）

- **n8n vs Exastro ITA vs GitLab（自動化/オーケストレーション）**  
  - n8n：API連携・業務フロー自動化に強いワークフローオーケストレータ（監視イベント連携、CMDB更新などの橋渡し役）  
  - Exastro ITA：構成作業自動実行に特化したITオートメーション  
  - GitLab：Dev/CI/CDの統合ツール（ビルド/テスト/デプロイ）  
  - 方針：ビルド/テスト/デプロイはGitLab、構成作業はExastro ITA、両者と他システムをつなぐ業務フローはn8nが担当

- **Zulip vs 他チャット/チケット機能**  
  - Zulip：トピックベースのスレッドに強いOSSチャット。サービスデスクやインシデント対応のフロント窓口に利用  
  - チケット/状態管理はGitLab サービス管理（Issue/CMDB）、作業実行はExastro/GitLabに分担  
  - 追加のチャット/チケット基盤は持たず、会話チャネルはZulipに集約  
  - 方針：チャットは窓口とコミュニケーションに集中させ、状態管理や実行は他ツールに委任

この表は「ツールをカテゴリごとに閉じる」前提での割り当てであり、他カテゴリのツールを併用する方針に変える場合は要件に応じて再設計する。

---

## チケット管理の使い分け

- 推奨の主担当：GitLab サービス管理プロジェクト（Issue/CMDB）をチケット台帳の中心にし、インシデント／サービス要求／変更／問題をここで一元管理。SLA・ワークフロー・CI紐付けを活用。
- 開発タスク/不具合：技術管理プロジェクトの GitLab Issue/Epic/MR を開発側の作業チケットとして使用。運用系はサービス管理、開発系は技術管理で分離し、必要に応じて相互リンクする。
- 自動起票：クラウド側ログ通知基盤（CloudWatch→*（Webhook）→n8n）からのイベントは n8n で受け、GitLab Issue 起票と Zulip 通知を標準化する。
- チャネル分担：状態管理/承認/証跡は GitLab、コミュニケーションは Zulip に集約し、n8n が両者の連携を担う。
- 役割/RACI：役割別の使い方と責任分界（RACI）はサービス管理テンプレートを正とする（`scripts/itsm/gitlab/templates/service-management/docs/role_guide.md.tpl` と `scripts/itsm/gitlab/templates/service-management/docs/raci.md.tpl`）。

## 顧客向けポータルからの問い合わせフロー

- 顧客向け窓口：GitLab Issueフォーム（認証が可能な利用者向け）または Zulip（ストリーム/トピック）を入口とする。外部フォームが必要な場合はHTTP POSTで n8n Webhook に送信する。
- 受付：n8n で受信（Webhook または GitLab/Zulip 連携）し、入力チェックとカテゴリ判定を実施。
- 起票：n8n から GitLab サービス管理（CMDB/Issue） にチケット（サービス要求/インシデント等）を自動登録し、受付番号を発行。
- 通知：n8n が受付完了メールを顧客へ送信。社内は Zulip の専用トピックへ通知。
- 対応：担当者は GitLab Issueで進捗/ステータスを管理し、必要なやり取りは Zulip で行う。
- 追跡：ステータス更新時にメールで顧客へ連絡。必要ならポータル側で簡易ステータス表示を GitLab API連携で出す。

## データガバナンス

### アクセス制御（テーブル単位）
- GitLab/Zulip/n8n/Exastro/Grafana/Qdrant は Keycloak（OIDC/SAML）で統合認証し、グループ/ロールでアクセス制御（最小権限）を行う。連携用のservice accountは用途別に分離し、Secrets Manager／SSM パラメータで管理する。
- 運用基盤が接続する Postgres/RDS などでは IAM 認証＋ Keycloak のRBAC方針に合わせたDBロール分離を行い、機微データは最小権限・監査ログ前提で取り扱う（read-only/エクスポート用ロールは別定義）。

### 監査ログの改ざん防止（WORM/S3）
- CloudTrail・RDS Enhanced Monitoring・VPC Flow Logs は専用 S3 バケットへ集約し、Object Lock（WORM）＋バージョニング＋SSE-KMS で改ざんと削除を防ぐ。ログ書き込みはログ発行アカウントの IAM role のみに限り、運用チームには読み取り専用ロールを割り当てる。
- CloudWatch Logs のS3アーカイブ（Athena/Grafana での長期検索・集計用）は対象ロググループを限定し、運用で合意したものだけを出力する（監視参照の導線はGrafanaに統一）。長期保存時は `logs-archive` バケットにライフサイクルで移動し、同様に Object Lock を維持する。

### エクスポート手順
- データエクスポートは GitLab Issue（承認/記録）を起点にし、n8n のワークフローで実行する。対象・期間・利用者・承認IDを記録し、出力先は VPC 内 S3（VPC Endpoint 経由）に限定して監査ログを残す。
- エクスポートファイル（CSV/JSON）は KMS で暗号化し、`aws s3 presign` による期限付きURLで共有するときも転送先とアクセスアカウントを明示。exportable な公開データ以外は事前に `pii_redaction_policy` を通してマスキングし、LLM などに送る前にデータ分類ポリシーをチェックする。

### データ分類（PII／機微／公開）
- データ分類は「PII」「機微／特権」「公開」の三層で定義。PII（従業員メール/顧客IDなど）は Keycloak（アイデンティティ）および GitLab（必要最小の連絡/記録。原則はConfidential Issue）で管理し、Zulip に貼り付けない。n8n で扱う際は `pii_redaction_policy` を使ってマスキングしてから通知/連携する。
- 公開データ（サービスカタログや一般KPI）は GitLab（公開リポジトリ/Pages 等）で管理し、公開指定以外のデータを誤って公開しないよう変更Issue/承認フローで分類変更をレビューする。

---

## レポート/分析機能の位置づけ

- クラウド側ログ分析基盤（Athena/Grafana）：ログ/メトリクスの可視化・検索・集計の中心。
- GitLab サービス管理（CMDB/Issue）：チケット/CMDB/変更履歴の集計と、意思決定の根拠（Issue/MR）を参照。
- GitLab Omnibus：Issue/Epic/パイプラインのメトリクス・インサイト。

---

## サービス運用統合レポート（SLA含む）の流し込み

- ソース定義：GitLab サービス管理（CMDB/Issue） のサービス/CIに SLA/OLA 項目（応答/解決目標、稼働率）を持たせ、チケット側で実績（開始/応答/解決/保留時間）を記録。
- 計測・集計：監視指標（稼働率/アラート）を n8n で集計し、チケット実績（MTTA/MTTR、SLA達成/逸脱件数）を GitLab サービス管理から取得して突合。ログ根拠の参照は Athena/Grafana を正とする。
- 反映：n8n で期間別（週次/月次）に集計したサービス別SLA実績を GitLab（サービス管理プロジェクトの `reports/` へのMR、または定例レポートIssue）へ反映し、Zulipへ通知する。
- レポート内容：サービス単位の稼働率、応答/解決時間の目標と実績、SLA逸脱件数と要因、主要インシデントのリンク（GitLab Issueへの参照）、改善アクションの進捗（GitLab課題へのリンク）。

---

## ツール別「利用しない機能」と根拠

| ツール | ツールの保持する機能の中で利用しない機能 | ツールの保持する機能の中で利用しない根拠 |
| --- | --- | --- |
| n8n | 監視そのもの（メトリクス収集/可視化）、インシデント詳細分析、非定型要求の調整 | 監視はクラウドネイティブ基盤に統一し、n8nはイベント処理や自動連携に限定。分析・判断は人や他システムで行うため |
| Qdrant | 正式な台帳/文書の保管、承認・変更履歴の正、権限管理の中核 | 正はGitLab（CMDB/Issue/リポジトリ）。Qdrantは検索性向上のための派生インデックスに限定し、再生成可能なデータとして扱うため |
| Zulip | 正式な仕様・設計・BCP保管、チケット状態管理、既知エラーDB | 長期ナレッジや台帳はGitLabに集約し、Zulipは窓口とリアルタイムコミュニケーションに専念するため |
| GitLab サービス管理（CMDB/Issue） | チャットUI、ログ検索/可視化、構成作業の実行 | チャットはZulip、ログ分析はAthena/Grafana、構成作業の実行はExastro ITAに分担し、GitLabは台帳/承認/証跡に特化するため |
| GitLab | チャット/監視/CMDB自動収集の常時稼働バス用途 | 会話・通知はZulip/n8n、監視はクラウド側、CMDB収集はExastro/クラウドAPI→n8nで担い、GitLabは版管理とCI/CDに集中するため |
| Exastro ITA Web | プロジェクト管理・要件管理用途、CMDB台帳用途 | 要件/承認は他プラクティクスで扱い、Exastroは構成作業自動実行に専念するため |
| Exastro ITA API | Web UI操作の代替としての常用 | 手動はWeb、自動はAPIに経路を分離し権限制御を簡素化するため |
| Keycloak | アプリ固有の細粒度権限モデル | 細粒度権限は各アプリ側に任せ、Keycloakは統合認証と粗いロールに限定する方針のため |
| クラウド側ログ分析基盤（Athena/Grafana） | チケット管理、承認/証跡、対話窓口 | 起票・承認・証跡はGitLab、コミュニケーション/最終決定はZulipに集約し、分析基盤は分析に専念させるため |
| クラウド側ログ通知基盤（CloudWatch→*（Webhook）→n8n） | 複雑な業務判断、長期台帳 | 判断/最終決定はZulip、承認/証跡はGitLab、処理はn8nに寄せ、通知基盤は配送に専念させるため |
