# GitLab Issue Metrics Sync 要求（Requirements）

本書は `apps/gitlab_issue_metrics_sync/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/gitlab_issue_metrics_sync/README.md` と `apps/gitlab_issue_metrics_sync/docs/`、ワークフロー定義、同期スクリプトを正とします。

## 1. 対象

GitLab Issue を運用データとして収集・集計し、日次等のメトリクスを S3 に履歴として保存する n8n ワークフロー群。

## 2. 目的

「全部 Issue」の運用状態を定量化して履歴化し、改善・意思決定（傾向把握/ボトルネック分析等）の材料にする。

## 2.1 代表ユースケース（DQ/設計シナリオ由来）

本セクションは `apps/gitlab_issue_metrics_sync/docs/dq/dq.md` の設計スコープ/主要リスクを、運用上のユースケースへ落とし込んだものです。

- UC-MET-01: 既定（日次/前日 UTC）で GitLab Issue を集計し、S3 に履歴出力する
- UC-MET-02: `N8N_METRICS_TARGET_DATE` 等の入力で対象日付を指定し、集計結果を再現する（監査/調査のための再実行）
- UC-MET-03: 出力物（`metrics.json`/`gitlab_issues.jsonl` 等）が JSON として解析可能であることを確認する（OQ での最低限チェック）
- UC-MET-04: 期間/対象の取り違いを防ぐ（既定ロジックと手動指定の双方で、出力が意図した期間に整合する）
- UC-MET-05: GitLab/S3 の認証失敗時に、失敗を明確にし証跡（ログ/出力欠落）を残す

## 3. スコープ

### 3.1 対象（In Scope）

- GitLab API から Issue データを取得する
- 期間（例: 前日 UTC）を切ってメトリクスを集計する
- 集計結果を S3 に出力する（JSON/JSONL 等）
- 定期実行（Cron）および手動再現（OQ 用 Webhook）を提供する

### 3.2 対象外（Out of Scope）

- GitLab の運用/権限設計そのもの
- S3 ライフサイクル/分析基盤の設計（Athena/BI 等）
- メトリクスの KPI 妥当性の最終判断（値の解釈は運用側の責任）

## 4. 機能要件（要約）

- 入力: 定期実行（Cron）または手動トリガ（Webhook）
- 処理: GitLab からの取得、期間指定、集計、出力形式の整形
- 出力: S3 への保存（履歴として参照可能）
- 再現性: 対象日付を指定して同一ロジックで再計算できること

## 5. 非機能要件（共通）

- セキュリティ: GitLab/S3 のアクセスキーは最小権限で運用する
- 冪等性: 同一日付/同一条件の再実行で結果を上書き・追記どちらでも運用可能な設計とする（方式は実装で定義）
- 監査性: 出力（集計結果）と入力条件（対象日付/範囲）を追跡可能にする
- 運用性: dry-run 等で書き込みを抑止できる場合は提供し、誤出力リスクを低減する
