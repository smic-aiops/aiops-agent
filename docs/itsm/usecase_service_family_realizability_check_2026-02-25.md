# サービス系（設計ファミリ=service）ユースケース：実現可否再チェック（2026-02-25）

- 対象: `docs/itsm/usecase_design_allocation_2026-02-25.csv` の `設計ファミリ == service`
- 対象件数: 340
- 参考（実装ギャップ再分類）: `docs/itsm/usecase_impl_gap_report_2026-02-25_reclassified.csv`（該当IDが存在する分のみ）

## 結論
- 設計テンプレ欠落: 0
- 参照コンポーネント欠落: 0
- 参照コンポーネント（workflows空）: 0

## 実装ギャップ再分類（内訳）
- 実装済み（根拠+自動化）: 180
- 実装済みへ寄せる候補: 160

## 既存機能への割当（内訳）
- platform-doc-only: 185
- apps/workflow_manager: 43
- apps/itsm_core/cloudwatch_event_notify; apps/aiops_agent: 21
- apps/workflow_manager; apps/itsm_core/zulip_gitlab_issue_sync: 21
- apps/itsm_core/gitlab_issue_metrics_sync: 21
- apps/itsm_core/gitlab_push_notify: 21
- apps/aiops_agent: 16
- apps/itsm_core/gitlab_mention_notify: 6
- apps/itsm_core/zulip_gitlab_issue_sync: 6

## カテゴリ内訳（上位）
- インシデント管理: 39
- サービスデスク: 35
- サービス構成管理: 23
- サービス要求管理: 22
- リリース管理: 22
- IT資産管理: 21
- サービスカタログ管理: 21
- サービスレベル管理: 21
- サービス継続管理: 21
- サービス設計: 21
- ビジネス分析: 21
- 可用性管理: 21
- 問題管理: 21
- 容量・パフォーマンス管理: 21
- 変更管理: 2
- インシデント管理; 問題管理: 1
- コミュニケーション（例外処理）: 1
- サービスデスク; インシデント管理: 1
- サービスデスク; 変更管理: 1
- サービス構成管理; 変更管理: 1
- サービス要求管理; 変更管理: 1
- 変更管理; プロジェクト管理: 1
- 変更管理; 測定および報告: 1

## 参照コンポーネント（存在確認）
- apps/workflow_manager: referenced=64, exists=True, workflows=5
- apps/aiops_agent: referenced=37, exists=True
- apps/itsm_core/zulip_gitlab_issue_sync: referenced=27, exists=True, workflows=2
- apps/itsm_core/cloudwatch_event_notify: referenced=21, exists=True, workflows=2
- apps/itsm_core/gitlab_issue_metrics_sync: referenced=21, exists=True, workflows=2
- apps/itsm_core/gitlab_push_notify: referenced=21, exists=True, workflows=2
- apps/itsm_core/gitlab_mention_notify: referenced=6, exists=True, workflows=1
