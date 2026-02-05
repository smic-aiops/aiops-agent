# 変更管理（構成/ポリシー/プロンプト）

## 1. 対象と変更区分
- **構成（Infrastructure）**: `main.tf` / `variables.tf` / `modules/**` / `terraform.*.tfvars`
- **ポリシー（Policy）**: `apps/aiops_agent/data/default/policy/**`
- **プロンプト（Prompt）**: `apps/aiops_agent/data/default/prompt/**`
  - レルム別の上書きが必要な場合: `apps/aiops_agent/data/<realm>/{policy,prompt}/**`
- **ワークフロー（Workflow）**: `apps/aiops_agent/workflows/**`

## 2. 変更フロー（レビュー/承認/ロールバック）
1. **起案**: 変更理由、影響範囲、ロールバック手順、検証観点を明記する。
2. **レビュー**: PR を作成し、`terraform plan` 結果やワークフロー差分を添付する。
3. **承認**: 変更区分ごとの承認者がレビュー結果を承認し、実施時間帯を確定する。
4. **適用**: 検証環境 → 本番の順で適用し、結果を記録する。
5. **検証**: 監視/動作確認を実施し、問題がなければクローズする。
6. **ロールバック**: 失敗や影響があれば直ちに前版へ戻し、再評価する。

### ロールバック指針
- **Terraform 構成**: 直前の安定コミットに戻し、同じ `-var-file` セットで `terraform apply`。
- **ポリシー/プロンプト/ワークフロー**: 直前の JSON/TXT に戻し、`apps/aiops_agent/scripts/deploy_workflows.sh` で再同期。
- **データ変更**: 事前バックアップがない場合は保守作業扱いとし、復旧計画を最優先する。

## 3. 本番・検証環境の同期方法
1. **検証環境で先行適用**
   - `terraform plan -var-file=...` を取得し、影響をレビューする。
   - n8n 変更は `apps/aiops_agent/scripts/deploy_workflows.sh` を先に検証環境で実行する。
2. **差分確認**
   - `terraform plan` の差分が想定外の場合は適用を止める。
3. **本番へ反映**
   - 検証結果のサマリを添付し、本番に同一の変更セットを適用する。

## 4. 監査ログ（変更者/変更理由の記録）
### 必須記録項目
- 変更者、レビュー者、承認者
- 変更理由（背景/課題/期待効果）
- 影響範囲（サービス/CI/依存システム）
- 実施日時、検証結果、ロールバック結果
- 関連コミット/PR、`terraform plan` の要約

### 記録先（最低限）
- **GitLab PR**: 変更理由・影響・ロールバックを記載し、レビュー/承認履歴を残す。
- **変更台帳**: 変更内容の履歴をページで管理する（テンプレを維持）。
- **システムログ**: `aiops_prompt_history`（プロンプト履歴）や CloudWatch Logs を参照可能にする。

### 変更台帳テンプレ（例）
- 変更ID / タイトル / 変更者 / 承認者 / 実施日
- 変更理由 / 影響範囲 / ロールバック
- 参照リンク（PR, plan, runbook）

## 5. 修正ログ

