# OQ: ITSM Bootstrap

## 目的
重要機能（テンプレ参照の一貫性、スクリプトの実行入口、静的チェック）が意図どおり成立することを確認する。

## 実行（推奨）

```bash
apps/itsm_core/bootstrap/scripts/run_oq.sh --dry-run
```

## 実行（GitLab 管理 API スモーク）

```bash
# API 呼び出し内容のみ確認
apps/itsm_core/bootstrap/scripts/run_oq.sh --with-gitlab-smoke --dry-run

# 実 API 実行（OQ 用 Issue を 1 件作成して close）
apps/itsm_core/bootstrap/scripts/run_oq.sh --execute-gitlab-smoke
```

## 期待結果（最小）
- 参照パス（旧ディレクトリ名等）が残っていないこと。
- 主要スクリプトの `bash -n` が成功すること。
- テンプレート（SSoT）ディレクトリが存在し、代表ファイルが見つかること。
- （`--with-gitlab-smoke` / `--execute-gitlab-smoke` 時）GitLab の project / board / milestone / issue / markdown API が成功すること。
