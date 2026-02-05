# CSV 最小フロー（GAMP® 5 2nd / CSA 前提）

本書は、本リポジトリで「最小で試す」ための進め方（導線）をまとめたものです。  
監査向けの構成説明はルートの `README.md` を正とし、詳細は `docs/README.md` と各アプリ配下の `apps/*/README.md` を参照してください。

## 方針

- サービス管理者がプロンプト/ポリシー/ワークフローを中心に編集し、価値を検証する想定
- 「便利になった？」「コストは？」「判断は速くなった？」を指標で比較し、価値を確認する

## 進め方（ステップ）

- ステップ 1（構築/IQ 前提）: 環境を構築する
- ステップ 2（構成/DQ 前提）: ITSM を構築する
- ステップ 3（要件/仕様）: AI Ops 検証シナリオを考える
- ステップ 4（構成/仕様）: サービスリクエスト ワークフローを整備する
- ステップ 5（導入/IQ-OQ）: AIOps Agent をデプロイする
- ステップ 6（OQ/PQ）: AI Ops 検証シナリオを実行する（証跡を残す）

## ドキュメントガイド（フェーズ別）

### ステップ 1（構築/IQ 前提）：環境を構築する

- 環境構築ガイド: `docs/setup-guide.md`
- 環境の利用手順と SSO の流れ: `docs/usage-guide.md`

### ステップ 2（構成/DQ 前提）：ITSM を構築する

- 本プロトタイプ環境では、ITSM 構成サービスとして、認証：Keycloak / チャット：Zulip / レポジトリ：GitLab / ローコード：n8n を固定する想定
- サービス運用基盤の想定と ITSM + AI Ops の方針: `docs/itsm/itsm-platform.md`
- ITSM セットアップ手順（n8n イメージ更新など）: `docs/itsm/README.md`

### ステップ 3（要件/仕様）：AI Ops 検証シナリオを考える

- 例: `sulu` サービスをメインサービスに見立て、モニタリング通知ログやチャットから通知を受け、AIOps Agent が（承認を挟みつつ）自動化を実行する運用を想定する

### ステップ 4（構成/仕様）：AIOps Agent / ワークフローを整備する

- 要件（URS 相当）: `apps/aiops_agent/docs/app_requirements.md`
- 仕様（FS/DS 相当）: `apps/aiops_agent/docs/aiops_agent_specification.md`
- 設計: `apps/aiops_agent/docs/aiops_agent_design.md`
- 実装メモ: `apps/aiops_agent/docs/aiops_agent_implementation.md`
- 代表例（ワークフロー側の OQ）: `apps/workflow_manager/docs/oq/oq.md`

### ステップ 5〜6（IQ/OQ/PQ）：検証を実行し、証跡を残す

- DQ/IQ/OQ/PQ: `apps/aiops_agent/docs/{dq,iq,oq,pq}/`
- 証跡保存・変更記録: `docs/change-management.md`

### その他

- Codex/開発エージェント向け運用ルール: `AGENTS.md`
