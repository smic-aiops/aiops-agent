# DQ: ITSM Bootstrap

## 目的
設計（テンプレ/参照先/スクリプト構造）が意図どおりであることを最小で示す。

## チェック（最小）
- テンプレの正が `apps/itsm_core/bootstrap/data/templates/` に集約されていること。
- ブートストラップ実行スクリプトの入口が `apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh` であること。
- ユースケース関連の参照（`UC-*` のテンプレ参照）が新パスを指していること。

## 証跡
- Git の差分（PR/MR）と `apps/itsm_core/bootstrap/scripts/run_oq.sh` の結果を証跡とする。

