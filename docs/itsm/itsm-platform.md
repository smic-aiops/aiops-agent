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
  - サービス管理/CMDB：**GitLab サービス管理（CMDB/Issue, `cmdb/`）**（現状の正） / **共有 RDS(PostgreSQL) の SoR（`itsm.*`）**（承認・決定・正規化レコードの集約）
  - 構成自動化/構成情報取得：**Exastro ITA Web / Exastro ITA API**（適用は構成情報取得・実行オーケストレーション系に限定）  
  - クラウド側ログ分析基盤：**CloudWatch → * → Athena → Grafana（＋CloudWatch datasource）**  
  - クラウド側ログ通知基盤：**CloudWatch → *（Webhook）→ n8n**
  - 監査/参照ポータル：**Sulu**（SoR の read-only 参照UI。決定一覧/Incident/SRQ/Problem/Change の閲覧導線）
  - 人事/組織（HRMS）：**Horilla**（realm ごとに URL/DB を分離してデプロイし、ITSM 基盤とは API 連携対象として扱う）
- 監視・オブザーバビリティはクラウド側ログ分析/通知基盤を前提とし、GitLab/Zulip/n8n は「記録・起票・通知・自動処理」を担当
- テスト自動化・実行基盤は各プロジェクトが自由に選択（例：GitLab CI）。本方針では特定ツールを規定しない
- 似た機能を持つツールは採用・非採用の根拠を明示し、利用しない機能を明確化する
- ナレッジ/設計/運用手順は GitLab（リポジトリ/Markdown）に集約し、会話は Zulip に集約する
- CMDBのマスターはレルム対応のGitLabグループ「サービス管理プロジェクト」内 `cmdb/`（現状）。SoR（`itsm.*`）は承認/決定/主要レコードの正規化データを集約し、必要に応じて CMDB の正規化（Service/CI テーブル）へ段階導入する
- カレンダー機能の使い分け：サービス変更・リリース・アウトージ予定は GitLab サービス管理（Issue/ボード/マイルストーン）に登録し、必要に応じて n8n で外部カレンダーへ同期する（専用ERP/グループウェアは本構成には含めない）

関連ドキュメント:
- GitLab更新イベントの@メンション通知（Zulip DM）: `apps/itsm_core/gitlab_mention_notify/README.md`

## OSS 一覧（バージョン）

本ドキュメントで扱う OSS の一覧です。バージョンは Terraform 変数の **デフォルト値**に基づきます（`terraform.*.tfvars` で上書き可能）。運用時は `terraform output` も確認してください。

| OSS | バージョン | 備考 |
| --- | --- | --- |
| Keycloak | 26.4.7 | `keycloak_image_tag` のデフォルト値 |
| Zulip | 11.4-0 | `zulip_image_tag` のデフォルト値 |
| n8n | 1.122.4 | `n8n_image_tag` のデフォルト値 |
| Qdrant | v1.16.3 | `qdrant_image_tag` のデフォルト値 |
| GitLab | 17.11.7-ce.0 | `gitlab_omnibus_image_tag` のデフォルト値 |
| GitLab Runner | alpine-v17.11.4 | `gitlab_runner_image_tag` のデフォルト値（ECS/Fargate shell executor 用） |
| Exastro ITA Web | exastro/exastro-it-automation-web-server:2.7.0 | `exastro_it_automation_web_server_image_tag` のデフォルト値 |
| Exastro ITA API | exastro/exastro-it-automation-api-admin:2.7.0 | `exastro_it_automation_api_admin_image_tag` のデフォルト値 |
| Grafana | 12.3.1 | `grafana_image_tag` のデフォルト値 |
| Sulu | 3.0.3 | `sulu_image_tag` のデフォルト値（ITSM SoR の監査/参照向け read-only ポータル） |
| Horilla | 1.5.0 | `horilla_image_tag` のデフォルト値（HRMS。ECS へ realm 単位でデプロイ） |

## apps/ 配下のアプリ一覧（別表）

apps 配下のディレクトリアプリを一覧化します。詳細は各アプリの README を参照してください。

| アプリ | 概要 | 参照 |
| --- | --- | --- |
| aiops_agent | AIOps Agent のワークフロー群 | `apps/aiops_agent/README.md` |
| workflow_manager | サービスリクエスト管理のワークフロー群 | `apps/workflow_manager/README.md` |
| cloudwatch_event_notify | CloudWatch イベント通知のワークフロー | `apps/itsm_core/cloudwatch_event_notify/README.md` |
| gitlab_issue_metrics_sync | GitLab Issue メトリクス同期 | `apps/itsm_core/gitlab_issue_metrics_sync/README.md` |
| gitlab_dora_metrics_sync | GitLab DORA 指標（日次）同期 | `apps/itsm_core/gitlab_dora_metrics_sync/README.md` |
| itsm_sla_metrics_sync | ITSM SLA 計測（日次）同期 | `apps/itsm_core/itsm_sla_metrics_sync/README.md` |
| gitlab_issue_rag | GitLab Issue の RAG 連携 | `apps/itsm_core/gitlab_issue_rag/README.md` |
| gitlab_mention_notify | GitLab メンション通知 | `apps/itsm_core/gitlab_mention_notify/README.md` |
| gitlab_push_notify | GitLab Push 通知 | `apps/itsm_core/gitlab_push_notify/README.md` |
| zulip_gitlab_issue_sync | Zulip ↔ GitLab Issue 同期 | `apps/itsm_core/zulip_gitlab_issue_sync/README.md` |
| zulip_stream_sync | Zulip ストリーム同期 | `apps/itsm_core/zulip_stream_sync/README.md` |

## scripts/ 配下の主要機能一覧（別表）

機能実現に大きな役割を持つ主要スクリプトを一覧化します（運用手順の正は各README/スクリプト先頭コメント）。

| スクリプト | 概要 | 参照 |
| --- | --- | --- |
| `itsm_bootstrap_realms.sh` | ITSM Bootstrap（GitLab のプロジェクト/テンプレート/ラベル/ボード等の初期構成） | `apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh` |
| `ensure_realm_groups.sh` | GitLab レルム/グループ構成の前提整備 | `apps/itsm_core/bootstrap/scripts/ensure_realm_groups.sh` |
| `sync_usecase_dashboards.sh` | Grafana の ITSM ユースケースダッシュボード同期 | `apps/itsm_core/bootstrap/scripts/sync_usecase_dashboards.sh` |
| `provision_grafana_itsm_event_inbox.sh` | Grafana `ITSM Event Inbox` の作成と監視参照導線の整備 | `apps/itsm_core/bootstrap/scripts/provision_grafana_itsm_event_inbox.sh` |

## ユースケース定義の正本

ユースケース定義・ユースケースID・ユースケース機能ID・プラクティス別の詳細一覧は、CSV を正本とする。

- `docs/itsm/itsm_oss_features.csv`

## ツールの役割と「似た機能の使い分け」の要約（根拠）

似た機能を持つツールの採用方針（役割分担）の整理。

- **GitLab サービス管理（CMDB/Issue） vs Exastro ITA（構成・自動化）**
  - GitLab：CMDB（`cmdb/`）と変更/議論/レビュー/根拠リンクなどの **長期記録（Change & Evidence）** の中心
  - Exastro ITA：構成パラメータ・作業手順の定義と実行（Web/API）
  - 方針：Exastro ITA から取得できる構成情報は n8n で差分化し、GitLab CMDB を随時更新（MR/コミット）して「参照先の一元化」を担保する

- **Zulip（会話） vs GitLab（長期記録）**  
  - Zulip：インシデント/依頼/合意形成のリアルタイム窓口（トピックで整理）  
  - GitLab：経緯記録/証跡（決定の要約・根拠リンク・`correlation_id` 等）・Runbook・設計・台帳の長期保管（版管理）
  - SoR（共有 RDS / PostgreSQL）：承認/決定/主要レコードの **構造化された正（`itsm.approval` / `itsm.audit_event` 等）**
  - 方針：会話/調整は Zulip、最終決定は Zulip または GitLab Issue（状況により）。n8n が会話→起票/要約→（GitLab 証跡化 + SoR 記録）を補助する

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
- 役割/RACI：役割別の使い方と責任分界（RACI）はサービス管理テンプレートを正とする（`apps/itsm_core/bootstrap/data/templates/service-management/docs/role_guide.md.tpl` と `apps/itsm_core/bootstrap/data/templates/service-management/docs/raci.md.tpl`）。

## 顧客向けポータルからの問い合わせフロー

- 顧客向け窓口：GitLab Issueフォーム（認証が可能な利用者向け）または Zulip（ストリーム/トピック）を入口とする。外部フォームが必要な場合はHTTP POSTで n8n Webhook に送信する。
- 受付：n8n で受信（Webhook または GitLab/Zulip 連携）し、入力チェックとカテゴリ判定を実施。
- 起票：n8n から GitLab サービス管理（CMDB/Issue） にチケット（サービス要求/インシデント等）を自動登録し、受付番号を発行。
- 通知：n8n が受付完了メールを顧客へ送信。社内は Zulip の専用トピックへ通知。
- 対応：担当者は GitLab Issueで進捗/ステータスを管理し、必要なやり取りは Zulip で行う。
- 追跡：ステータス更新時にメールで顧客へ連絡。必要ならポータル側で簡易ステータス表示を GitLab API連携で出す。

## データガバナンス

### アクセス制御（テーブル単位）
- GitLab/Zulip/Exastro/Grafana は Keycloak（OIDC/SAML）で統合認証し、グループ/ロールでアクセス制御（最小権限）を行う。n8n はローカル認証、Qdrant はAPI前提（原則 n8n 経由）とし、連携用のservice accountは用途別に分離して Secrets Manager／SSM パラメータで管理する。
- 運用基盤が接続する Postgres/RDS などでは IAM 認証＋ Keycloak のRBAC方針に合わせたDBロール分離を行い、機微データは最小権限・監査ログ前提で取り扱う（read-only/エクスポート用ロールは別定義）。

### 監査ログの改ざん防止（WORM/S3）
- CloudTrail・RDS Enhanced Monitoring・VPC Flow Logs は専用 S3 バケットへ集約し、Object Lock（WORM）＋バージョニング＋SSE-KMS で改ざんと削除を防ぐ。ログ書き込みはログ発行アカウントの IAM role のみに限り、運用チームには読み取り専用ロールを割り当てる。
- CloudWatch Logs のS3アーカイブ（Athena/Grafana での長期検索・集計用）は対象ロググループを限定し、運用で合意したものだけを出力する（監視参照の導線はGrafanaに統一）。長期保存時は `logs-archive` バケットにライフサイクルで移動し、同様に Object Lock を維持する。
- ITSM SoR（`itsm.audit_event`）は DB 側で append-only + ハッシュチェーンを形成し、チェーン先頭（最新 `integrity.hash`）を定期的に同様の WORM バケットへアンカーして「DB 管理者が DB 内で辻褄を合わせる」攻撃を難しくする。

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

## OSSの役割と非採用機能（再整理）

`## OSS 一覧（バージョン）` に載せている OSS について、「本システムで担う役割」と「意図的に使わない機能」を運用方針として固定する。

| OSS | 本システムでの主な役割（採用） | 使わない機能（非採用） | 非採用の理由/方針 |
| --- | --- | --- | --- |
| Keycloak | 統合認証/認可（OIDC、ロールベースのアクセス制御） | 各アプリ固有の細粒度業務権限ロジック | 認証基盤と業務権限を分離し、責務を明確化するため |
| Zulip | 会話/調整の主チャネル、運用通知の到達点 | チケットの正本管理、設計/台帳の長期保管 | 状態管理・証跡は GitLab/SoR を正とし、会話に専念させるため |
| n8n | システム間連携、自動化オーケストレーション、通知制御 | 監視の一次検知基盤、長期台帳 | 一次検知は CloudWatch、正本は GitLab/SoR に分離するため |
| Qdrant | 類似検索/RAG 用の派生インデックス | 正式な台帳/証跡データの保管、更新系の常用運用 | 正本は GitLab/SoR。Qdrant は再生成可能な検索層として扱うため |
| GitLab | 記録/起票/承認/証跡、CMDB（`cmdb/`）、CI/CD | 常時チャット、監視の一次分析、イベント配送バス | 会話は Zulip、監視分析は Athena/Grafana、配送は n8n/CloudWatch に分担 |
| Exastro ITA Web | 構成情報の管理、実行定義/実行オーケストレーション（GUI） | チケット管理、会話/承認の正本管理 | ITA は実行面に特化し、管理/証跡は GitLab 側に寄せるため |
| Exastro ITA API | 構成取得/実行の API 経路（n8n/GitLab 連携先） | 人手運用の主経路（UI 代替としての常用） | 手動運用は Web、システム連携は API と経路分離するため |
| Grafana | 監視参照/可視化（ダッシュボード、Annotation、CloudWatch/Athena 参照） | Alertmanager data source、Alert provisioning（rule/contact point/policy の file/API 管理）を標準運用にしない | 一次通知経路を CloudWatch/SNS → n8n に統一するため（Grafana webhook は任意の補助経路） |
| Sulu | ITSM SoR の監査/参照ポータル（read-only 一覧/検索） | サービスデスクの受付/更新 UI、SoR 更新機能 | Sulu は監査参照に限定し、更新操作は GitLab/n8n 系に集約するため |
| Horilla | Horilla は HR の台帳として採用するが、SSO 統合や ITSM/CMDB の中心にはしない。必要な部分だけ連携して使う | Keycloak OIDC（SSO）連携、ITSM（Incident/Change 等）の正本管理、CMDB の正本管理 | Horilla は HR 領域に限定する。認証統合（OIDC）は当面構成に含めず、ITSM の正本は GitLab/SoR を維持するため |

## 現時点の矛盾/要修正箇所

2026-02-25 時点で把握していた主な不整合は、以下のとおり解消済み。

| 対象 | 旧不整合 | 正とする方針 | 対応結果 |
| --- | --- | --- | --- |
| `docs/itsm/features_comparison.md` の Sulu 記述 | 「Sulu（CloudFront + S3）」と書かれ、SoR read-only 参照UIとしての役割が読み取りにくかった | Sulu は「監査/参照ポータル（read-only UI）」 | `features_comparison.md` を方針表現へ修正済み |
| `docs/itsm/itsm_oss_features.csv` の一部 Grafana 行 | `Alerting` 表現が残り、Alert provisioning の標準不採用方針とずれていた | Grafana は「参照/可視化中心、Webhook 任意」。一次通知は CloudWatch/SNS → n8n | CSV の該当行を `Dashboards/Annotations/Webhook (optional)` 系へ修正済み |
