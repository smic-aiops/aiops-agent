# PQ（性能適格性確認）: CIR Issue Close（ITSM Core）

## 目的

代表的な実行頻度において、Issue 更新/close が安定して処理できることを確認する（最小）。

## 対象

- ワークフロー（正）: `apps/itsm_core/cir_issue_close/workflows/`
- 外部 API: GitLab API（Issue update/close）

## 指標（最低限）

- 応答/実行時間が過度に伸びない（滞留しない）
- 失敗率が許容範囲内である（リトライ/再実行で回復できる）
- 冪等性（重複 close/note を発生させない）が成立する（実装を正とする）

## 実施方法（最小）

- OQ の代表シナリオを複数回実行し、結果ログ（HTTP ステータス/失敗理由）を保存する

## 証跡（evidence）
- 実行ログ（タイムスタンプ、対象 Issue、結果）
