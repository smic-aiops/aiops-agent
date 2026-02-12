# DQ（設計適格性確認）: Zulip Stream Sync

## 目的

- CMDB 等の入力に従い、Zulip ストリームの作成/アーカイブを安全に自動化する設計前提・制約・主要リスク対策を明文化する。
- 変更時に再検証（OQ 中心）の判断ができる状態にする。

## 対象（SSoT）

- 本 README: `apps/itsm_core/zulip_stream_sync/README.md`
- 要求/ユースケース: `apps/itsm_core/zulip_stream_sync/docs/app_requirements.md`
- ワークフロー:
  - `apps/itsm_core/zulip_stream_sync/workflows/zulip_stream_sync.json`
  - `apps/itsm_core/zulip_stream_sync/workflows/zulip_stream_sync_test.json`
- 同期スクリプト: `apps/itsm_core/zulip_stream_sync/scripts/deploy_workflows.sh`
- OQ: `apps/itsm_core/zulip_stream_sync/docs/oq/oq.md`
- CS: `apps/itsm_core/zulip_stream_sync/docs/cs/ai_behavior_spec.md`

## 設計スコープ（In/Out）

- 対象:
  - 入力に従い `action=create|archive` を実行し、Zulip ストリーム状態を同期する
  - dry-run により入力検証のみを実行できる
  - 冪等（既に存在/既にアーカイブ等）を許容し、安全側で完走する
  - `realm`（tenant）に応じて接続先/認証情報を切り替えられる（単一ワークフローで複数環境運用）
- 非対象:
  - Zulip 自体の製品バリデーション
  - CMDB 側の正当性保証（入力品質は別途）
  - Webhook 入口の認証・アクセス制御（運用/インフラ側で制御する）

## 前提・制約

- Zulip API への認証は Bot の `email + API key` を使用する（ワークフロー内で Basic 認証ヘッダを生成）。
- 秘匿情報（token 等）は tfvars に平文で置かず、SSM/Secrets Manager から n8n の環境変数へ注入する。
- 本アプリは「安全側の冪等完走」を優先し、存在確認・未存在の扱いはエラーにしない（仕様は下記参照）。

## 今回のDQ改善点（2026-02-03）

1. UC-ZS-08（資格情報不足の fail-fast）を要求へ追加し、DQ/OQ とトレースできるようにする（対応済）
2. DQ シナリオへ「資格情報不足の fail-fast」を追加し、OQ（`oq_zulip_stream_sync_missing_creds_failfast.md`）と紐付ける（対応済）
3. 入力別名（`stream_name`/`stream`、`stream_id`/`zulip_stream_id`、`description`/`stream_description`）の優先順位を明文化し、曖昧入力の解釈ブレを抑止する（対応済）
4. `invite_only` の既定値（未指定は `true`）と、入力値の許容（真偽値/文字列）を明文化する（対応済）
5. テスト Webhook（`/webhook/zulip/streams/sync/test`）の入力/合否（`strict`）とステータスコードを DQ 側へ追記し、IQ/OQ の前提を一貫化する（対応済）
6. 早期失敗（`status_code=424`）時の応答キー（`missing` 等）と、外部 API を呼ばないことを仕様として明確化する（対応済）
7. ログ/証跡の推奨キーに `missing` を追加し、資格情報不足の原因追跡を改善する（対応済）
8. 変更管理（再検証トリガ）へ「資格情報解決仕様（N8N_ZULIP_* のマッピング）と test webhook の strict 仕様」を追記し、影響評価の漏れを減らす（対応済）
9. OQ のケース表へ「資格情報不足の fail-fast」を追記し、運用試験の入口で見落としにくくする（対応済）
10. `system.md` 実行時の証跡（差分/日時/対象 realm/結果）に「fail-fast の観点」を含め、次回以降の監査性を補強する（対応済）

## 今回のDQ改善点（2026-02-01）

1. DQ から参照している OQ 文書の欠落を解消する（対応済）
2. `realm` 切替の OQ を追加し、証跡化を必須化する（対応済）
3. 応答へ `realm`/`zulip_base_url` を必須化し、追跡性を強化する（対応済）
4. テスト Webhook の env 健全性確認を「本番と同じ解決仕様（realm マッピング含む）」へ整合する（対応済）
5. `upstream_body` のセンシティブキーをマスクし、秘匿情報露出リスクを低減する（対応済）
6. OQ 実行スクリプトを fail-fast（非2xx/`ok=false`）にし、プリフライトの停止条件を明確化する（対応済）
7. OQ ケース表へ traceability（`realm`/`zulip_base_url`）の確認を追加する（対応済）
8. IQ の合否判定を「マッピングを含む必須 env」の観点で明確化する（対応済）
9. PQ の追跡性観点（環境差分/誤接続の追跡）を明文化する（対応済）
10. system.md 実行の証跡に、対象 realm・実施日時・差分・結果（センシティブマスク）を必ず残す（対応済）

## 入力仕様（Webhook body）

### 必須

- `action`: `create` / `archive`（小文字化して判定）

### 条件付き必須

- `action=create` の場合: `stream_name`（別名: `stream`）
- `action=archive` の場合: `stream_name`（別名: `stream`）または `stream_id`（別名: `zulip_stream_id`）

### 任意

- `realm` / `tenant`: 接続先/認証情報の切替キー（未指定は `default`）
- `stream_description` / `description`: `create` 時の description
- `invite_only`: `create` 時の公開設定（未指定は `true`）
- `dry_run`: `true` 相当の値で dry-run を有効化

### 別名（alias）と優先順位

入力に別名が混在している場合は、以下の優先順位で採用する（上が優先）:

- `stream_name`: `stream_name` → `stream`
- `stream_id`: `stream_id` → `zulip_stream_id`
- `description`: `description` → `stream_description`
- `realm`: `realm` → `tenant`

### 値の正規化（最低限）

- 文字列は前後の空白を `trim` して扱う（空文字列は未指定扱い）
- `invite_only` は真偽値または真偽値相当の文字列を許容する（未指定は `true`）

### dry-run の有効化条件（同等扱い）

- 入力の `dry_run=true`
- 環境変数の `ZULIP_STREAM_SYNC_DRY_RUN=true`
- 環境変数の `DRY_RUN=true`

## 接続先/認証情報（realm 解決）

### realm の決定

以下の順で `realm` を決定する（最初に見つかった非空文字列を採用）:

1. `body.realm`
2. `body.tenant`
3. `body.reply_target.tenant`
4. `body.reply_target.realm`
5. 環境変数 `N8N_REALM`
6. `default`

### Zulip 接続先（base URL）

- `N8N_ZULIP_API_BASE_URL`
- それ以外は `ZULIP_BASE_URL` / `N8N_ZULIP_API_BASE_URL` にフォールバック
- 入力は `.../api/v1` の有無を許容し、内部では正規化して `/api/v1` を付与して呼び出す

### Bot email / token

- email:
  - `N8N_ZULIP_BOT_EMAIL`
  - それ以外は `ZULIP_BOT_EMAIL` / `N8N_ZULIP_BOT_EMAIL`
- token:
  - `N8N_ZULIP_BOT_TOKEN`
  - それ以外は `ZULIP_BOT_API_KEY` / `N8N_ZULIP_BOT_TOKEN` / `ZULIP_BOT_TOKEN`

### 不足時の扱い

- dry-run 以外で `baseUrl` / `email` / `token` が不足している場合は、`status_code=424` で失敗する（失敗時も秘匿情報は返さない）。

## テスト Webhook（/test）入力仕様（接続検証）

- 対象: `POST /webhook/zulip/streams/sync/test`（ワークフロー: `zulip_stream_sync_test.json`）
- 入力（JSON）:
  - `strict`（任意）: `true` の場合、必須 env が不足していれば `status_code=424` で失敗する
  - `strict` が未指定（または false 相当）の場合、必須 env が不足していても `ok=true` で返す（ただし `missing` は返す）

## 主要リスクとコントロール（最低限）

- 誤操作（誤った stream を作成/アーカイブ）
  - コントロール: 入力 validation、冪等、dry-run、OQ で確認
- 認証情報漏えい（Zulip token）
  - コントロール: SSM/Secrets Manager 管理、tfvars 平文禁止
- 誤った接続先/認証情報の選択（realm 切替の誤り）
  - コントロール: `realm` 解決規則の明文化、OQ シナリオ追加、レスポンス/ログに `realm` を含めて追跡性を確保する
- 不正な入力経路（Webhook 入口の露出）
  - コントロール: アクセス制御は運用/インフラ側（Allowlist/WAF/内部ネットワーク）で実施し、アプリ側は厳格な入力検証と dry-run による事前確認を提供する

## 振る舞い（処理仕様）

### 共通

- `action` が不正な場合は `status_code=400` で失敗する。
- 入力が不足する場合は `status_code=400` で失敗する（create: `stream_name` 必須 / archive: `stream_name` または `stream_id` 必須）。
- dry-run の場合は Zulip API を呼ばず、入力チェック結果（および安全なサマリ）を返す。

### create（作成）

- 既に存在する場合は「成功（skipped）」として返し、二重作成を避ける。
- 作成は `/api/v1/users/me/subscriptions` を使用し、作成後に一覧取得で `stream_id` を解決する。

### archive（アーカイブ）

- 対象が見つからない場合は「成功（skipped）」として返す（安全側）。
- アーカイブは `/api/v1/streams/{stream_id}` の `is_archived=true` を使用する。

## エラーハンドリング（外部 API）

- Zulip API 呼び出し失敗は、`status_code=502` とし、可能な範囲で `upstream_status` と `upstream_body` を返す。
- ただし `upstream_body` は秘匿情報が含まれる可能性があるため、返却内容は「センシティブになり得るフィールドを除外/マスクする」ことを前提とする（実装はワークフローを正とする）。

## ログ/証跡（最小）

### 記録すべきキー（推奨）

- `realm`, `zulip_base_url`, `action`, `stream_name`, `stream_id`, `status_code`, `skipped`, `reason`, `upstream_status`
- `status_code=424`（資格情報不足）の場合は `missing`
- `upstream_body` は必要最小限かつセンシティブキー（token/api_key/authorization 等）をマスクしたうえで記録する（返却/ログとも）

### 証跡（例）

- `/webhook/zulip/streams/sync/test` の応答 JSON（必須 env の健全性確認）
- n8n 実行ログ（`realm`, `status_code`, `action`）
- Zulip 側のストリーム作成/アーカイブ履歴

## 設計シナリオ（DQ）

| scenario_id | ユースケース | 目的（要約） | 関連 OQ |
| --- | --- | --- | --- |
| DQ-ZSS-SC-01 | UC-ZS-01 | `action=create` が入力検証と作成に到達できる | `oq_zulip_stream_create.md` |
| DQ-ZSS-SC-02 | UC-ZS-02 | `action=archive` が入力検証とアーカイブに到達できる | `oq_zulip_stream_archive.md` |
| DQ-ZSS-SC-03 | UC-ZS-03 | dry-run で外部 API を呼ばずに完走する | `oq_zulip_stream_sync_dry_run.md` |
| DQ-ZSS-SC-04 | UC-ZS-04 | 冪等（既存/未存在）の安全側動作 | `oq_zulip_stream_create_idempotent.md` / `oq_zulip_stream_archive_idempotent.md` |
| DQ-ZSS-SC-05 | UC-ZS-05 | 入力不正を検出して拒否する | `oq_zulip_stream_sync_input_validation.md` |
| DQ-ZSS-SC-06 | UC-ZS-06 | `realm` による接続先/認証情報の切替 | `oq_zulip_stream_sync_realm_routing.md` |
| DQ-ZSS-SC-07 | UC-ZS-07 | 応答へ `realm`/`zulip_base_url` を必ず含める（追跡性） | `oq_zulip_stream_sync_response_traceability.md` |
| DQ-ZSS-SC-08 | UC-ZS-08 | dry-run 以外で資格情報不足を検出して早期失敗する（fail-fast） | `oq_zulip_stream_sync_missing_creds_failfast.md` |

## 入口条件（Entry）

- Webhook（main/test）と必須 env が `apps/itsm_core/zulip_stream_sync/README.md` に明記されている
- OQ が整備されている（`apps/itsm_core/zulip_stream_sync/docs/oq/oq.md`）

## 出口条件（Exit）

- IQ 合格: `apps/itsm_core/zulip_stream_sync/docs/iq/iq.md`
- OQ 合格: `apps/itsm_core/zulip_stream_sync/docs/oq/oq.md`（入力検証、create/archive）

## 変更管理（再検証トリガ）

- 入力スキーマ（action/必須キー）の変更
- dry-run/冪等の挙動変更
- realm 解決規則、または `N8N_ZULIP_*` マッピング仕様の変更
- テスト Webhook（`/test`）の `strict` 判定、または必須 env/エラーコードの扱い変更
- Zulip API 呼び出し範囲（作成/アーカイブ以外）の追加
- 同期スクリプト（`deploy_workflows.sh` / `run_oq.sh`）の挙動変更

## 更新記録（短く）

- 2026-02-01: `realm` 切替（UC/シナリオ）の明文化、入力仕様/資格情報解決/ログ推奨キーを追記（追跡性と誤接続リスク低減のため）
- 2026-02-01: 応答の追跡性を強化（`realm`/`zulip_base_url` の必須化）、OQ（realm routing / traceability）を追加（運用証跡の一貫性を高めるため）
