# ITSM SoR: アーカイブ/保持期間/削除（MVP 方針）

このドキュメントは `apps/itsm_core/sql/itsm_sor_core.sql`（`itsm.*`）の **保持/削除/匿名化** 方針と、MVP としての最小実装を定義します。

## 前提（MVPの割り切り）

- SoR の書き込み主体は現状 **n8n から DB 直叩き**であり、UI/API 層の業務ルールは未整備です。
- 添付の実体（S3/EFS 等）の削除・WORM（Object Lock）・ライフサイクルは **ストレージ側の設定**が正です（DB は参照メタのみ）。
- 監査ログ（`itsm.audit_event`）は原則 **追記型**（append-only）で、削除は例外扱いです（デフォルトでは物理削除を無効化）。

## 実務で決めるべき論点（最小セット）

1. 何を何年保管するか（カテゴリごと）
2. 削除の種類（運用上の削除 / 保持期限到来の削除 / PII削除要求）
3. 監査ログの扱い（原則消さない、消すなら手順と権限）
4. 添付（実体）とメタデータの整合（S3ライフサイクル/ロックと同期）

## 日本法制/ガイドラインを踏まえたデフォルト（MVP）

本リポジトリのデフォルト保持年限は、以下を “根拠にしやすい最小限” として採用します（※業種・契約・社内規程で上書き前提）。

- 税務の帳簿書類は **原則 7 年**、条件により **10 年**になるケースがあるため、ITSM の意思決定/監査用途は 7〜10 年を基準に設定する
- 個人情報は **必要な範囲でのみ保持**し、不要になった場合は遅滞なく消去/匿名化する（年限の一律規定ではなく “目的・必要性” が軸）

参考（公式）:
- 国税庁: 帳簿書類等の保存期間（原則 7 年、一定の場合 10 年）
  - https://www.nta.go.jp/taxes/shiraberu/taxanswer/hojin/5930.htm
- 個人情報保護委員会: 個人データの保存期間（目的に照らした管理、不要時の消去等）
  - https://www.ppc.go.jp/faq/korosuginaikojinjouhou/gaiyou/50/
  - https://www.ppc.go.jp/privacy/qa/answer/

### デフォルト保持（DB側の変数）

デフォルト値は `itsm.retention_policy`（レルム別）へ **遅延投入**されます（`itsm.ensure_retention_policy()`）。

| policy_key | デフォルト保持 | 物理削除（既定） | 備考 |
|---|---:|---|---|
| `incident` | 7年 | 有効 | `closed_at/resolved_at` 基準 |
| `change_request` | 7年 | 有効 | `implemented_at` 基準 |
| `approval` | 10年 | 有効 | 最終状態 + `approved_at/updated_at` 基準 |
| `audit_event` | 10年 | **無効** | 原則消さない（hard delete は例外） |
| `attachment` | 7年 | 有効 | メタデータのみ（実体はストレージ側） |

運用上の削除（取り下げ/誤登録）:
- 上記の各テーブルは `deleted_at/deleted_by_principal_id/delete_reason` を持ち、`soft_delete_grace_days`（既定: 30日）経過で purge 対象になります。

## 削除の種類と実装手段（MVP）

### 1) 運用上の削除（ソフトデリート → 猶予後に purge）

- 対象テーブル: `itsm.incident`, `itsm.change_request`, `itsm.approval`, `itsm.attachment`
- 実装: `deleted_at` をセット（n8n 側で UPDATE）
- purge 実行: `itsm.apply_retention(realm_id, dry_run)`（dry_run=false で物理削除）

### 2) 保持期限到来の削除（物理削除）

- incident: `closed_at/resolved_at` が保持期限を超過したレコード
- change_request: `implemented_at` が保持期限を超過したレコード
- approval: final status（approved/rejected/canceled/expired）かつ期限超過
- 監査（audit_event）は既定では削除しない（hard_delete_enabled=false）

削除の監査:
- purge 実行時、削除件数を `itsm.audit_event` に **要約イベント**として追記します（`action=retention.purge`）。

### 3) PII 削除要求（削除より匿名化/マスキング）

整合性（参照・説明責任）を保つため、レコード自体の削除よりも **principal_id の疑似化（pseudonymize）** を優先します。

- 実装: `itsm.anonymize_principal(realm_id, principal_id, dry_run)`
- 置換後: `redacted:<sha256_prefix>`（レルム+principal_id で安定生成）
- 監査: 実行時に `itsm.audit_event` へ `action=pii.redaction` を追記

## 運用手順（スクリプト）

### 保持/削除ジョブ（dry-run 推奨 → execute）

1. dry-run（件数確認）:
   - `apps/itsm_core/scripts/apply_itsm_sor_retention.sh --realm-key default --dry-run`
2. 実行:
   - `apps/itsm_core/scripts/apply_itsm_sor_retention.sh --realm-key default --execute`
3. （任意）plan-only（SQL/ターゲットの確認のみ）:
   - `apps/itsm_core/scripts/apply_itsm_sor_retention.sh --plan-only --realm-key default --dry-run`

### PII 匿名化（dry-run 推奨 → execute）

1. dry-run（影響件数確認）:
   - `apps/itsm_core/scripts/anonymize_itsm_principal.sh --realm-key default --principal-id <kc-sub> --dry-run`
2. 実行:
   - `apps/itsm_core/scripts/anonymize_itsm_principal.sh --realm-key default --principal-id <kc-sub> --execute`
3. （任意）plan-only（SQL/ターゲットの確認のみ）:
   - `apps/itsm_core/scripts/anonymize_itsm_principal.sh --plan-only --realm-key default --principal-id <kc-sub> --dry-run`

## 将来拡張（必要になったら）

- `itsm.audit_event` の `occurred_at` 月次パーティション（大量データ前提）と、期限到来時の `DROP PARTITION`
- 添付ストレージ（S3）側のライフサイクル/オブジェクトロック（WORM）と purge の二相処理（DB→削除キュー→ストレージ削除→メタ削除）
- UI/API 層における “消せない/消す前に承認が必要” などの業務ルール実装
