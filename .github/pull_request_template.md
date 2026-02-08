## 目的 / 背景

## 変更内容

## 影響範囲

## リスクとロールバック

## 検証

- [ ] `terraform fmt -recursive`
- [ ] `terraform init -backend=false`
- [ ] `terraform validate`

## チェック（該当するもの）

- [ ] 秘密情報（tfvars/state/log/evidence）をコミットしていない
- [ ] 破壊的変更/コスト影響があれば明記した
- [ ] ドキュメントを更新した（必要な場合）

