# ユースケース 設計/実装 ギャップ（自動抽出）

- 生成日: 2026-02-26
- 入力: `docs/itsm/itsm_oss_features.csv`

## 判定基準
- 設計済み: `apps/itsm_core/bootstrap/data/templates/**/docs/usecases/*.md.tpl` または `apps/**/docs/**/*.md` に `UC-XXXX` が出現
- 実装状況: `itsm_oss_features.csv` の `本レポジトリシステムでの実現状況`（`⭕️/🔺/❌`）

## 件数
- 全ユースケース: 1241
- 設計されていない: 0
- 実装状況=⭕️: 300
- 実装状況=🔺: 651
- 実装状況=❌: 290
- 設計されていない かつ 実装状況=❌: 0

## 出力
- 未設計: `docs/itsm/usecase_design_missing_2026-02-26.csv`
- 未実装(❌): `docs/itsm/usecase_impl_missing_2026-02-26.csv`
- 部分実装(🔺): `docs/itsm/usecase_impl_partial_2026-02-26.csv`
- 未設計かつ未実装(❌): `docs/itsm/usecase_design_and_impl_missing_2026-02-26.csv`
