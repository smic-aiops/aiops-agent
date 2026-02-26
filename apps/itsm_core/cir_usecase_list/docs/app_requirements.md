# CIR Approved Usecase List 要求（Requirements）

本書は `apps/itsm_core/cir_usecase_list/` の要求（What/Why）を定義します。実装の正は `apps/itsm_core/cir_usecase_list/workflows/` を正とします。

## 1. 対象

GitLab 一般管理プロジェクトの CIR（継続的改善レジスター）＝ GitLab Issue を検索し、`状態/Approved` のレコードを一覧してユースケース機能ID（`UC-*`）を抽出する n8n ワークフロー。

## 2. 目的

- Approved な改善機会（CIR）を機械的に列挙できるようにし、後続のドキュメント更新・同期処理の入力として利用可能にする。
- 抽出結果に Issue URL/ID を含め、監査・追跡可能性を確保する。
- 本ワークフロー自体は docs を更新しない。docs 反映は別工程（LLM プロンプト）で行い、更新先は `vendor/<name_prefix>/apps/*/realms/<realm_key>/docs/` の realm overlay に限定する（共通ベース docs は read-only とみなす。`name_prefix` は `terraform output -raw name_prefix` を正とする）。

## 3. 代表ユースケース

- UC-ITSM-06: CIR（一般管理/継続的改善）で `状態/Approved` の Issue を一覧し、ユースケース機能ID（`UC-*`）を抽出して返せる

## 4. 機能要件（要約）

- `POST /webhook/itsm/cir/usecases/approved/list` で一覧を返すこと
- `ITSM/継続的改善` と `状態/Approved` を AND 条件としてフィルタできること（必要に応じて上書き可能）
- `dry_run=true` で外部 API を呼ばずに応答できること
