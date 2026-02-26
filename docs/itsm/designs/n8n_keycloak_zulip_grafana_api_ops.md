# API/運用（n8n / Keycloak / Zulip / Grafana）設計

対象:
- `docs/itsm/itsm_oss_features.csv` の以下（ソフトウェア開発および管理）
  - Grafana: `UC-2824`（Annotations API）
  - Keycloak: `UC-2825` `UC-2826`（Clients / Service accounts）
  - Zulip: `UC-2827` `UC-2828`（Get messages / Upload file API）
  - n8n: `UC-2829`〜`UC-2833`（API Playground / CLI / nodes / triggers / metadata）

## 共通方針

- 認証/認可は Keycloak（OIDC）を正とし、各アプリ固有 token は SSM/Secrets Manager に置く。
- API/CLI の利用は GitLab CI（Runner）から実行できる状態を目標にする（人手作業の属人化を避ける）。
- 監査/証跡は GitLab の Job log / Artifact / Issue コメントに残す。

## Grafana（UC-2824）

- 目的: デプロイ/変更/障害などのイベントを Annotation として残し、ダッシュボード上で時系列相関を追えるようにする。
- 実行: GitLab CI から Grafana Annotations API を呼び出す（API Key は GitLab CI variables で管理）。

## Keycloak（UC-2825, UC-2826）

- 目的: アプリ連携（client）と機械認証（service account）を統一し、token の配布/失効/ロール付与を運用可能にする。
- 実行: realm/client を Terraform と `scripts/itsm/keycloak/*` 系で反映し、サービス間 token は短命化を優先する。

## Zulip（UC-2827, UC-2828）

- 目的: bot によるメッセージ取得（narrow）とファイルアップロードを可能にし、通知/レポート/証跡添付の基盤にする。
- 実行: Zulip bot の API key を SSM 経由で注入し、GitLab CI / n8n から API を呼ぶ。

## n8n（UC-2829〜UC-2833）

- 目的: API/CLI によるワークフロー運用（インポート/実行/メタ取得）を標準化する。
- 実行:
  - API Playground は「疎通/検証」用途に限定し、本番運用は Git 管理（workflow 同期）を正とする。
  - CLI は一括インポート/バックアップ/移行に利用し、手順は GitLab の runbook として版管理する。

## UC 対応（この設計でカバー）

`UC-2824` `UC-2825` `UC-2826` `UC-2827` `UC-2828` `UC-2829` `UC-2830` `UC-2831` `UC-2832` `UC-2833`

