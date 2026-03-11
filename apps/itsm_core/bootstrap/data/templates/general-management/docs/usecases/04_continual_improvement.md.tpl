# 4. 継続的改善

**人物**：中村（現場）／松井（改善責任者）

## Before
中村「改善案、出しっぱなし」

## GitLab（使い方）
- Project: `{{GENERAL_MANAGEMENT_PROJECT_PATH}}`
- 改善＝Issue（改善が「議事録」ではなく「成果物」になる）
- Issue テンプレ: `.gitlab/issue_templates/04_continual_improvement_register.md`（CIR 台帳項目つき）
- テンプレ起票直後の初期ラベル（`ITSM/継続的改善`, `状態/New`）は、Issue Hook → n8n により自動付与される（Quick Action ではなく webhook を正とする）
- 効果（KPI/定性的効果）をコメント必須にする（測定と報告）
- 月次でボードを棚卸しし、未着手の理由も透明化

## CIR ステータス（定義）

GitLab Issue を **CIR（継続的改善レジスター）のレコード**として扱い、ステータスは **ラベル**で管理します（ラベル接頭辞: `状態/`）。

### ステータス一覧（推奨8状態）

#### 1) New（新規）
- **意味**：改善機会として受け付け、CIR に登録した直後（まだ評価していない）。
- **入る条件**：要望/気づき/レビュー結果を受領してレコード作成（新規起票）。
- **出る条件**：重複チェック、カテゴリ付け、一次オーナー仮アサイン完了 → **Assess**へ。
- **主担当**：継続的改善（CI）オーナー/受付窓口
- **ラベル**：`状態/New`

#### 2) Assess（評価）
- **意味**：実施可否・優先度を決めるための情報収集と整理中。
- **この状態で埋める/決める（最低限）**：目的/期待効果、対象（サービス/機能/データ/環境）、リスク、概算、成功指標（KPI）と測定方法。
- **出る条件**：やる → **Approved** / やらない → **Rejected** / 前提待ち → **On Hold**
- **主担当**：改善オーナー（プロダクト/運用）＋関係者レビュー
- **ラベル**：`状態/Assess`

#### 3) Approved（承認済み）
- **意味**：実施決定。優先度とリソース枠が確保され、着手準備 OK。
- **この状態で確定**：スコープ、完了条件（DoD）、期限/マイルストーン、実装手段（チケット/変更/リリース計画への紐づけ）。
- **出る条件**：実作業開始 → **Implement**
- **主担当**：改善委員会/プロダクト責任者/運用責任者（承認者）
- **ラベル**：`状態/Approved`

#### 4) Implement（実施中）
- **意味**：設計・実装・検証・展開を進めている状態（PoC→段階導入も含む）。
- **この状態で管理**：進捗、リスクと対策（ロールバック含む）、変更・リリースとの整合。
- **出る条件**：本番反映/提供開始（または PoC 終了）→ **Review**
- **主担当**：実装チーム（SRE/Dev/運用自動化チーム等）
- **ラベル**：`状態/Implement`

#### 5) Review（効果確認）
- **意味**：実装は完了。効果測定・運用影響・学びのレビュー中。
- **この状態でやること**：KPI達成度、期待効果 vs 実績、副作用、ナレッジ/手順/監視設定/CMDB 等の更新要否。
- **出る条件**：成果 OK → **Closed** / 追加改善が必要 → **Implement** へ戻す（または新規改善として **New** 起票）。
- **主担当**：改善オーナー＋運用責任者（必要に応じてレビュー会）
- **ラベル**：`状態/Review`

#### 6) Closed（クローズ）
- **意味**：レビューまで完了し、記録が確定。監査・振り返りに耐える状態。
- **クローズ時に残す**：結果サマリ、実績KPI、実コスト、学び、関連リンク（変更/リリース/チケット/手順書）。
- **主担当**：継続的改善（CI）オーナー
- **ラベル**：`状態/Closed`

### 例外状態（運用を詰まらせない）

#### 7) On Hold（保留）
- **意味**：やりたいが、前提条件が未達で止めている（却下ではない）。
- **必須項目**：保留理由、再開条件、見直し日（次回レビュー日）。
- **戻り先**：条件達成 → **Assess**（運用により Approved へ戻すのも可）
- **主担当**：改善オーナー
- **ラベル**：`状態/On Hold`

#### 8) Rejected（却下）
- **意味**：現時点で実施しない決定（却下として記録を残す）。
- **必須項目**：却下理由（効果薄/コスト過大/重複/対象外/リスク過大/代替あり）。
- **再起票**：状況が変わったら **New** で再登録し、旧 Issue をリンクする。
- **主担当**：承認者（または CI オーナー）
- **ラベル**：`状態/Rejected`

## 運用ルール（最小）
- **Assess のSLA**：例「受付から10営業日以内に Approved/On Hold/Rejected のどれかにする」
- **On Hold の棚卸し**：例「月1回、再開条件と見直し日で棚卸し」
- **Closed の品質**：KPI結果と学びが空欄ならクローズしない

## After
松井「これ、工数15%減だね」
→ 改善が“成果物”に

## CMDB 設定（Grafanaダッシュボード）
- 設定先: `cmdb/<組織ID>/<サービスID>.md` の `grafana.usecase_dashboards`
- 対象ユースケース: `04_continual_improvement`（継続的改善）
- ダッシュボードは CI が自動同期（1時間毎 + CMDBの作成/更新/削除）
- APIキー: CI/CD 変数 `GRAFANA_API_KEY`
- データソース設定方法: [`docs/monitoring_unification_grafana.md`]({{GITLAB_BASE_URL}}/{{GROUP_FULL_PATH}}/{{SERVICE_MANAGEMENT_PROJECT_PATH}}/-/blob/main/docs/monitoring_unification_grafana.md)

```yaml
grafana:
  usecase_dashboards:
    - org_id: <組織ID>
      usecase_id: 04_continual_improvement
      usecase_name: 継続的改善
      dashboard_uid: gm-continual-improvement
      dashboard_title: Continual Improvement Overview
      folder: ITSM - 一般管理
      data_sources:
        - name: athena
          type: athena
          purpose: 集計/レポート指標（ログ/メトリクス集計）
      panels:
        - panel_title: 改善件数
          metric: improvement_count
          data_source: athena
          position:
            x: 0
            y: 0
            w: 12
            h: 6
        - panel_title: 効果達成率
          metric: benefit_realization
          data_source: athena
          position:
            x: 12
            y: 0
            w: 12
            h: 6
        - panel_title: 実施率
          metric: adoption_rate
          data_source: athena
          position:
            x: 0
            y: 6
            w: 12
            h: 6
        - panel_title: アクション残
          metric: action_items
          data_source: athena
          position:
            x: 12
            y: 6
            w: 12
            h: 6
```

## イベント通知（AWS）
- 通知ルート: CloudWatch → n8n → Zulip / GitLab / Grafana
- 通知イベント種別: 改善遅延 / 効果未達
- Zulip チャンネル: #gm-improvement
- n8n がイベントを受信して分類（重大度/カテゴリ/対象サービス）し、GitLab Issue/コメントとZulip通知を発行
- Grafana にはイベントに対応するダッシュボードURLを添付し、CMDBの `grafana.usecase_dashboards` と紐付ける
