# 24. セキュリティ

**人物**：小林（セキュリティ）／斉藤（Dev）／岡田（Ops）

## 物語（Before）
リリース直前。  
小林「このライブラリ、重大脆弱性がある」  
斉藤「今!? もうテスト終わってる…」  
岡田「“最後に見つかる”が一番コスト高い」

## ゴール（価値）
- セキュリティ課題を早期に検知し、手戻りを減らす
- 例外や判断を「説明できる証跡」として残す

## 事前に揃っているもの（このプロジェクト）
- Issue（テンプレ: `02_技術タスク` / `04_技術調査（Spike）`）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/issues/new`
- CI（パイプライン枠）: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}/-/pipelines`
- サービス管理（判断の正）: `{{GITLAB_BASE_URL}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}`

## 実施手順（GitLab）
1. セキュリティ検知を Issue 化（影響と期限を明確化）  
2. 対応方針を決める（修正/回避/例外）  
3. 例外やリスク受容は `{{SERVICE_MANAGEMENT_PROJECT_PATH}}#XXX` に紐づける  
4. CI にセキュリティチェックを追加（不足があれば後述の「不足チェック」参照）

## 不足チェック（この環境での扱い）
- 現状CIは JSON/Schemas の整合性検証が中心です。  
  実プロダクトに合わせて SAST/依存関係スキャン等を追加する前提で、まずは Issue と判断の導線を整えます。


## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `24_security`（セキュリティ）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 24_security
      usecase_name: セキュリティ
      dashboard_uid: tm-security
      dashboard_title: Security Overview
      folder: ITSM - 技術管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 脆弱性件数
          metric: vulnerability_count
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: パッチ適用時間
          metric: patch_latency
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: セキュリティインシデント
          metric: security_incidents
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: コンプライアンススコア
          metric: compliance_score
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 脆弱性検知 / セキュリティインシデント / パッチ遅延
- Zulip チャンネル: #tm-security
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける

## 対応ユースケース（トレーサビリティ）
このユースケース群は「Keycloak/Zulip の標準機能で実現し、設定（判断の正本）を GitLab に残す」前提です。  
なお、現時点でアプリ個別の OIDC 連携までを必須にはしていないため、まずは設計・運用導線を整備し、必要な範囲から段階的に適用します。

- UC-4503（管理権限分離）: Keycloak の realm/クライアント管理権限を分離（管理者ロール/運用ロール）し、例外は `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` に紐付けて承認を残す
- UC-4504（トークン設計）: Keycloak のクライアント設定（Token/Session/Scope）を設計し、変更は Change Issue と MR で追跡
- UC-4506（権限継承）: Keycloak のグループ/ロール設計で継承（階層）を表現し、権限追加は承認付きで運用
- UC-4507（外部IdP連携）: Keycloak の Identity Provider 設定で外部IdPを追加可能（実際の接続は段階適用）
- UC-4508（統合認証・SSO）: Keycloak を統合ID基盤として採用し、アプリ側の OIDC 有効化は優先度に応じて実施
- UC-4509（マルチテナント認証）: realm 分離（または realm 内の組織分離）でテナント境界を作り、設定差分をGitLabで管理
- UC-4510（権限設計）: ロール/グループ/クライアントスコープを組み合わせた権限モデルを設計し、棚卸しを定例化
- UC-4511（ユーザーフェデレーション）: LDAP/外部ディレクトリを Keycloak の User Federation として接続可能（必要時に適用）
- UC-4512（多要素認証）: Keycloak の認証フローで MFA を適用（対象ロール/条件付き適用を含む）
- UC-0801（トピック作成権限）: Zulip のロール/ストリーム投稿権限（誰が投稿できるか）で実質的にトピック作成を制御し、運用ポリシーを `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` に残す
## Done（完了条件）
- 対応/例外の判断が `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` 側に残っている
- 技術管理側で修正がMR/CIとして残っている

<!-- BEGIN TRACEABILITY_GENERAL_FAMILY -->
## 対応ユースケース（トレーサビリティ / general）
- UC-0801 トピック作成権限
- UC-4501 機密チケット
- UC-4502 レジストリ認証
- UC-4503 管理権限分離
- UC-4504 トークン設計
- UC-4506 権限継承
- UC-4507 外部IdP連携
- UC-4508 統合認証・SSO
- UC-4509 マルチテナント認証
- UC-4510 権限設計
- UC-4511 ユーザーフェデレーション
- UC-4512 多要素認証
- UC-4513 情報セキュリティ管理のKPI/指標定義
- UC-4514 情報セキュリティ管理のガバナンスと方針運用の整備
- UC-4515 情報セキュリティ管理のステークホルダー/関係者調整
- UC-4516 情報セキュリティ管理のツール/データ整備
- UC-4517 情報セキュリティ管理のリスク/例外レビュー
- UC-4518 情報セキュリティ管理のリスクと例外の管理
- UC-4519 情報セキュリティ管理のレビュー/監査の実施
- UC-4520 情報セキュリティ管理のロードマップ策定
- UC-4521 情報セキュリティ管理の主要関係者の合意形成
- UC-4523 情報セキュリティ管理の定期レビュー/報告
- UC-4524 情報セキュリティ管理の実行計画の策定
- UC-4525 情報セキュリティ管理の役割/責任（RACI）定義
- UC-4526 情報セキュリティ管理の意思決定基準の明文化
- UC-4527 情報セキュリティ管理の成果物の記録/版管理
- UC-4528 情報セキュリティ管理の指標の定義と可視化
- UC-4529 情報セキュリティ管理の改善施策の優先順位付け
- UC-4530 情報セキュリティ管理の教育/オンボーディング
- UC-4531 情報セキュリティ管理の教育/展開/浸透
- UC-4532 情報セキュリティ管理の方針/ポリシー策定
- UC-4534 情報セキュリティ管理の現状評価/ギャップ分析
- UC-4535 情報セキュリティ管理の目標/ターゲット設定
- UC-4538 資格情報管理
- UC-4539 セキュア運用
<!-- END TRACEABILITY_GENERAL_FAMILY -->
