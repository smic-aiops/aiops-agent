# 一般管理（設計ファミリ=general）ユースケース：実現可否再チェック（2026-02-25）

- 対象: `docs/itsm/usecase_design_allocation_2026-02-25.csv` の `設計ファミリ == general`
- 対象件数: 438
- 参考（実装ギャップ再分類）: `docs/itsm/usecase_impl_gap_report_2026-02-25_reclassified.csv`

## 結論
- 実装ギャップCSVへの掲載漏れ: 0
- 設計テンプレ欠落: 0
- 参照コンポーネント欠落: 0
- 参照コンポーネント（workflows空）: 0

## 既存機能への割当（内訳）
- platform-doc-only: 322
- apps/itsm_core/gitlab_issue_metrics_sync: 29
- apps/itsm_core/gitlab_issue_rag: 24
- apps/itsm_core/zulip_gitlab_issue_sync: 24
- apps/workflow_manager: 21
- apps/itsm_core/zulip_stream_sync: 8
- apps/itsm_core/gitlab_push_notify: 5
- apps/itsm_core/gitlab_dora_metrics_sync: 5

## カテゴリ内訳（上位）
- 測定および報告: 44
- 情報セキュリティ管理: 39
- 関係管理: 32
- プロジェクト管理: 25
- リスク管理: 25
- 継続的改善: 25
- アーキテクチャ管理: 24
- サプライヤ管理: 24
- サービス財務管理: 24
- ポートフォリオ管理: 24
- 人材・タレント管理: 24
- 戦略管理: 24
- 知識管理: 24
- 組織変更管理: 24
- サービス妥当性確認およびテスト: 21
- 変更イネーブルメント: 21
- ガバナンス: 5
- コミュニケーション管理: 5
- コミュニケーション: 2
- ガバナンス; 情報セキュリティ管理: 1
- ガバナンス; 監査: 1

## 参照コンポーネント（存在確認）
- apps/itsm_core/gitlab_issue_metrics_sync: referenced=29, exists=True, workflows=2
- apps/itsm_core/gitlab_issue_rag: referenced=24, exists=True, workflows=2
- apps/itsm_core/zulip_gitlab_issue_sync: referenced=24, exists=True, workflows=2
- apps/workflow_manager: referenced=21, exists=True, workflows=5
- apps/itsm_core/zulip_stream_sync: referenced=8, exists=True, workflows=2
- apps/itsm_core/gitlab_push_notify: referenced=5, exists=True, workflows=2
- apps/itsm_core/gitlab_dora_metrics_sync: referenced=5, exists=True, workflows=2
