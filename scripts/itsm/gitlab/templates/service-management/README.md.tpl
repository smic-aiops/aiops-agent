# ITSM 運用向け GitLab プロジェクト

このリポジトリは ITSM 運用を GitLab CE 上で立ち上げるためのテンプレートです。
Issue と CMDB を中心に、運用フローを標準化し、可視化と監査性を確保します。

## 全体まとめ（思想）
- 一般管理＝「全社の意思決定と改善の流れ」（[`{{GENERAL_MANAGEMENT_PROJECT_PATH}}`]({{GITLAB_BASE_URL}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}})）
- サービス管理＝「業務とITが一体で回る流れ」（本プロジェクト）
- 技術管理（DevOps）＝「価値を最速で形にする流れ」（[`{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}`]({{GITLAB_BASE_URL}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}})）

## 利用可能リソース（組織）
- SSO/ID管理（Keycloak 管理画面）: [Keycloak 管理画面]({{KEYCLOAK_ADMIN_CONSOLE_URL}})
- チームチャット（Zulip）: [Zulip（組織）](https://{{REALM}}.zulip.smic-aiops.jp)
- 自動化（n8n）: [n8n（組織）]({{N8N_BASE_URL}})
- 可視化/監視（Grafana）: [Grafana（組織）]({{GRAFANA_BASE_URL}})
- Web管理（Sulu）: Sulu 管理画面（`/admin`）> Monitoring > AI Nodes（`サマリ` 列で AI ノードの判断内容を要約表示）

## GitLabメンション通知の対応表
- 対応表: [`docs/mention_user_mapping.md`](docs/mention_user_mapping.md)
- GitLab の `@username` と Zulip 宛先（user_id / email）の対応を記載します。
- メール一致/username一致で解決できない場合のみ追記してください。

## ユースケース集
- [`docs/usecases/usecase_guide.md`](docs/usecases/usecase_guide.md)

## ダッシュボード（状態参照）
- [`docs/dashboards/README.md`](docs/dashboards/README.md)

## レポート
- 月次（運用）: [`docs/monthly_report_template.md`](docs/monthly_report_template.md)
- 月次（サービス管理）: [`docs/reports/monthly_service_report_template.md`](docs/reports/monthly_service_report_template.md)

## スコープ（サービス管理プラクティス）
- インシデント管理
- サービス要求管理
- 問題管理
- 変更管理
- ナレッジ管理
- 継続的改善
- サービスレベル管理
- 監視とイベント管理

## プラクティスをサービスバリューシステムで捉える（カテゴリ別）
**プラクティスを「カテゴリ別」に整理してサービスバリューシステムの中で捉える**と、
「どこに力を入れるべきか」「どこが弱いか」が見えやすくなります。

### プラクティスの3カテゴリ（全34）
~~~mermaid
flowchart TB
  A[一般管理プラクティス（14）]:::gm
  B[サービス管理プラクティス（17）]:::sm
  C[技術管理プラクティス（3）]:::tm
  classDef gm fill:#E6F7FF,stroke:#1890FF,color:#000;
  classDef sm fill:#F6FFED,stroke:#52C41A,color:#000;
  classDef tm fill:#FFF7E6,stroke:#FAAD14,color:#000;
~~~

### カテゴリ別にサービスバリューシステムを見るとこうなる（概念）
~~~mermaid
flowchart TB
  G[ガバナンス] --> GM[一般管理プラクティス\n統制・方針・改善]
  GM --> SM[サービス管理プラクティス\n価値創出の実働]
  SM --> TM[技術管理プラクティス\n技術基盤]
  TM --> V[価値]
~~~

### 実務での使い方（診断の観点）
- サービス管理は強いが、一般管理が弱い → KPI不明確・統制不足
- 技術は強いが、サービス管理が弱い → 属人運用・復旧/改善が回らない

### ツール設計（GitLab）への落とし込み（例）
- 一般管理: 方針/監査/リスク/KPIをIssueとREADMEで管理（[`{{GENERAL_MANAGEMENT_PROJECT_PATH}}`]({{GITLAB_BASE_URL}}/{{GENERAL_MANAGEMENT_PROJECT_PATH}})）
- サービス管理: Issue/Board/ラベルで運用を統制（本プロジェクト）
- 技術管理: CI/CD/IaC/Repo構成で変更のリスクを低減（[`{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}`]({{GITLAB_BASE_URL}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}})）

## Value Stream（サービス管理プラクティス中心）
本環境で扱うサービス管理プラクティスを軸に、価値提供までの流れを整理します。
対象プラクティス: インシデント管理、問題管理、サービス要求管理、変更管理、ナレッジ管理、継続的改善。

### 図解（概念）
```mermaid
flowchart TD
  A[受付/サービス要求] --> B[インシデント管理]
  B -- 既知化 --> E[ナレッジ管理]
  B --> C[問題管理]
  C -- 恒久対策 --> D[変更管理]
  C -- 改善入力 --> F[継続的改善]
  D -- 改善入力 --> F
  E -- 再発防止 --> B
```

### 価値の流れの説明
- 受付（サービス要求/インシデント）から開始し、迅速な復旧で価値回復
- 根本原因の分析は問題管理で実施し、恒久対策は変更管理で実装
- 解決内容はナレッジとして蓄積し、再発防止と対応速度向上へ還元
- 月次レポートと KPI により継続的改善を回し、サービス価値を最適化

### プラクティス別の価値と例
- サービス要求管理: 価値=利用者の要求を標準手順で迅速処理、例=アカウント発行/権限追加
- インシデント管理: 価値=サービス停止や劣化からの早期復旧、例=障害検知→暫定復旧→解決
- 問題管理: 価値=再発防止と根本原因の排除、例=RCA 作成→恒久対策の提案
- 変更管理: 価値=リスクを最小化した安定変更、例=変更諮問委員会（承認者） 承認→リリース→検証
- ナレッジ管理: 価値=対応品質と速度の向上、例=手順書/FAQ/事例の蓄積
- 継続的改善: 価値=運用の最適化とコスト削減、例=月次 KPI レビュー→改善計画

## 目的と運用方針
- 主要プラクティス（インシデント/問題/サービス要求）を Issue で一元管理
- ラベルとボードで状態遷移を可視化
- CMDB（Markdown）を Git 管理し、構成情報を唯一の正として扱う
- CMDB の正はレルム対応の GitLab グループ「サービス管理プロジェクト」内 `cmdb/` に集約する
- 月次レポートと CMDB レポートで改善サイクルを支援

## 初期セットアップ（推奨手順）
1. Issue テンプレートを確認
   - `.gitlab/issue_templates/` に各種テンプレートを用意
   - 「インシデント」「問題」「サービス要求」をテンプレから作成
2. ラベルとボードの確認
   - 運用用ラベルは自動作成済み（日本語）
   - ボード「インシデント管理」で状態ラベルを列として可視化
3. CMDB の登録
   - `cmdb/<組織ID>/<サービスID>.md` を作成・更新
   - Front Matter は機械可読のため必須
4. CI の有効化
   - `.gitlab-ci.yml` により CMDB の必須項目と Grafana/AWS 連携を検証
   - 例: `scripts/cmdb/validate_cmdb.sh` で AWS 監視基盤の必須項目を検証
   - テンプレ適用: `.gitlab-ci.yml` が無い場合は `scripts/itsm/gitlab/templates/service-management/.gitlab-ci.yml.tpl` をルートに配置して有効化
   - 厳格モード: `scripts/cmdb/validate_cmdb.sh --strict` で Grafana/AWS のどちらか + SLAリンクを必須にする
     - 例: 監視導線が未整備のサービスを CI でブロックしたい場合に使用
   - 切替例: `--no-aws`（Grafanaのみ）、`--no-grafana`（AWSのみ）
5. レポート運用
   - [`docs/monthly_report_template.md`](docs/monthly_report_template.md) を月次レポートに転用
   - `scripts/cmdb/generate_cmdb_report.sh` で CMDB レポートを生成
6. グループCI変数の自動設定（GitLabトークン）
   - `scripts/itsm/gitlab/refresh_realm_group_tokens_with_bot_cleanup.sh` が各レルムのグループアクセストークンを発行（旧トークン削除時に group bot を無効化/削除）
   - 同スクリプトが `GITLAB_API_BASE_URL` / `GITLAB_TOKEN` を各グループのCI変数へ登録
   - `GITLAB_API_BASE_URL` は `terraform output service_urls.gitlab` を優先して解決（`/api/v4` を付与）

## 運用フロー（例）
1. 受付
   - Issue をテンプレから起票（インシデント/問題/サービス要求）
   - 種別/状態/優先度/影響度/担当ラベルを付与
2. 対応
   - ボードで状態を更新しながら進捗管理
3. 解決・レビュー
   - 問題管理やナレッジ化にリンク
4. 改善
   - 月次レポートで KPI と改善案を整理

## ディレクトリ構成
- `.gitlab/issue_templates/` : 運用用 Issue テンプレート
- `cmdb/` : Markdown CMDB
- [`docs/`](docs/) : 月次レポートテンプレート、SLA/SLO マスター
- `scripts/cmdb/` : CMDB レポート生成スクリプト

## CMDB 記載ルール
```
cmdb/
└─ <組織ID>/
   └─ <サービスID>.md
```

## CMDB と Grafana 連携
- CMDB 内の `grafana.base_url` と `dashboard_uid` を使ってダッシュボードへ遷移
- 変数 `service/env/cmdb_id` を使い、特定サービスの状態を即参照
- CMDB の `grafana.usecase_dashboards` を元に、CI が Grafana ダッシュボードを作成/更新/削除する
  - 実行条件: 1時間毎のスケジュール、または CMDB の作成/更新/削除イベント
  - 実行スクリプト: `scripts/grafana/sync_cmdb_dashboards.sh`
  - API キー: CI/CD 変数 `GRAFANA_API_KEY`（必要に応じて `grafana.provisioning.api_key_env_var` で上書き）

## Grafana/AWS 参照ルール
- 参照の正は Grafana とし、Issue/レポートのリンクは Grafana に統一
- AWS（CloudWatch など）はデータソースとし、CMDB の `aws_monitoring` は補助情報として保持

## SLA/SLO マスター
- サービスごとの SLA/SLO 定義は [`docs/sla_master.md`](docs/sla_master.md) を正とする
- 目標・定義・算出元・PromQL/対象メトリクス・計測/集計期間・参照ダッシュボードを一元管理する
- 記入テンプレート: [`docs/sla_master.md`](docs/sla_master.md)
- CMDB からも [`docs/sla_master.md`](docs/sla_master.md) を参照できるようリンクを張る
- Athena 集計を使う場合は [`docs/monitoring_unification_grafana.md`](docs/monitoring_unification_grafana.md) を参照する
- 定義変更は Issue テンプレ「SLA/SLO 定義」で履歴管理する

## テンプレ更新の方針
- スクリプト実行時に README/テンプレ/ラベルを上書き更新

## 変更管理
- 変更は Issue（テンプレ「変更」）で申請し、承認後に実施
- 状態ラベル（変更：申請中/審査中/承認済/実施中/完了/中止）で可視化
- 影響範囲とロールバック手順は必須

## 注意事項
- 重要情報（トークン/パスワード）は Git に含めない
- CMDB の Front Matter は必須項目を欠かさない
- SLA/SLO 定義は [`docs/sla_master.md`](docs/sla_master.md) を正とする
- 監査や変更管理のため、Issue を正とする

---

## このREADMEでカバーしている範囲
- GitLab CE 前提の運用全体像
- 日本語ラベルを軸にした統制ルール
- サービスデスク〜インシデント〜問題管理〜ナレッジ〜改善までの実運用手順
- Board（カンバン）・KPI・月次レポートの使い方
- 禁止事項・ルール明文化（属人化防止）

## 本仕様書の強み
- 用語・考え方に準拠
- CMDB（正）と Grafana（状態参照）の責務分離が明確
- CI による統制（未承認構成変更の防止）まで定義済み
- RACI を含み、運用責任が曖昧にならない

## そのまま可能な使い方
- PDF 化して社内標準文書として配布
- 新規システム・運用設計の必須資料に指定
- 内部統制／ISMS の説明資料として流用


## プラクティス一覧（全34・カテゴリ別、参考）
この環境のスコープを超えるものも含め、全プラクティスを漏れなく記載します。

### 一般管理プラクティス（14）
- アーキテクチャ管理: 全体構造と設計原則を管理し、変更の整合性を担保します。
- 継続的改善: 改善の機会を特定し、優先順位付けして実行します。
- 情報セキュリティ管理: 情報資産の機密性・完全性・可用性を保護します。
- ナレッジ管理: 知識を体系化し、再利用できる形で提供します。
- 測定と報告: KPI等を定義し、意思決定に必要な可視化と報告を行います。
- 組織変更管理: 変更の受容と定着を促し、抵抗や混乱を抑えます。
- ポートフォリオ管理: 投資対象を整理し、価値・リスク・資源配分を最適化します。
- プロジェクト管理: 期限・品質・コストを管理し、成果物を確実に提供します。
- 関係管理: ステークホルダーとの関係を維持し、期待値を調整します。
- リスク管理: 事業・運用リスクを評価し、対策と監視を行います。
- サービス財務管理: コストと価値を可視化し、予算・課金等を管理します。
- 戦略管理: 方向性と優先順位を定め、価値提供の戦略を整合させます。
- サプライヤ管理: 外部委託・ベンダーを管理し、品質とリスクを統制します。
- 人材とタレント管理: 必要なスキルを確保し、育成・配置を最適化します。

### サービス管理プラクティス（17）
- 可用性管理: 必要な稼働率を満たすよう設計・運用・改善します。
- ビジネス分析: 要求を整理し、実現手段と価値を明確にします。
- 容量・性能管理: 需要に応じたキャパシティと性能を確保します。
- 変更コントロール: 変更のリスクを評価し、承認・実施・記録を統制します。
- インシデント管理: サービスの復旧を最優先に、影響を最小化します。
- IT資産管理: ハード/ソフト等の資産を把握し、ライフサイクルを管理します。
- 監視とイベント管理: 監視で異常を検知し、イベントを適切に分類・対応します。
- 問題管理: 根本原因を分析し、再発防止策を実施します。
- リリース管理: リリースを計画し、リスクを抑えつつ提供します。
- サービスカタログ管理: 提供サービスを定義し、利用者に分かりやすく公開します。
- サービス構成管理: 構成情報（CI等）を管理し、影響分析や復旧に活用します。
- サービス継続性管理: 重大障害時でもサービスを継続/復旧できるよう準備します。
- サービスデザイン: 要求を満たすサービスの設計を行い、運用性を高めます。
- サービスデスク: 利用者窓口として受付・案内・一次対応を行います。
- サービスレベル管理: SLA/SLOを定義・合意し、達成状況を管理します。
- サービス要求管理: 標準化された要求を受付・実行し、迅速に提供します。
- サービスの検証とテスト: 変更が要件と品質を満たすことを検証します。

### 技術管理プラクティス（3）
- 展開管理: リリース成果物の配布・適用を管理し、展開成功率を高めます。
- インフラストラクチャとプラットフォームの管理: 基盤を整備し、安定稼働を支えます。
- ソフトウェア開発と管理: 開発活動を管理し、継続的に価値を提供します。
