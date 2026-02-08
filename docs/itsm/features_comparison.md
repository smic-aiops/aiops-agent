# 市販ITSM との比較（機能対照表）

本ドキュメントは、市販ITSM を基準に、本リポジトリの「AIOps Agent サービス運用基盤（OSS 統合）」で **どこまで代替/実現できているか**、および **未提供の場合の実装案**を整理した比較表です。

前提（本リポジトリ側の主要要素）:
- 認証/認可: Keycloak（OIDC）
- 連携/自動化: n8n（Webhook/スケジュール/外部API連携）
- 記録/起票/CMDB（正）: GitLab（Issue/Repo/`cmdb/`）
- コミュニケーション: Zulip
- 構成自動化/構成収集: Exastro ITA
- 監視参照/可視化: Grafana（CloudWatch/Athena 等）
- ログ/イベント: CloudWatch / EventBridge（＋n8n）
- ベクトル検索: Qdrant（RAG/類似検索）
- ポータル/コントロールサイト: Sulu（CloudFront + S3）
- データストア/秘匿情報: RDS(PostgreSQL) / EFS / SSM・Secrets Manager

判定:
- `○`: 概ね提供（運用可能な形で揃っている）
- `△`: 一部提供（要設計/要拡張、代替実装で成立）
- `×`: 未提供（別コンポーネント追加または新規実装が必要）

> 注意: 市販ITSM はエディション/プラグイン/契約内容により提供範囲が変わります。本表は「代表的な実装パターン」を機能領域として列挙しています（完全な網羅＝全プラグイン/全業界ソリューションまでの列挙は現実的に不可能なため）。

| # | 領域 | 機能/モジュール | 本リポジトリ（現状の相当） | 有無 | 未提供/不足時の実装案（このレポ拡張の方向性） |
|---:|---|---|---|:---:|---|
| 1 | プラットフォーム | 統合データモデル（テーブル/参照/ACL） | GitLab（Issue/Repo）+ RDS（アプリ用）+ SSM（設定/秘密） | 市販ITSM: ○<br>本システム: △ | 「ITSM コア用の正規化DB（例: Postgres）」を追加し、GitLab は外部公開/変更管理に寄せる（双方向同期は n8n）。 |
| 2 | プラットフォーム | フォーム/リストUI（レコード中心UI） | GitLab Issue/Project UI、Zulip、各OSS UI（n8n/Grafana 等） | 市販ITSM: ○<br>本システム: △ | 「ITSM 画面/UI（例: Odoo のヘルプデスク、または独自Web）」を追加し、Keycloak で統合。 |
| 3 | プラットフォーム | ローコード（App Engine / Studio） | n8n ワークフロー（ローコード自動化） | 市販ITSM: △<br>本システム: △ | CRUD アプリを作る場合は「Odoo」や「軽量CRUD（Retool 相当のOSS）」を追加。 |
| 4 | プラットフォーム | サーバーサイドスクリプト（Business Rule 等） | n8n（条件分岐/コードノード）+ GitLab CI（任意） | 市販ITSM: ○<br>本システム: △ | 「共通ルール層」を作るなら、`apps/*` にライブラリ化（TypeScript/Python）して n8n から呼ぶ。 |
| 5 | プラットフォーム | Flow Designer / Workflow | n8n（Webhook/スケジューラ/外部API） | 市販ITSM: ○<br>本システム: ○ | 追加要望は `apps/*/workflows/` に標準化（OQ を必ず追加）。 |
| 6 | プラットフォーム | IntegrationHub（Spoke/コネクタ） | n8n コネクタ + カスタムHTTP | 市販ITSM: △<br>本システム: △ | 主要SaaS向けに「再利用可能な n8n サブワークフロー（spoke相当）」を整備。 |
| 7 | プラットフォーム | REST API（テーブルAPI等） | n8n Webhook（API提供）+ GitLab API | 市販ITSM: ○<br>本システム: △ | 「ITSM API（OpenAPI）」を定義し、n8n はオーケストレーションへ寄せ、API本体は別サービス化。 |
| 8 | プラットフォーム | イベント/メッセージ基盤（内部イベント） | EventBridge/CloudWatch + n8n | 市販ITSM: ○<br>本システム: △ | 追跡性が必要なら「イベントスキーマ（JSON Schema）+ 署名 + ID一貫性」を導入。 |
| 9 | プラットフォーム | 監査ログ（フィールド変更履歴） | GitLab（MR/Issue履歴）+ AWSログ（CloudTrail/CloudWatch） | 市販ITSM: ○<br>本システム: △ | 「ITSMコアDB」を持つ場合は、変更履歴テーブル + 監査ログの外部転送を追加。 |
| 10 | プラットフォーム | 権限制御（ACL/フィールドACL） | Keycloak（認証）+ 各OSSのRBAC | 市販ITSM: ○<br>本システム: △ | 「統一RBAC」を作るなら、Keycloak ロール→各サービスの権限同期（SCIM/プロビジョニング）を整備。 |
| 11 | プラットフォーム | マルチテナント（Domain Separation） | Keycloak realm + tfvars の realm 分離 | 市販ITSM: △<br>本システム: △ | GitLab グループ/プロジェクト分離をテンプレート化し、n8n は realm ごとに環境注入を標準化。 |
| 12 | プラットフォーム | モバイル（Now Mobile） | なし（各OSSのWeb UI） | 市販ITSM: △<br>本システム: × | 「PWA（Sulu）」+「通知（メール/Push）」、またはモバイル対応のチケットUI（OSS）を追加。 |
| 13 | プラットフォーム | サービス/セルフポータル（Service Portal） | Sulu（Control Site）+ GitLab（カタログ/ナレッジ） | 市販ITSM: △<br>本システム: △ | Sulu に「申請フォーム（OIDC）」を実装し、申請は n8n→GitLab Issue/ITSM DBへ。 |
| 14 | プラットフォーム | ナレッジ（Knowledge Base） | GitLab（Wiki/Repo）+ Qdrant（検索補助） | 市販ITSM: ○<br>本システム: △ | ナレッジ分類/承認/有効期限を GitLab テンプレ/ラベルで標準化（必要なら専用KB OSS追加）。 |
| 15 | プラットフォーム | レポーティング（Reports） | Grafana + GitLab（集計、例: `apps/gitlab_issue_metrics_sync`） | 市販ITSM: ○<br>本システム: △ | 主要KPIは「Issueメトリクス集計（`apps/gitlab_issue_metrics_sync`）」を拡張して一元化。 |
| 16 | プラットフォーム | Performance Analytics（時系列KPI/目標） | Grafana（時系列）+ S3/Athena（集計） | 市販ITSM: △<br>本システム: △ | 「KPIデータマート（Athena/Glue）」を定義し、ETL を n8n かバッチで実装。 |
| 17 | セキュリティ | SSO（SAML/OIDC） | Keycloak（OIDC） | 市販ITSM: △<br>本システム: ○ | SAML が必要なら Keycloak 側で有効化し、各OSSへ連携。 |
| 18 | セキュリティ | MFA | Keycloak（設定次第） | 市販ITSM: △<br>本システム: △ | Keycloak の MFA（TOTP/WebAuthn）を標準化し、ロール別に強制。 |
| 19 | セキュリティ | SCIM/自動プロビジョニング | なし | 市販ITSM: △<br>本システム: × | Keycloak + SCIM ブリッジ（または各OSS API）でユーザー/グループ同期を実装。 |
| 20 | セキュリティ | データ暗号化（at rest/in transit） | AWS（ACM/TLS, RDS/EFS/S3暗号化） | 市販ITSM: ○<br>本システム: △ | KMSキー分離、秘密情報は SSM/Secrets Manager を必須化（tfvars平文禁止を強制）。 |
| 21 | セキュリティ | 監査/コンプライアンス（監査証跡） | `evidence/` + Gitの変更管理 + AWSログ | 市販ITSM: ○<br>本システム: △ | 「監査証跡インデックス」を強化し、重要操作（承認/変更）を一意IDで追跡。 |
| 22 | ITSM | Incident Management（インシデント） | GitLab Issue + Zulip + n8n（通知/起票、例: `apps/zulip_gitlab_issue_sync`） | 市販ITSM: ○<br>本システム: △ | テンプレ/ラベル/状態遷移（SLA含む）を標準化し、Webhook→自動起票を拡充。 |
| 23 | ITSM | Major Incident Management | GitLab（運用で代替） | 市販ITSM: △<br>本システム: △ | 「メジャーインシデント用Issueタイプ」+「専用Zulipストリーム」+「コミュニケーションタイムライン自動生成」を実装。 |
| 24 | ITSM | Problem Management（問題） | GitLab Issue（問題/既知エラー）+ Seed | 市販ITSM: ○<br>本システム: △ | `apps/aiops_agent/scripts/import_aiops_problem_management_seed.sh` を拡張し、RCAテンプレ/リンクを強制。 |
| 25 | ITSM | Known Error Database（KEDB） | GitLab（Issue/Wiki） | 市販ITSM: ○<br>本システム: △ | 既知エラーを `cmdb/known_errors/` 等に正規化し、n8n で検索/提案（Qdrant）を強化。 |
| 26 | ITSM | Change Management（変更/CAB） | GitLab（MR/Issue/承認）+ n8n ゲート | 市販ITSM: ○<br>本システム: △ | 「CAB承認フロー」を n8n で実装し、承認証跡を `evidence/` に自動保存。 |
| 27 | ITSM | Release Management（リリース） | GitLab（マイルストーン/Issue） | 市販ITSM: ○<br>本システム: △ | リリースカレンダ→外部カレンダー同期（n8n）と、リリース条件（テスト結果）自動チェックを追加。 |
| 28 | ITSM | Request Fulfillment（サービス要求） | `apps/workflow_manager`（カタログAPI）+ GitLab | 市販ITSM: ○<br>本システム: △ | Sulu ポータルのフォーム→カタログAPI→実行フロー（n8n）を標準提供。 |
| 29 | ITSM | Service Catalog（カタログ） | `apps/workflow_manager`（Workflow Manager） + GitLab（カタログ同期） | 市販ITSM: ○<br>本システム: △ | カタログ定義（YAML）→GitLab表示→Suluフォーム生成→n8n実行、をテンプレ化。 |
| 30 | ITSM | 承認（Approvals） | n8n +（会話: Zulip / 証跡: DB+GitLab） | 市販ITSM: ○<br>本システム: △ | `apps/aiops_agent` の承認導線（`/webhook/approval/click`）を前提に、Zulip 上では承認結果を `/decision` として扱い、`/decisions` で履歴サマリを参照できるよう拡張（証跡は `aiops_approval_history` と GitLab へ）。 |
| 31 | ITSM | SLA/OLA/UC | なし（運用で代替） | 市販ITSM: ○<br>本システム: × | GitLab Issue の `created_at`/ラベルからSLA計測→Grafana可視化→期限通知（n8n）を実装。 |
| 32 | ITSM | エスカレーション（自動割当/通知） | n8n（通知/分岐） | 市販ITSM: △<br>本システム: △ | 当番表（On-call）を外部（Google Calendar等）から取り込み、Zulip/メールへエスカレを自動化。 |
| 33 | ITSM | インシデント⇄CI紐付け | GitLab CMDB（`cmdb/`）+ Issueリンク | 市販ITSM: ○<br>本システム: △ | CI参照を「CI ID（固定）」に統一し、Issueテンプレに必須項目として組み込む。 |
| 34 | ITSM | Knowledge / FAQ 連携 | GitLab + Qdrant（例: `apps/gitlab_issue_rag`） | 市販ITSM: ○<br>本システム: △ | 「解決時のナレッジ化」ワークフロー（n8n）を追加し、レビュー/承認プロセスを実装。 |
| 35 | ITSM | サーベイ/CSAT | なし | 市販ITSM: △<br>本システム: × | 受付完了/解決時にアンケート送付（n8n）→結果を GitLab/DB に保存→Grafana。 |
| 36 | ITSM | サービスカレンダー/凍結期間 | GitLab（マイルストーン/Issue） | 市販ITSM: △<br>本システム: △ | 凍結期間を `cmdb/calendar/` で管理し、変更作成時に自動チェック（n8n）。 |
| 37 | ITSM | 通知（Email/SMS/Chat） | Zulip（例: `apps/gitlab_mention_notify`, `apps/gitlab_push_notify`, `apps/zulip_stream_sync`） +（必要に応じてSMTP） | 市販ITSM: △<br>本システム: △ | SMS/電話が必要なら外部（Twilio等）連携の n8n spoke を追加。 |
| 38 | CMDB | CMDB（CI管理） | GitLab `cmdb/` を正にする方針 | 市販ITSM: ○<br>本システム: △ | CIスキーマ（JSON Schema）と検証（CI/CD）を整備し、整合性を自動テスト。 |
| 39 | CMDB | CSDM（サービス/アプリ/CIモデル） | `docs/itsm/itsm-platform.md` の整理 | 市販ITSM: △<br>本システム: △ | CSDM相当のディレクトリ/スキーマをテンプレ化（例: `cmdb/services/`, `cmdb/apps/`, `cmdb/cis/`）。 |
| 40 | CMDB | CIリレーション（依存関係） | GitLab（YAML/Markdown） | 市販ITSM: ○<br>本システム: △ | リレーションをグラフ化（Graphviz/Mermaid生成）し、Sulu/Grafanaで参照可能にする。 |
| 41 | CMDB | 自動ディスカバリ（Discovery） | Exastro ITA + AWS API（想定） | 市販ITSM: △<br>本システム: △ | AWS Config/SSM Inventory を併用し、収集→正規化→GitLab CMDBへ同期するn8nを追加。 |
| 42 | CMDB | Service Mapping（アプリ依存関係） | 部分的（設計/手動） | 市販ITSM: △<br>本システム: × | トレース/APM（OpenTelemetry）やVPC Flow Logsから依存推定→CMDBへ提案、を段階導入。 |
| 43 | CMDB | Reconciliation（複数ソース統合） | n8n（差分/正規化の実装余地） | 市販ITSM: △<br>本システム: △ | 「ソース優先順位」「衝突解決ルール」をYAML化し、同期フローで一貫適用。 |
| 44 | ITOM | Event Management（イベント→アラート） | CloudWatch/EventBridge + n8n（例: `apps/cloudwatch_event_notify`） | 市販ITSM: △<br>本システム: △ | 受信正規化（重複排除/抑止）と、重大度マトリクス（ルール）を標準化。 |
| 45 | ITOM | インシデント自動起票 | `apps/cloudwatch_event_notify` 等 | 市販ITSM: △<br>本システム: △ | 監視ルール別に「起票先（GitLabプロジェクト/ラベル）」を管理し、テンプレで拡張。 |
| 46 | ITOM | アラート相関/ノイズ削減（AIOps） | なし（部分は実装可能） | 市販ITSM: △<br>本システム: × | 相関ルール（時間窓/同一CI/同一症状）をn8nで実装→重複を束ねてIssue化。 |
| 47 | ITOM | 異常検知（メトリクス） | CloudWatch/Grafana（アラーム） | 市販ITSM: △<br>本システム: △ | 高度化は「Prometheus + Alertmanager」追加、または CloudWatch Anomaly Detection を利用。 |
| 48 | ITOM | ログ管理（集約/検索） | CloudWatch + S3/Athena + Grafana（方針） | 市販ITSM: △<br>本システム: △ | ログ標準（JSON/TraceID）と、Athenaテーブル/保持期間のテンプレ化を進める。 |
| 49 | ITOM | APM/分散トレーシング | 一部（AWS X-Ray の気配） | 市販ITSM: △<br>本システム: △ | OpenTelemetry を標準化し、X-Ray/Tempo 等へ送る（Grafanaで可視化）。 |
| 50 | ITOM | Runbook Automation | n8n + Exastro ITA | 市販ITSM: △<br>本システム: △ | 「Runbook→実行（承認ゲート付き）」をカタログ化し、証跡を `evidence/` に自動保存。 |
| 51 | ITOM | オーケストレーション（遠隔実行） | Exastro ITA（構成自動化） | 市販ITSM: △<br>本システム: △ | 変更管理（GitLab）と実行（Exastro）のブリッジを強化（承認済みのみ実行）。 |
| 52 | ITOM | On-call スケジューリング | なし | 市販ITSM: △<br>本システム: × | 当番表を GitLab（YAML）か外部カレンダーで管理し、n8n で呼び出してエスカレ。 |
| 53 | ITOM | インフラ自動停止（コスト最適化） | `service_control_schedule_*`（Terraform） | 市販ITSM: △<br>本システム: △ | 運用UI（Sulu）から「例外/延長」できるようにし、承認付きで変更する。 |
| 54 | ITAM | ハードウェア資産管理（HAM） | GitLab CMDB（台帳で代替） | 市販ITSM: △<br>本システム: △ | 専用OSS（Snipe-IT/GLPI等）を追加し、正はOSSに置きGitLabへ同期（または逆）。 |
| 55 | ITAM | ソフトウェア資産管理（SAM） | なし | 市販ITSM: △<br>本システム: × | ライセンス台帳（YAML/DB）+ 利用実績収集（SSM/EDR/MDM）→差分検知（n8n）を実装。 |
| 56 | ITAM | 契約/保守期限管理 | なし | 市販ITSM: △<br>本システム: × | 契約台帳を GitLab（`cmdb/contracts/`）で管理し、期限通知（n8n）を実装。 |
| 57 | ITAM | 調達（Procurement） | Odoo（ERP要素、任意） | 市販ITSM: △<br>本システム: △ | Odoo の調達/在庫を使うか、軽量に GitLab Issue でワークフロー化。 |
| 58 | SecOps | Security Incident Response（SIR） | GitLab Issue（セキュリティ用で代替） | 市販ITSM: △<br>本システム: △ | セキュリティ用テンプレ/ラベル/権限分離（Keycloak/Group）を整備し、証跡を強化。 |
| 59 | SecOps | Vulnerability Response | GitLab（Dependabot相当/CI）次第 | 市販ITSM: △<br>本システム: △ | SBOM生成 + 脆弱性スキャン結果→n8n→Issue自動作成/優先度付け、を実装。 |
| 60 | SecOps | 脅威インテリジェンス統合 | なし | 市販ITSM: △<br>本システム: × | 外部TIフィード→n8n→重要度でアラート/ナレッジ化、を追加。 |
| 61 | GRC | ポリシー/コントロール管理 | `docs/`（CSA/NIST AI RMF 前提） | 市販ITSM: △<br>本システム: △ | GitLab で「ポリシー as code（YAML）」+ レビュー/承認フロー、証跡リンクを標準化。 |
| 62 | GRC | リスク管理（Risk） | `docs/03` 想定（運用で整備） | 市販ITSM: △<br>本システム: △ | リスク台帳を GitLab Issue/`docs/03` に集約し、定期レビュー（n8nリマインド）を追加。 |
| 63 | GRC | 監査管理（Audit Management） | `evidence/` + 変更管理（Git） | 市販ITSM: △<br>本システム: △ | 監査要求→証跡収集→提出物生成（n8n）をテンプレ化。 |
| 64 | DevOps | DevOps（CI/CD連携） | GitLab（強い） | 市販ITSM: △<br>本システム: ○ | 変更管理（RFC）とパイプライン結果の紐付けをテンプレ化。 |
| 65 | DevOps | Change Automation（デプロイ連携） | Exastro + GitLab + n8n | 市販ITSM: △<br>本システム: △ | 承認済み変更のみデプロイ可能な「ゲート」を厳格化（署名/HMAC/二重確認）。 |
| 66 | DevOps | 変更の可観測性（変更起因分析） | CloudWatch/Grafana + GitLab（通知: `apps/gitlab_push_notify`） | 市販ITSM: △<br>本システム: △ | デプロイイベントを EventBridge に記録し、アラート相関に使えるようにする。 |
| 67 | SPM | プロジェクト/ポートフォリオ管理 | GitLab（Issue/Milestone） | 市販ITSM: △<br>本システム: △ | 組織横断のポートフォリオが必要なら Odoo/外部PPM を追加し、同期（n8n）。 |
| 68 | Agile | アジャイル（Scrum/Kanban） | GitLab Boards | 市販ITSM: △<br>本システム: △ | 市販ITSM Agile 相当は GitLab で運用し、ITSMとリンク（Issueリンク/ラベル規約）。 |
| 69 | CSM | Customer Service Management（ケース） | Zulip（会話）+ GitLab（Issue） | 市販ITSM: △<br>本システム: △ | 外部顧客向けは「Zammad/OTRS等」を追加し、GitLab/CMDBと連携。 |
| 70 | HR | HR Service Delivery | なし | 市販ITSM: △<br>本システム: × | 人事ワークフローは専用OSS/既存HRを採用し、IDはKeycloakで統合。 |
| 71 | FSM | Field Service Management | なし | 市販ITSM: △<br>本システム: × | 現場作業が必要なら専用FSMを採用し、チケット/資産/在庫のみ連携（n8n）。 |
| 72 | Workplace | Workplace/Facilities Service | なし | 市販ITSM: △<br>本システム: × | 施設管理は別システムを採用し、申請/承認/通知のみ共通化（n8n）。 |
| 73 | AI | Virtual Agent（チャットボット） | Zulip bot + `apps/aiops_agent`（LLM） | 市販ITSM: △<br>本システム: △ | 「対話のガードレール（AIS）」+「ツール権限」+「監査ログ」を整備して運用レベルへ。 |
| 74 | AI | Now Assist（要約/分類/提案） | `apps/aiops_agent`（設計思想） | 市販ITSM: △<br>本システム: △ | 代表ユースケース（要約/初動手順提案/次アクション）をワークフロー化し、評価（DQ）を追加。 |
| 75 | AI | 予測分類（カテゴリ/割当） | なし | 市販ITSM: △<br>本システム: × | 学習用データ（Issue履歴）を整備し、軽量モデル（またはLLM）で分類→人レビュー→自動化を段階導入。 |
| 76 | AI | AI Search（ナレッジ検索） | Qdrant（RAG、例: `apps/gitlab_issue_rag`）+ GitLab | 市販ITSM: △<br>本システム: △ | 検索対象（Runbook/FAQ/CMDB/Issue）を定義し、インデックス更新のSLOを決める。 |
| 77 | 自動化 | RPA（UI自動操作） | なし | 市販ITSM: △<br>本システム: × | Playwright/Robot Framework を追加し、実行は GitLab CI or ECS バッチ、統制は n8n で。 |
| 78 | 自動化 | Process Mining | なし | 市販ITSM: △<br>本システム: × | イベントログ（要求→承認→完了）を整形し、PM4Py等で分析→改善提案をGitLabで運用。 |
| 79 | データ | データ連携（ETL/Transform） | n8n（ETL的に利用） | 市販ITSM: △<br>本システム: △ | 大規模ETLは Glue/Lambda へ分離し、n8n はオーケストレーション中心にする。 |
| 80 | 運用 | バックアップ/リストア | AWS（RDS/EFS/S3） | 市販ITSM: △<br>本システム: △ | バックアップ手順/演習（復旧テスト）を OQ/PQ として体系化し、証跡を `evidence/` に保存。 |
| 81 | IaC（AWS） | AWS 基盤を Terraform で丸ごと再現（VPC/RDS/ECS/WAF/CF/ACM/Route53 等） | `main.tf`, `modules/stack/` | 市販ITSM: △<br>本システム: ○ | Terraform/CloudFormation 等を併用（市販ITSM は IaC の実行・統制側に寄せる）。 |
| 82 | IaC（AWS） | State をローカル運用（`terraform.tfstate`）する前提と注意喚起 | `terraform.tfstate`, `docs/infra/README.md` | 市販ITSM: △<br>本システム: ○ | 市販ITSM 外で state 管理（S3+Lock 等）。市販ITSM は変更申請/承認の連携で利用。 |
| 83 | IaC（AWS） | tfvars を用途別に分割して運用（env/itsm/apps） | `terraform.env.tfvars`, `terraform.itsm.tfvars`, `terraform.apps.tfvars` | 市販ITSM: △<br>本システム: ○ | 変数/設定管理は外部（Git/Secrets）に置き、市販ITSM は参照・監査導線に寄せる。 |
| 84 | IaC（AWS） | tfvars 分割前提の `fmt/validate/plan/apply` オーケストレーション | `scripts/plan_apply_all_tfvars.sh` | 市販ITSM: △<br>本システム: ○ | CI/CD（GitLab CI 等）で実行し、市販ITSM Change と紐付ける。 |
| 85 | IaC（AWS） | 初回 apply 後の outputs を tfvars へ“安定化”反映 | `scripts/infra/update_env_tfvars_from_outputs.sh` | 市販ITSM: △<br>本システム: ○ | IaC 側の運用設計。市販ITSM ではなく CI/CD スクリプト領域。 |
| 86 | IaC（AWS） | RDS master パスワードを tfvars に反映（コミット禁止前提） | `scripts/infra/refresh_rds_master_password_tfvars.sh` | 市販ITSM: △<br>本システム: ○ | Secrets 管理で一元化（市販ITSM では Secrets の実体は持たない想定）。 |
| 87 | IaC（AWS） | DB パスワードを各サービス用 SSM パラメータへ同期 | `scripts/infra/update_rds_app_passwords_from_output.sh` | 市販ITSM: △<br>本システム: ○ | AWS 側で Secrets/SSM を管理し、市販ITSM は参照名や回転手順の管理に寄せる。 |
| 88 | IaC（AWS） | OIDC 有効化フラグを tfvars に自動追記＋`refresh-only` まで実行 | `scripts/itsm/update_terraform_itsm_tfvars_auth_flags.sh` | 市販ITSM: △<br>本システム: ○ | IaC の補助。市販ITSM は承認・記録（Change）へ寄せる。 |
| 89 | IaC（AWS） | “サービス自動停止”のスケジュール制御（コスト最適化）を IaC で提供 | `terraform.itsm.tfvars`（`service_control_schedule_*`） | 市販ITSM: △<br>本システム: ○ | 市販ITSM ではスケジュール管理はできるが、クラウド停止制御は外部実装が必要。 |
| 90 | IaC（AWS） | Control Site を CloudFront + S3（OAC）で配信する設計 | `modules/stack/`（CloudFront/S3） | 市販ITSM: △<br>本システム: ○ | 市販ITSM のポータルではなく、AWS 側でホスティング。 |
| 91 | IaC（AWS） | WAF を CloudFront と ALB に適用する IaC | `modules/stack/`（WAF/ALB/CF） | 市販ITSM: △<br>本システム: ○ | セキュリティ制御はクラウド側（市販ITSM は関与しない）。 |
| 92 | プラットフォーム（OSSホスティング） | OSS（Keycloak/Zulip/GitLab/n8n/Grafana 等）を ECS で動かす“自前ITSM基盤” | `modules/stack/ecs_*.tf` | 市販ITSM: △<br>本システム: ○ | 市販ITSM は SaaS/製品として提供。自前ホスティングのOSS統合は別アーキテクチャ。 |
| 93 | プラットフォーム（OSSホスティング） | realm（テナント）単位で環境変数/URL を分離する前提の設計 | `docs/apps/README.md`（realm）, `terraform.*.tfvars` | 市販ITSM: △<br>本システム: ○ | 市販ITSM はインスタンス/ドメイン分離で別物。OSS側の realm 分離は外部設計。 |
| 94 | スクリプト（共通） | スクリプトが `terraform output` から `AWS_PROFILE` を自動解決する共通設計 | `scripts/lib/aws_profile_from_tf.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM は AWS CLI 実行環境ではない。外部実行（Runner/CI）で担う。 |
| 95 | スクリプト（共通） | `name_prefix`/realm 解決などのスクリプト共通ライブラリ | `scripts/lib/name_prefix_from_tf.sh`, `scripts/lib/realms_from_tf.sh` | 市販ITSM: △<br>本システム: ○ | 同等は 市販ITSM Script ではなく外部運用コード。 |
| 96 | コンテナ運用（イメージ/ECS） | upstream コンテナイメージをローカルへキャッシュする pull スクリプト群 | `scripts/itsm/*/pull_*.sh`, `images/` | 市販ITSM: △<br>本システム: ○ | 市販ITSM に“イメージキャッシュ”概念はない。コンテナ運用は外部。 |
| 97 | コンテナ運用（イメージ/ECS） | ECR へ build/push するスクリプト群（各サービス分） | `scripts/itsm/*/build_and_push_*.sh` | 市販ITSM: △<br>本システム: ○ | CI/CD の領域。市販ITSM DevOps 連携は“連携/ゲート”であって build/push は外部。 |
| 98 | コンテナ運用（イメージ/ECS） | `IMAGE_ARCH` 等でマルチアーキ対応を運用スクリプトに組み込み | `scripts/itsm/**` | 市販ITSM: △<br>本システム: ○ | コンテナ基盤の運用事項であり、市販ITSM 標準機能ではない。 |
| 99 | コンテナ運用（イメージ/ECS） | ECS の force-new-deploy を叩く redeploy スクリプト群 | `scripts/itsm/*/redeploy_*.sh`, `scripts/itsm/run_all_redeploy.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM から実行するなら外部API呼び出し/ジョブが必要。 |
| 100 | n8n 運用 | n8n の暗号鍵を EFS から復元して tfvars/SSM と整合させる | `scripts/itsm/n8n/restore_n8n_encryption_key_tfvars.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM ではなく n8n/EFS/AWS の運用課題。 |
| 101 | n8n 運用 | n8n 初回 owner セットアップを自動復旧する | `scripts/itsm/n8n/ensure_n8n_owner.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM のユーザー/ロールとは無関係。n8n 運用の自動化。 |
| 102 | GitLab 運用 | GitLab 管理者トークンを“コンテナ内”で発行し tfvars へ反映 | `scripts/itsm/gitlab/refresh_gitlab_admin_token.sh` | 市販ITSM: △<br>本システム: ○ | 外部 GitLab 運用。市販ITSM 側に同等はない。 |
| 103 | GitLab 運用 | GitLab グループ/初期プロジェクトを realm 単位でブートストラップ | `scripts/itsm/gitlab/itsm_bootstrap_realms.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM ではなく GitLab の初期設定自動化。 |
| 104 | GitLab 運用 | GitLab グループの Webhook secrets を更新・同期 | `scripts/itsm/gitlab/refresh_gitlab_webhook_secrets.sh` | 市販ITSM: △<br>本システム: ○ | 同等は外部 GitLab の管理。 |
| 105 | GitLab 運用 | GitLab を EFS にミラーし、RAG/インデックスへ流す運用スクリプト | `scripts/itsm/gitlab/start_gitlab_efs_mirror.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM の KB/検索は別系統。GitLab→EFS→検索基盤は外部実装。 |
| 106 | GitLab 運用 | GitLab→EFS→Qdrant のパイプライン状態チェック | `scripts/itsm/gitlab/check_gitlab_efs_rag_pipeline.sh` | 市販ITSM: △<br>本システム: ○ | 検索基盤の運用は外部。 |
| 107 | RAG/検索基盤 | Qdrant を n8n の realm ごとサイドカーで起動する設計 | `modules/stack/ecs_tasks.tf`（Qdrant） | 市販ITSM: △<br>本システム: ○ | 市販ITSM の AI Search とは別。自前ベクトルDB運用は外部。 |
| 108 | apps デプロイ（n8n） | apps のデプロイ＝n8n ワークフロー JSON 同期、という運用モデル | `docs/apps/README.md` | 市販ITSM: △<br>本システム: ○ | 市販ITSM は Flow Designer 等。n8n の JSON 同期は外部。 |
| 109 | apps デプロイ（n8n） | 複数アプリのワークフロー同期を一括実行 | `scripts/apps/deploy_all_workflows.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM では外部“ワークフロー配布”という概念がない。 |
| 110 | apps デプロイ（n8n） | ワークフロー同期の `--dry-run`（書き込み抑止）運用 | `scripts/apps/deploy_all_workflows.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM でやるなら Update Set/CI で別の統制。 |
| 111 | apps デプロイ（n8n） | ワークフロー同期後の自己テスト（`--with-tests`） | `scripts/apps/deploy_all_workflows.sh`, `apps/*/scripts/run_oq.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM の ATF とは別。n8n 側の自己テストは外部。 |
| 112 | apps デプロイ（n8n） | 同期後にワークフローを有効化する運用フラグ | `scripts/apps/deploy_all_workflows.sh` | 市販ITSM: △<br>本システム: ○ | Flow の有効化は 市販ITSM 内で完結するが、n8n は外部。 |
| 113 | apps デプロイ（n8n） | n8n Public API を前提にした “upsert デプロイ” | `apps/*/scripts/deploy_workflows.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM の API は別物。n8n の運用方式は外部。 |
| 114 | apps デプロイ（n8n） | テスト用 Webhook を用意し、同期後に自動叩いて疎通確認 | `apps/cloudwatch_event_notify/README.md`（test webhook） | 市販ITSM: △<br>本システム: ○ | 市販ITSM でもテストは可能だが、“n8n Webhook で試験”は外部。 |
| 115 | apps デプロイ（n8n） | テスト実行時だけ一時的に環境変数をヘッダ注入する仕組み | `apps/cloudwatch_event_notify/README.md`（`x-aiops-env-*`） | 市販ITSM: △<br>本システム: ○ | 市販ITSM では推奨されない（Secrets の扱い）。外部側のテスト設計。 |
| 116 | apps デプロイ（n8n） | 例外時のみ Terraform outputs の secret 参照にフォールバックする運用フラグ | `apps/cloudwatch_event_notify/README.md` | 市販ITSM: △<br>本システム: ○ | 市販ITSM は secrets の正を持たない想定。外部運用のガードレール。 |
| 117 | 検証/証跡（CSA/CSV） | OQ 文書をテンプレ/シナリオから自動生成する仕組み | `scripts/generate_oq_md.sh`, `scripts/apps/create_oq_evidence_run_md.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM ATF/文書化とは別。GxP/CSA 文書生成は外部で実装。 |
| 118 | 検証/証跡（CSA/CSV） | `apps/run_all_oq.sh` のような横断 OQ 実行スクリプト | `apps/run_all_oq.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM で横断検証するなら ATF だが、OSS横断の実行は外部。 |
| 119 | 検証/証跡（CSA/CSV） | 実行ログを JSONL で `evidence/` に保存する共通ヘルパ | `scripts/lib/setup_log.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM の監査ログとは別。外部実行の証跡収集。 |
| 120 | 検証/証跡（CSA/CSV） | `evidence/` ディレクトリを監査/検証の保管場所として同梱 | `evidence/` | 市販ITSM: △<br>本システム: ○ | 市販ITSM はレコードに保持するが、Git 管理の証跡ストレージは別設計。 |
| 121 | CSV/AI ガバナンス | apps README に CSV（GAMP5/CSA）最小ドキュメントフォーマットを固定 | `apps/README.md` | 市販ITSM: △<br>本システム: ○ | 市販ITSM の標準は ITIL 実装。GxP/CSA 文書テンプレは外部で整備が必要。 |
| 122 | CSV/AI ガバナンス | DQ/IQ/OQ/PQ を前提にしたドキュメント/導線を同梱 | `apps/*/docs/{dq,iq,oq,pq}.md` | 市販ITSM: △<br>本システム: ○ | 市販ITSM の文書体系ではなく、規制/監査向けの外部成果物。 |
| 123 | CSV/AI ガバナンス | AI の振る舞い（AIS）を “構成アイテム” として文書化 | `apps/*/docs/cs/ai_behavior_spec.md` | 市販ITSM: △<br>本システム: ○ | 市販ITSM も AI 機能はあるが、AIS のような外部統制文書は別途必要。 |
| 124 | CSV/AI ガバナンス | プロンプト/ポリシーを Git 管理し、realm 別上書きを可能にする | `apps/*/data/`, `apps/*/prompt/`, `apps/*/policy/` | 市販ITSM: △<br>本システム: ○ | 市販ITSM の GenAI 設定とは別。外部LLM運用の構成管理。 |
| 125 | 変更管理（Git） | Git ベースの変更管理導線（差分＝変更記録、証跡とリンク）を前提化 | `docs/change-management.md` | 市販ITSM: △<br>本システム: ○ | 市販ITSM Change とは別系統。統合するなら相互リンク/同期が必要。 |
| 126 | ITSM テンプレ（GitLab） | GitLab テンプレート（general/service/technical）を同梱して“ITSMをGitで起動” | `scripts/itsm/gitlab/templates/` | 市販ITSM: △<br>本システム: ○ | 市販ITSM の ITSM テーブルではなく、GitLab を正にするためのテンプレ資産。 |
| 127 | 運用レポート/補助 | “セットアップ状況サマリ”を自動出力するスクリプト | `scripts/report_setup_status.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM の健康状態ではなく、AWS+OSS の構築状態診断。 |
| 128 | 運用レポート/補助 | “Terraform outputs が取れる前提”を検証するスクリプト | `scripts/verify_apps_scripts_tf_resolution.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM には Terraform outputs の概念がない。 |
| 129 | 運用レポート/補助 | RAG（GitLab→EFS→Qdrant）の状態をレポートする補助スクリプト | `scripts/apps/report_aiops_rag_status.sh` | 市販ITSM: △<br>本システム: ○ | 市販ITSM の AI Search は別。自前 RAG の運用確認は外部。 |
| 130 | 運用レポート/補助 | OpenAI 互換 API 設定（realm別）を tfvars へスケルトン出力する補助 | `scripts/apps/export_aiops_agent_environment_to_tfvars.sh` | 市販ITSM: △<br>本システム: ○ | （例: 市販ITSM の生成AI支援機能）とは別。外部LLMキー/エンドポイント管理は外部で実装。 |

## 付録A: `apps/` 対応（比較表へ統合済み）

`apps/*`（n8n ワークフロー）の個別対応は、上の比較表の各行（例: #15, #22, #28-29, #34, #37, #44-45, #66, #73-76）へ `apps/...` として埋め込み済みです。

## 付録B: 本リポジトリにあって 市販ITSM（標準）にはないもの（比較表へ統合済み）

本付録の 50 項目は、上の比較表へ統合しました（表の末尾側に追加）。

## 補足（本リポジトリ内の根拠になりやすい参照先）

- 方針（ツール分担/データ正）: `docs/itsm/itsm-platform.md`
- ITSM サービスのセットアップ/運用: `docs/itsm/README.md`
- ワークフロー同期（apps デプロイ）: `docs/apps/README.md`
- 監視通知（例）: `apps/cloudwatch_event_notify/README.md`
- サービス要求/カタログ（例）: `apps/workflow_manager/README.md`
