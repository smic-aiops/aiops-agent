# 33. 問題管理（RCA と再発防止）

**人物**：加藤（運用）／森（開発）／山本（サービスデスク）

## 物語（Before）
加藤「また同じ障害だ。復旧はできるけど、根が残ってる」  
森「直して終わり、だと次は“もっと悪い形”で来る」  
山本「問い合わせも同じ内容が増えてます。現場が疲弊します」

## ゴール（価値）
- “復旧” と “再発防止” を分け、**Problem として管理**できる
- 既知エラー（Known Error）と回避策が残り、**問い合わせ対応が速くなる**

## 事前に揃っているもの（このプロジェクト）
- インシデントテンプレ: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/tree/main/.gitlab/issue_templates`
- Issue起票: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/issues/new`
- ボード: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/boards`
- ラベル: `{{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/labels`

## 実施手順（GitLab / n8n）
1. 「インシデントの再発条件」を決める（例: 30日以内に同一カテゴリ×同一サービスで3回）  
2. n8n が再発条件を満たしたら、Problem Issue を起票（例: `ITSM/問題` + `状態/要調査`）し、該当インシデントを linked Issue で紐付ける  
3. Problem Issue で RCA（根本原因分析）を実施し、次を最低限埋める  
   - 何が起きたか（事実）／なぜ起きたか（原因）／なぜ防げなかったか（検知・運用・設計）  
   - 暫定対策（回避策）／恒久対策（設計・実装）／検証方法（再発しない根拠）  
4. 回避策が有効なうちに、サービスデスク向けに「既知エラー」として残す（例: `docs/known_errors/` や Wiki、Issue本文でも可）  
5. 恒久対策を技術管理へ分解し、MR/CI で証跡化する（例: `{{TECHNICAL_MANAGEMENT_PROJECT_PATH}}#XXX`）  
6. 運用・顧客影響がある場合は、サービス管理の変更判断にリンクして合意を残す（例: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}#XXX`）  
7. 再発率（同一カテゴリのインシデント）を Grafana で追い、改善が確認できたら Problem をクローズする

## After（変化）
加藤「復旧で“止血”、Problem で“根治”。流れが分かれた」  
森「恒久対策が MR と CI に残る。次の人が追える」  
山本「既知エラーがあるだけで、問い合わせが一段速くなる」

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `33_problem_management`（問題管理）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`](../monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 33_problem_management
      usecase_name: 問題管理
      dashboard_uid: sm-problem-management
      dashboard_title: Problem Management Overview
      folder: ITSM - サービス管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（再発/原因/対策リードタイム）
      panels:
        - panel_title: 再発インシデント件数
          metric: recurring_incident_count
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: Problem 起票数
          metric: problem_created
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 原因特定までの時間
          metric: time_to_rca
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: 恒久対策リードタイム
          metric: time_to_permanent_fix
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 同一インシデント再発 / 既知エラー未登録 / 恒久対策期限超過
- Zulip チャンネル: #sm-problem
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
## Done（完了条件）
- Problem Issue に RCA（原因/対策/検証）が残り、linked Issue で実装まで辿れる
- 既知エラーと回避策が共有され、問い合わせ対応と復旧が速くなる
- 再発率が下がっていることをメトリクスで説明できる

## ねらい
- インシデント対応の“火消し”を止めずに、**再発防止の流れを別レーンで回す**
- 既知エラーを残し、サービスデスクの一次対応を強くする（属人化を減らす）

## 価値指標（KPI例）
- 再発率（同一カテゴリ×同一サービスのインシデント回数）
- 原因特定リードタイム（Time to RCA）
- 恒久対策の完了率（期限内にクローズできた割合）
- 既知エラーの再利用率（回避策が参照された回数）

## 参考（Sources）
- https://www.axelos.com/resource-hub/practice/problem-management （参照日: 2026-02-13）
- https://www.atlassian.com/incident-management/problem-management （参照日: 2026-02-13）
- https://sre.google/sre-book/postmortem-culture/ （参照日: 2026-02-13）

<!-- BEGIN AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
## 対応ユースケース（トレーサビリティ / 移設: 99_missing_usecases）

- 元は `99_missing_usecases.md.tpl` に集約していた未設計ユースケースを、既存の詳細テンプレ（章）へ移設した一覧です。
- 「プラクティス」は `docs/itsm/itsm_oss_features.csv` をソースとし、コンポーネント/操作はそれに基づく設計上の割当です（未実装は命名規約で明示）。

### 問題管理（21）
#### プラクティス: GitLab; Zulip / アプリ: Issues; Labels; Topics（21）
- コンポーネント/操作:
  - GitLab: `{{SERVICE_MANAGEMENT_PROJECT_PATH}}` で Issue 起票→ラベル/ボードで状態管理→（必要時）MR で変更レビュー/承認
  - Issueテンプレ: `issue_templates/03_problem.md`（根本原因/再発防止）
- 対象ユースケース:

| UC-ID | 機能ID | ユースケース | 実装状況 |
|---|---|---|---|
| UC-3901 | UC-GL-484 | 問題管理のSLA/目標管理 | ⭕️ |
| UC-3902 | UC-GL-485 | 問題管理のエスカレーション/連携 | ⭕️ |
| UC-3903 | UC-GL-486 | 問題管理のデータ品質の維持 | ⭕️ |
| UC-3904 | UC-GL-487 | 問題管理のナレッジの更新 | ⭕️ |
| UC-3905 | UC-GL-488 | 問題管理のレポート/振り返り | ⭕️ |
| UC-3906 | UC-GL-489 | 問題管理のレポートの標準化 | ⭕️ |
| UC-3907 | UC-GL-490 | 問題管理の依存関係の整理 | ⭕️ |
| UC-3908 | UC-GL-491 | 問題管理の分類/優先度付け | ⭕️ |
| UC-3909 | UC-GL-492 | 問題管理の受付/登録 | ⭕️ |
| UC-3910 | UC-GL-493 | 問題管理の品質保証/監査 | ⭕️ |
| UC-3911 | UC-GL-494 | 問題管理の実行/処理 | ⭕️ |
| UC-3912 | UC-GL-495 | 問題管理の承認/レビュー | ⭕️ |
| UC-3913 | UC-GL-496 | 問題管理の改善施策の実施 | ⭕️ |
| UC-3914 | UC-GL-497 | 問題管理の方針/標準定義 | ⭕️ |
| UC-3915 | UC-GL-498 | 問題管理の標準テンプレートの整備 | ⭕️ |
| UC-3916 | UC-GL-499 | 問題管理の継続的改善 | ⭕️ |
| UC-3917 | UC-GL-500 | 問題管理の自動化/効率化 | ⭕️ |
| UC-3918 | UC-GL-501 | 問題管理の調査/分析 | ⭕️ |
| UC-3919 | UC-GL-502 | 問題管理の通知/コミュニケーション | ⭕️ |
| UC-3920 | UC-GL-503 | 問題管理の運用手順の整備 | ⭕️ |
| UC-3921 | UC-GL-504 | 問題管理の関係者合意の形成 | ⭕️ |


<!-- END AUTO_MIGRATED_FROM_99_MISSING_USECASES -->
