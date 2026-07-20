## 種別
種別：変更

## 顧客ID（CMDB）
（例: CUST-001）

## 対象サービス
（例: Sulu）

## 現行バージョン
（例: 3.0.3）

## 修正対象バージョン
（例: 3.0.4）

## ビルド定義ref（任意）
（CodeBuild定義と管理済みoverrideを取得するGit branch、tag、またはcommit SHA。未指定時はmain）

## 変更内容

## 目的

## 影響範囲

## 実施予定
YYYY/MM/DD HH:MM

## ロールバック手順

## ECRイメージ作成
- 新規タグのみを使用する（既存タグは上書きしない）
- `latest`タグは更新しない
- 実行時は`push_images=true`と`allow_ecr_push=true`を明示する

## 承認
承認者：
承認後は承認ラベルを付与し、`/approve`または「CAB approved」「承認済」の承認ノートを記録する。
