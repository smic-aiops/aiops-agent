# 市販ITSM との比較（機能対照表）

本ドキュメントは、市販ITSM を基準に、本リポジトリの「AIOps Agent サービス運用基盤（OSS 統合）」で **どこまで代替/実現できているか**、および **未提供の場合の実装案**を整理した比較表です。

前提（本リポジトリ側の主要要素）:
- 認証/認可: Keycloak（OIDC）
- 連携/自動化: n8n（Webhook/スケジュール/外部API連携）
- 記録/起票/CMDB（現状の正）: GitLab（Issue/Repo/`cmdb/`）
- SoR（正規化DB）: 共有 RDS(PostgreSQL) の `itsm.*`（承認・決定・正規化レコードを集約）
- コミュニケーション: Zulip
- 構成自動化/構成収集: Exastro ITA
- 監視参照/可視化: Grafana（CloudWatch/Athena 等）
- ログ/イベント: CloudWatch / EventBridge（＋n8n）
- ベクトル検索: Qdrant（RAG/類似検索）
- ポータル/コントロールサイト: Sulu（CloudFront + S3）
- データストア/秘匿情報: RDS(PostgreSQL) / EFS / SSM・Secrets Manager

判定:
- `⭕️`: 大体可能
- `🔺`: 一部可能
- `❌`: 他アプリ・基盤と連携で可能
- `-`: 不可能

> 注意: 市販ITSM はエディション/プラグイン/契約内容により提供範囲が変わります。本表は「代表的な実装パターン」を機能領域として列挙しています（完全な網羅＝全プラグイン/全業界ソリューションまでの列挙は現実的に不可能なため）。

## ITSMユースケース比較

`docs/itsm/itsm_oss_features.csv` の集計結果です（カテゴリ別の合計数）。

| 項目 | 一般管理 | サービス管理 | 技術管理 |
|---|---:|---:|---:|
| 行数 | 359 | 383 | 400 |
| 本レポジトリ ⭕️ | 359 | 383 | 400 |
| 本レポジトリ 🔺 | 0 | 0 | 0 |
| 本レポジトリ ❌ | 0 | 0 | 0 |
| 本レポジトリ - | 0 | 0 | 0 |
| 市販ITSM ⭕️ | 49 | 211 | 10 |
| 市販ITSM 🔺 | 286 | 172 | 132 |
| 市販ITSM ❌ | 24 | 0 | 258 |
| 市販ITSM - | 0 | 0 | 0 |

## 補足（本リポジトリ内の根拠になりやすい参照先）

- 方針（ツール分担/データ正）: `docs/itsm/itsm-platform.md`
- ITSM サービスのセットアップ/運用: `docs/itsm/README.md`
- ワークフロー同期（apps デプロイ）: `docs/apps/README.md`
- 監視通知（例）: `apps/cloudwatch_event_notify/README.md`
- サービス要求/カタログ（例）: `apps/workflow_manager/README.md`
