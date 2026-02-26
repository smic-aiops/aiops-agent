# Technical Management Project

## 1. プロジェクトの目的
本プロジェクトは、技術管理プラクティスに基づく設計・開発・テストを
スクラム開発で実施するための技術開発プロジェクトです。

## 全体まとめ（思想）
- 一般管理＝「全社の意思決定と改善の流れ」（[`general-management`](https://gitlab.smic-aiops.jp/general-management)）
- サービス管理＝「業務とITが一体で回る流れ」（[`service-management`](https://gitlab.smic-aiops.jp/service-management)）
- 技術管理（DevOps）＝「価値を最速で形にする流れ」（本プロジェクト）

## 利用可能リソース（組織）
- SSO/ID管理（Keycloak 管理画面）: [Keycloak 管理画面]({{KEYCLOAK_ADMIN_CONSOLE_URL}})
- チームチャット（Zulip）: [Zulip（組織）](https://{{REALM}}.zulip.smic-aiops.jp)
- 自動化（n8n）: [n8n（組織）]({{N8N_BASE_URL}})
- 可視化/監視（Grafana）: [Grafana（組織）]({{GRAFANA_BASE_URL}})

## ユースケース集
- [`docs/usecases/usecase_guide.md`](docs/usecases/usecase_guide.md)

## ダッシュボード（状態参照）
- [`docs/dashboards/README.md`](docs/dashboards/README.md)

## レポート
- [`docs/reports/monthly_technical_report_template.md`](docs/reports/monthly_technical_report_template.md)

以下のプラクティスは、別プロジェクト **{{SERVICE_MANAGEMENT_PROJECT_PATH}}** を正とします。

- 変更管理
- リリース管理
- インシデント管理
- ナレッジ管理
- 継続的改善（Continual Improvement）

本プロジェクトは **技術管理（Technical Management）× DevOps** の実装を担います。

---

## 2. プロジェクト間の関係

| 項目 | プロジェクト |
|---|---|
| 開発・実装 | 本プロジェクト |
| 判断・承認 | {{SERVICE_MANAGEMENT_PROJECT_PATH}} |
| 運用受付 | {{SERVICE_MANAGEMENT_PROJECT_PATH}} |

すべての変更・障害・改善は、必ず {{SERVICE_MANAGEMENT_PROJECT_PATH}} の Issue と関連付けます。

---

## 3. 開発方式（スクラム）

本プロジェクトはスクラムを採用します。

### スクラムイベント
- スプリント（2週間）
- スプリントプランニング
- デイリースクラム
- スプリントレビュー
- レトロスペクティブ

### 役割
| 役割 | 内容 |
|---|---|
| プロダクトオーナー | {{SERVICE_MANAGEMENT_PROJECT_PATH}} 側の代表 |
| スクラムマスター | 本プロジェクト内 |
| 開発者 | ワークフロー/自動化の開発者 |

---

## 4. Issue の使い方

### Issue 種別
- ユーザーストーリー（スクラム開発単位）
- 技術タスク
- バグ修正
- 技術調査（Spike）

### 必須ルール
- すべての Issue は {{SERVICE_MANAGEMENT_PROJECT_PATH}} の Issue とリンクする
- 単独で「変更完了」「リリース完了」とはしない

---

## 5. ブランチと開発フロー

~~~text
Issue
 ↓
feature/* ブランチ
 ↓
Merge Request
 ↓
レビュー（技術）
 ↓
{{SERVICE_MANAGEMENT_PROJECT_PATH}} 側の承認
 ↓
main マージ

main ブランチのみがリリース対象
MR なしの変更は禁止
~~~

---

## 6. 障害対応時の動き
- 障害は {{SERVICE_MANAGEMENT_PROJECT_PATH}} で受付
- 本プロジェクトに修正 Issue が起票される
- 修正完了後、{{SERVICE_MANAGEMENT_PROJECT_PATH}} 側でクローズ判断

---

## 7. ドキュメント管理
- 設計変更時は [`docs/`](docs/) を更新
- ナレッジの正式保管先は {{SERVICE_MANAGEMENT_PROJECT_PATH}}

---

## 8. 継続的改善（Continual Improvement）
- レトロスペクティブの結果は {{SERVICE_MANAGEMENT_PROJECT_PATH}} の改善 Issue に集約
- 本プロジェクトでは改善アクションの実装を担当

---

## スコープ（技術管理プラクティス）
- 展開管理: 展開成功率 / 展開後インシデント数
- インフラストラクチャとプラットフォームの管理: 安定稼働 / 変更影響最小化
- ソフトウェア開発と管理: 開発の成功率 / デプロイの迅速性

## 10. サービスバリューチェーン事例
- [`docs/svc_examples/`](docs/svc_examples/) に 10 事例を収録

---

## サービスバリューシステムにおける位置づけ（技術管理）
技術管理プラクティスは、主に **Obtain/Build** および **Design & Transition** を強力に支援し、
サービス管理が安定して価値を提供できるように「技術基盤」と「変更リスク低減」を担います。

~~~mermaid
flowchart LR
  VALUE_SYSTEM[サービスバリューシステム] --> VALUE_CHAIN[サービスバリューチェーン]
  VALUE_CHAIN --> OB[Obtain/Build]
  VALUE_CHAIN --> DT[Design & Transition]
  OB --> TM[技術管理プラクティス]
  DT --> TM
~~~

---

## 参考: プラクティス一覧（カテゴリ別）
### 一般管理（14）
- アーキテクチャ管理: 全体構造と設計原則を管理します。
- 継続的改善: 改善を特定し優先順位付けして実行します。
- 情報セキュリティ管理: 情報資産を保護します。
- ナレッジ管理: 知識を体系化し提供します。
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

### サービス管理（17）
- 可用性管理: 稼働率を満たすよう設計・運用します。
- ビジネス分析: 要求と価値を整理し実現手段を明確化します。
- 容量・性能管理: 需要に応じた性能を確保します。
- 変更コントロール: 変更を評価・承認・記録します。
- インシデント管理: 復旧を最優先に影響を最小化します。
- IT資産管理: 資産の把握とライフサイクル管理を行います。
- 監視とイベント管理: 監視で異常を検知し分類・対応します。
- 問題管理: 根本原因と再発防止を扱います。
- リリース管理: リリースを計画しリスクを抑えます。
- サービスカタログ管理: 提供サービスを定義・公開します。
- サービス構成管理: 構成情報を管理し影響分析に活用します。
- サービス継続性管理: 重大障害時の継続/復旧を準備します。
- サービスデザイン: サービスを設計し運用性を高めます。
- サービスデスク: 利用者窓口として受付・一次対応します。
- サービスレベル管理: SLA/SLOを定義・合意し管理します。
- サービス要求管理: 標準要求を受付・実行します。
- サービスの検証とテスト: 要件・品質を検証します。

### 技術管理（3）
- 展開管理: 配布・適用を管理し成功率を高めます。
- インフラストラクチャとプラットフォームの管理: 基盤を整備し安定稼働を支えます。
- ソフトウェア開発と管理: 開発を管理し継続的に価値を提供します。
