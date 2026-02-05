# General Management Project

本プロジェクトは、一般管理プラクティスを GitLab で管理するための基盤です。
運用の判断・承認は **[{{SERVICE_MANAGEMENT_PROJECT_PATH}}]({{GITLAB_BASE_URL}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}})** を正とし、本プロジェクトでは
戦略・ポリシー・リスク・監査・コンプライアンスの可視化と意思決定を支援します。

## 全体まとめ（思想）
- 一般管理＝「全社の意思決定と改善の流れ」（本プロジェクト）
- サービス管理＝「業務とITが一体で回る流れ」（[`{{SERVICE_MANAGEMENT_PROJECT_PATH}}`]({{GITLAB_BASE_URL}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}})）
- 技術管理（DevOps）＝「価値を最速で形にする流れ」（[`{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}`]({{GITLAB_BASE_URL}}/{{TECHNICAL_MANAGEMENT_PROJECT_PATH}})）

## 利用可能リソース（組織）
- SSO/ID管理（Keycloak 管理画面）: [Keycloak 管理画面]({{KEYCLOAK_ADMIN_CONSOLE_URL}})
- チームチャット（Zulip）: [Zulip（組織）](https://{{REALM}}.zulip.smic-aiops.jp)
- 自動化（n8n）: [n8n（組織）]({{N8N_BASE_URL}})
- 可視化/監視（Grafana）: [Grafana（組織）]({{GRAFANA_BASE_URL}})

## ユースケース集
- [`docs/usecases/usecase_guide.md`](docs/usecases/usecase_guide.md)

## スコープ（一般管理プラクティス）
- リスク管理 / コンプライアンス
- 情報セキュリティ管理
- ポリシー・ガバナンス
- ポートフォリオ / 財務 / ベンダー

## 一般管理プラクティス一覧（14）
- アーキテクチャ管理: 全体構造と設計原則を管理します。
- 継続的改善: 改善の機会を特定し実行します。
- 情報セキュリティ管理: 情報資産を保護します。
- ナレッジ管理: 知識を体系化し共有します。
- 測定と報告: KPI等の可視化と報告を行います。
- 組織変更管理: 変更の受容と定着を促します。
- ポートフォリオ管理: 投資対象と資源配分を最適化します。
- プロジェクト管理: 期限・品質・コストを管理します。
- 関係管理: ステークホルダー期待値を調整します。
- リスク管理: リスク評価・対策・監視を行います。
- サービス財務管理: コストと価値を可視化し管理します。
- 戦略管理: 方向性と優先順位を整合させます。
- サプライヤ管理: 外部委託/ベンダーを統制します。
- 人材とタレント管理: スキル確保と育成を行います。

## サービスバリューシステムとの関係（概念）
一般管理プラクティスは、サービスバリューシステム全体を**統制・最適化する基盤**です（ガバナンスの実装層）。
SVCの各活動を横断して影響します。

~~~mermaid
flowchart TB
  G[ガバナンス] --> GM[一般管理プラクティス]
  GM --> VALUE_CHAIN[サービスバリューチェーン（全活動）]
~~~

## 運用ルール
- 重要判断は [{{SERVICE_MANAGEMENT_PROJECT_PATH}}]({{GITLAB_BASE_URL}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}) の Issue とリンクする
- 本プロジェクトは意思決定・監査向けの記録に集中
