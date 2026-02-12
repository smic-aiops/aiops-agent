# OQ: SoR Ops - dry-run（計画/SQL 出力）

## 目的

SoR ops の主要スクリプトが `--dry-run` / `--plan-only` で停止し、外部への書き込みなしに計画を出力できることを確認する。

## 受け入れ基準

- 各スクリプトが `exit 0` で終了する
- DB へ変更を書き込まない（`--dry-run` / `--plan-only` の範囲）

## 手順（例）

`apps/itsm_core/sor_ops/scripts/run_oq.sh` を利用する。

