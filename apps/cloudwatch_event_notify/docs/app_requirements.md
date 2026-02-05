# CloudWatch Event Notify 要求（Requirements）

本書は `apps/cloudwatch_event_notify/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/cloudwatch_event_notify/README.md` と `apps/cloudwatch_event_notify/docs/`、ワークフロー定義、同期スクリプトを正とします。

## 1. 対象

AWS の監視イベント（CloudWatch Alarm / SNS 通知など）を受け取り、ITSM のインシデント通知として整形し、Zulip/GitLab/Grafana へ連携する n8n ワークフロー群。

## 2. 目的

監視イベントを「運用者が即判断できる通知」に最小の加工で変換し、到達性と追跡性（リンク/メタデータ）を確保する。

## 2.1 代表ユースケース（DQ/設計シナリオ由来）

本セクションは `apps/cloudwatch_event_notify/docs/dq/dq.md` の設計スコープ/主要リスクを、運用上のユースケースへ落とし込んだものです。

- UC-CW-01: CloudWatch/SNS 通知を受信し、整形して Zulip へ通知する（必要情報を抽出し、運用者が判断できる要約を投稿）
- UC-CW-02: dry-run で外部送信せず、整形結果のみを確認する（誤通知リスクを抑止して検証する）
- UC-CW-03: Webhook トークン検証で不正送信を拒否する（`N8N_CLOUDWATCH_WEBHOOK_SECRET` 適用時）
- UC-CW-04: 複数チャネルの部分失敗を可視化し、全体として完走する（例: Zulip 成功 + GitLab 失敗を `results[]`/`status_code=207` で表現）
- UC-CW-05: 送信先（Zulip/GitLab/Grafana）を段階的に有効化し、影響範囲を制御する

## 3. スコープ

### 3.1 対象（In Scope）

- CloudWatch/SNS 通知ペイロードの受信
- 重大度/カテゴリ/対象サービス等の整形・分類
- Zulip への通知投稿
- （任意）GitLab への記録連携（Issue/コメント等）
- （任意）Grafana 参照/Annotation 用のリンク生成
- 構成による有効/無効化、および dry-run による整形結果の確認

### 3.2 対象外（Out of Scope）

- CloudWatch/SNS 自体の設定・運用の妥当性（監視設計）
- Zulip/GitLab/Grafana 自体の製品バリデーション
- 外部送信先の権限管理の詳細設計（必要最小権限の方針は要件に含む）

## 4. 機能要件（要約）

- 入力: CloudWatch/SNS 由来のイベント通知（Webhook 受信）
- 処理: 重要情報の抽出、通知本文の整形、関連リンク（GitLab/Grafana 等）の付与
- 出力: Zulip 投稿（任意で GitLab 記録 / Grafana 参照）
- テスト: 手動入力で整形結果を再現できるテスト用 Webhook を備える

## 5. 非機能要件（共通）

- セキュリティ: Webhook 受信の検証（トークン等）と、外部 API トークンの最小権限運用
- 可用性: 一時障害時のリトライ/再送で通知欠落を抑制する
- 冪等性: 同一イベントの重複通知を抑制できること（キー/条件は実装・ポリシー側で定義）
- 運用性: 外部送信を止められる dry-run を提供し、出力の確認を容易にする
