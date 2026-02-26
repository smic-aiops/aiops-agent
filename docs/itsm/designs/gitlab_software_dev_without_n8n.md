# ソフトウェア開発および管理（n8n 非依存）設計: GitLab + GitLab Runner

本設計は、`docs/itsm/itsm-platform.md` の方針に従い、**n8n に依存しない**開発管理ユースケース（`docs/itsm/itsm_oss_features.csv` の `ソフトウェア開発および管理`）を GitLab と GitLab Runner の範囲で実現するための設計メモです。

対象（CSV のユースケース群）:
- ソフトウェア開発および管理: `UC-2701`〜`UC-2823` のうち、n8n を前提にしないもの

## 前提

- GitLab を開発の正本（Repo/MR/Issue/Release）として採用する
- GitLab Runner は本基盤（ECS/Fargate shell executor）を利用し、プロジェクト横断で使えるタグ設計を行う
  - runner 作成/更新は `scripts/itsm/gitlab/ensure_gitlab_runner.sh` を利用する

## 標準構成（プロジェクトテンプレ）

- ブランチ保護
  - `main`（または `master`）は protected にし、直接 push を禁止
  - merge は MR 経由のみ（レビュー/承認を必須化）
- レビュー運用
  - CODEOWNERS を採用し、責任境界（チーム/領域）を明確化
  - MR approval を「最低 1 名」から開始し、重要リポジトリは段階的に引き上げる
- CI/CD
  - `.gitlab-ci.yml` はテンプレ化し、共通の検査（lint/test）と成果物（artifact）生成を標準化
  - リリースは tag + release notes（Release API）を正とする

## ユースケース実現の基本パターン

- 自動マージ/マージレビュー
  - merge request を前提にし、MR approval / pipeline success を gate にする
  - merge train（利用可能なら）を有効化し、直前の競合を減らす
- 課題/リリース API
  - GitLab API（Issues API / Releases API）を標準の連携点とする
  - パイプラインから API を呼ぶ場合は、GitLab CI の token/variables を使用する（n8n は不要）
- コンテナ/パッケージ/アーティファクト
  - GitLab Container Registry / Generic packages registry を利用して配布経路を統一する
  - 署名/検証が必要な成果物は CI ジョブで署名し、デプロイ側で検証する
- コード品質監視
  - CI で静的解析/テストを実行し、レポート（artifact）として保持する
  - 「品質の正」は pipeline 結果と artifact とする

## Runner 運用（最小）

- タグ設計: `itsm` / `prod` / `staging` 等の環境タグ + 役割タグ（例: `build`, `deploy`）
- run_untagged は原則 false（意図しないジョブ実行を避ける）
- token は SSM に保管し、Terraform から Runner タスクへ注入する（詳細は `modules/stack/ecs_tasks.tf` と `scripts/itsm/gitlab/ensure_gitlab_runner.sh`）

