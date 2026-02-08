# コントリビューションガイド（CONTRIBUTING）

aiops-agent へのコントリビューションを歓迎します。まずは Issue で目的・背景・影響範囲を共有し、合意を取ってから実装に入ることを推奨します（特にインフラ変更や運用手順変更）。

## 重要な注意（必読）

- このリポジトリは **Terraform により実際の AWS リソースを作成**します。検証目的でも **課金・セキュリティ影響**が発生します。
- `terraform.tfstate` / `*.tfvars` / ログ / 証跡には秘密情報が含まれる可能性があります。**絶対にコミットしない**でください（`.gitignore` で除外しています）。
- 変更は最小にし、意図とリスク、検証（DQ/IQ/OQ/PQ も含む）の証跡を残してください。

## 開発環境（ローカル）

- Terraform: `1.14.3`（`.terraform-version`）
- AWS CLI v2、Docker、`jq`、GNU `tar`

## 変更前のセルフチェック（最低限）

Terraform の構文チェックは、AWS へ接続せずに実行できます。

```bash
terraform fmt -recursive
terraform init -backend=false
terraform validate
```

## 変更の作法（推奨）

- **小さな PR**に分ける（インフラ変更とスクリプト/ドキュメント変更は可能なら分離）
- 破壊的変更（変数名変更、output 変更、デフォルト挙動変更）は Issue で先に相談
- スクリプトは `set -euo pipefail` を維持し、`DRY_RUN`（または `--dry-run`）を提供する

## PR に含めてほしい情報

- 変更目的（何を解決するか）
- 影響範囲（どのサービス/モジュール/ワークフローに影響するか）
- リスク（セキュリティ・コスト・運用影響）とロールバック方針
- 検証内容（実行コマンド、出力、証跡の保存先）

## ドキュメント更新

運用手順や構成の前提が変わる場合は、該当する README / `docs/` を更新してください。

入口:
- `README.md`
- `docs/README.md`
- `docs/infra/README.md`
- `docs/itsm/README.md`
- `docs/apps/README.md`

