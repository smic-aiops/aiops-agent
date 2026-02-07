# apps/aiops_agent/schema

このディレクトリは、**LLM（Chat ノード）の入出力契約（JSON Schema）**を `prompt_key` 単位でバージョン管理します。

## 命名規約

- 入力スキーマ: `<prompt_key>.input.json`
- 出力スキーマ: `<prompt_key>.output.json`

例:

- `adapter.classify.v1.input.json`
- `adapter.classify.v1.output.json`

## 目的

- `prompt_key` ごとに「LLM に渡す JSON」「LLM が返す JSON」を明文化し、破壊的変更をレビューしやすくする
- 仕様書（`apps/aiops_agent/docs/aiops_agent_specification.md`）の「prompt_key と JSON Schema の 1 対 1」の根拠配置とする

## 運用

- `apps/aiops_agent/workflows/*.json` 内の `prompt_key: '...'` と **1 対 1** で対応する `*.input.json` / `*.output.json` を用意します。
- 追加/変更時は `apps/aiops_agent/scripts/validate_llm_schemas.sh` を実行して整合性を確認します。

