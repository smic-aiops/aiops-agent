# OQ: CIR Issue Close

## 目的
`POST /webhook/itsm/cir/issues/close` が、CIR Issue を **`状態/Closed` + close + note 追記**でき、かつ **重複 note が出ない**ことを確認します。

## 手順（最小）
1. スモーク（dry-run）: `apps/itsm_core/cir_issue_close/scripts/run_oq.sh --dry-run` を実行し、叩くべき webhook が表示されることを確認する
2. 疎通（apply）: `apps/itsm_core/cir_issue_close/scripts/run_oq.sh` を実行し、`/test` が 200 で返ることを確認する
3. 計画確認: `POST /webhook/itsm/cir/issues/close` を `dry_run=true` で実行し、対象 Issue と更新内容（計画）が返ることを確認する（スクリプトが同時に実施）
4. 実運用で、system.md 実行が完了した後に `dry_run=false` で実行する
5. GitLab Issue に以下が反映されることを確認する
   - `状態/Closed` の付与（他 `状態/*` の除去）
   - Issue state が closed
   - 自動コメント（marker 付き）の追記
6. 同じ入力を再送しても、同じ marker の note が増えないことを確認する（force_note=false）
