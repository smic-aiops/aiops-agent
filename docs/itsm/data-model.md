# ITSM コア（PostgreSQL）統合データモデル設計（テーブル/参照/ACL）

本書は「統合データモデル（テーブル/参照/ACL）」の **不足（△）** を埋めるための詳細設計です。  
狙いは **ITSM コア DB（PostgreSQL/RDS）を “正のデータ（System of Record）”** として定義し、**GitLab は変更/証跡（Change & Evidence）へ寄せる** ことです。

---

## 0. 前提と方針（正のデータ境界）

### 正のデータ（SoR: System of Record）

- **ITSM コア DB（RDS PostgreSQL）**: レコード（Incident/Change/Request/CI/Service/Approval）と参照関係、SLA 計測に必要な構造化データの正
- **Keycloak**: アイデンティティ（ユーザー/グループ/ロール）の正（DB は Keycloak の ID を参照するだけ）
- **SSM/Secrets Manager**: 秘密情報の正（DB には “秘密の値” は置かず、参照名だけ保持）

### 正ではない（派生/証跡/ワークスペース）

- **GitLab（Issue/MR/Repo）**: 変更要求・レビュー・承認・議事録・証跡リンク・テンプレ/Runbook の版管理（“正の構造化データ” は DB）
- **n8n**: オーケストレーション（イベント→起票→承認→実行→記録）。ワークフローの状態は DB に依存しない（再実行可能）
- **Qdrant**: 検索用インデックス（派生データ。正は GitLab/DB）

---

## 1. テナント/ID 設計（Realm ＝ 分離単位）

### 1-1. テナント（realm）

- 1 テナント = Keycloak の **realm**（または realm 相当の論理境界）
- すべての “正のデータ” テーブルに `realm_id` を持たせ、**行レベル分離**を前提にする

### 1-2. 主キー/採番

- 主キー: `uuid`（アプリ/API を跨いだ参照が安定する）
- 人が読む番号: `number`（例: `INC-000123`）をテナント内で一意にし、外部連携（GitLab）でも使う

推奨:
- `record_number_sequence` をレルム単位/種別単位で保持し、`INC/CHG/SRQ/PRB/CI/SVC` を接頭辞にする

---

## 2. 参照（外部 ID / 証跡リンク）の統一

GitLab/Exastro/AWS/Grafana など、外部システムの識別子を各テーブルに散らさないために **共通の参照テーブル**を定義します。

### 2-1. `external_ref`（外部参照）

- 用途: 任意レコード（Incident/Change/CI/Service…）に対し、外部 ID を複数ぶら下げる
- 例:
  - GitLab Issue: `gitlab:issue:<project_path>#<iid>`
  - GitLab MR: `gitlab:mr:<project_path>!<iid>`
  - AWS ARN: `aws:arn:<...>`
  - Exastro Job: `exastro:job:<id>`
  - Grafana Dashboard/Explore: `grafana:<uid>`

---

## 3. コアスキーマ（テーブル定義：最小核）

本設計は **「最小核（MVP）で統合データモデルを成立」** させ、段階的に拡張できる構成にしています。

### 3-1. テーブル一覧（最小核）

#### マスタ/共通

- `itsm.realm`
- `itsm.record_number_sequence`
- `itsm.external_ref`
- `itsm.resource_acl`（例外的な共有/秘匿レコードのアクセス付与）
- `itsm.attachment`（S3/EFS 等のオブジェクト参照メタデータ）
- `itsm.comment`（レコード共通コメント）
- `itsm.tag`（レコード共通タグ）

#### サービス/構成（CMDB）

- `itsm.service`
- `itsm.configuration_item`
- `itsm.ci_relation`（CI 間リレーション）

#### レコード（プロセス）

- `itsm.incident`
- `itsm.service_request`
- `itsm.problem`
- `itsm.change_request`
- `itsm.approval`（共通承認）
- `itsm.task`（実行タスク/チェックリスト）

#### 監査

- `itsm.audit_event`（改ざん耐性を意識した追記型イベントログ）

### 3-2. ER 図（概略）

```mermaid
erDiagram
  REALM ||--o{ SERVICE : has
  REALM ||--o{ CONFIGURATION_ITEM : has
  REALM ||--o{ INCIDENT : has
  REALM ||--o{ CHANGE_REQUEST : has
  REALM ||--o{ SERVICE_REQUEST : has
  REALM ||--o{ PROBLEM : has
  REALM ||--o{ APPROVAL : has
  REALM ||--o{ AUDIT_EVENT : has

  SERVICE ||--o{ CONFIGURATION_ITEM : owns
  SERVICE ||--o{ INCIDENT : impacts
  SERVICE ||--o{ CHANGE_REQUEST : targets
  SERVICE ||--o{ SERVICE_REQUEST : targets
  SERVICE ||--o{ PROBLEM : targets

  CONFIGURATION_ITEM ||--o{ CI_RELATION : from
  CONFIGURATION_ITEM ||--o{ CI_RELATION : to

  INCIDENT ||--o{ EXTERNAL_REF : refs
  CHANGE_REQUEST ||--o{ EXTERNAL_REF : refs
  SERVICE_REQUEST ||--o{ EXTERNAL_REF : refs
  PROBLEM ||--o{ EXTERNAL_REF : refs
  CONFIGURATION_ITEM ||--o{ EXTERNAL_REF : refs
  SERVICE ||--o{ EXTERNAL_REF : refs

  INCIDENT ||--o{ COMMENT : has
  CHANGE_REQUEST ||--o{ COMMENT : has
  SERVICE_REQUEST ||--o{ COMMENT : has
  PROBLEM ||--o{ COMMENT : has
  CONFIGURATION_ITEM ||--o{ COMMENT : has
  SERVICE ||--o{ COMMENT : has

  INCIDENT ||--o{ ATTACHMENT : has
  CHANGE_REQUEST ||--o{ ATTACHMENT : has
  SERVICE_REQUEST ||--o{ ATTACHMENT : has
  PROBLEM ||--o{ ATTACHMENT : has
```

### 3-3. 主要テーブル（列/制約/参照）

以降の型表記は PostgreSQL を前提（`uuid`, `timestamptz`, `jsonb`）。

#### `itsm.realm`

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `key` | `text` | `tenant-a` | Keycloak realm 名に一致（ユニーク） |
| `name` | `text` | `Tenant A` | 表示名 |
| `created_at` | `timestamptz` |  |  |

#### `itsm.record_number_sequence`（採番）

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `realm_id` | `uuid` |  | FK |
| `record_type` | `text` | `incident/change_request/...` | ユニーク（テナント内） |
| `prefix` | `text` | `INC` | 表示番号の接頭辞 |
| `next_value` | `bigint` | `124` | 次に払い出す連番 |
| `updated_at` | `timestamptz` |  |  |

補足:
- 実装では `SELECT ... FOR UPDATE` で `next_value` を安全にインクリメントし、`INC-000123` を生成します。

#### `itsm.external_ref`（外部参照）

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `realm_id` | `uuid` |  | FK |
| `resource_type` | `text` | `incident/change_request/ci/service` | |
| `resource_id` | `uuid` |  | 参照先レコード ID |
| `ref_type` | `text` | `gitlab_issue/gitlab_mr/aws_arn/...` | |
| `ref_key` | `text` | `gitlab:issue:group/pj#123` | 同一 `ref_type` 内でユニーク推奨 |
| `ref_url` | `text` |  | UI へ出す URL（任意） |
| `meta` | `jsonb` | `{ "project_path": "...", "iid": 123 }` | 任意の補助情報 |
| `created_at` | `timestamptz` |  | |

制約（推奨）:
- `(realm_id, resource_type, resource_id, ref_type, ref_key)` をユニーク
- `ref_key` は “再生成可能” ではなく “識別子” として固定する

#### `itsm.resource_acl`（例外 ACL）

サービス単位の責任分界（`service.owner_group_id`）に加え、**秘匿レコードの閲覧許可**や **一時共有** を扱うための例外 ACL テーブルです。

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `realm_id` | `uuid` |  | FK |
| `resource_type` | `text` | `incident/change_request/...` | |
| `resource_id` | `uuid` |  | |
| `subject_type` | `text` | `group/principal/role` | |
| `subject_id` | `text` | `kc-group-id` / `kc-sub` / `auditor` | |
| `permission` | `text` | `read/write/approve` | check 制約推奨 |
| `expires_at` | `timestamptz` |  | 一時共有用（任意） |
| `granted_by_principal_id` | `text` | `kc-sub` | |
| `created_at` | `timestamptz` |  | |

#### `itsm.comment`（共通コメント）

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `realm_id` | `uuid` |  | FK |
| `resource_type` | `text` | `incident/change_request/...` | |
| `resource_id` | `uuid` |  | |
| `body` | `text` |  |  |
| `author_principal_id` | `text` | `kc-sub` | |
| `created_at` | `timestamptz` |  | |

#### `itsm.attachment`（添付メタ）

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `realm_id` | `uuid` |  | FK |
| `resource_type` | `text` |  | |
| `resource_id` | `uuid` |  | |
| `storage_type` | `text` | `s3/efs` | |
| `storage_key` | `text` | `s3://bucket/key` | 実体の参照（アクセス制御は別） |
| `content_type` | `text` | `application/pdf` | |
| `size_bytes` | `bigint` |  | |
| `sha256` | `text` |  | 改ざん検知用（任意） |
| `created_by_principal_id` | `text` | `kc-sub` | |
| `created_at` | `timestamptz` |  | |

#### `itsm.tag`（共通タグ）

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `realm_id` | `uuid` |  | FK |
| `resource_type` | `text` |  | |
| `resource_id` | `uuid` |  | |
| `key` | `text` | `environment` | |
| `value` | `text` | `prod` | |
| `created_at` | `timestamptz` |  | |

#### `itsm.service`

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `realm_id` | `uuid` |  | FK → `realm.id` |
| `number` | `text` | `SVC-000042` | テナント内ユニーク |
| `name` | `text` | `billing-api` | |
| `description` | `text` |  | |
| `owner_group_id` | `text` | `kc-group-id` | Keycloak group ID（※DB は正を持たない） |
| `criticality` | `text` | `low/medium/high` | check 制約推奨 |
| `status` | `text` | `active/retired` | |
| `created_at` | `timestamptz` |  | |
| `updated_at` | `timestamptz` |  | |

参照:
- Incident/Change/CI は `service_id` を持ち、影響範囲・責任分界・ACL の基点にする

#### `itsm.configuration_item`（CI）

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `realm_id` | `uuid` |  | FK |
| `number` | `text` | `CI-000314` | テナント内ユニーク |
| `service_id` | `uuid` |  | FK → `service.id`（所属サービス） |
| `ci_type` | `text` | `app/db/network/host` | check 制約推奨 |
| `name` | `text` | `rds-itsm-core` | |
| `attributes` | `jsonb` | `{ "arn": "...", "region": "ap-northeast-1" }` | 可変属性（ただし “正” は DB） |
| `lifecycle_status` | `text` | `in_service/out_of_service` | |
| `owner_group_id` | `text` | `kc-group-id` | |
| `created_at` | `timestamptz` |  | |
| `updated_at` | `timestamptz` |  | |

#### `itsm.ci_relation`（CI 関係）

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `realm_id` | `uuid` |  | FK |
| `from_ci_id` | `uuid` |  | FK → `configuration_item.id` |
| `to_ci_id` | `uuid` |  | FK → `configuration_item.id` |
| `relation_type` | `text` | `depends_on/runs_on/connected_to` | |
| `created_at` | `timestamptz` |  | |

制約:
- `(realm_id, from_ci_id, to_ci_id, relation_type)` のユニークを推奨（重複エッジ防止）

#### `itsm.incident`

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `realm_id` | `uuid` |  | FK |
| `number` | `text` | `INC-000123` | テナント内ユニーク |
| `title` | `text` | `API 5xx spikes` | |
| `description` | `text` |  | 本文（長文は GitLab 側へ寄せても良い） |
| `status` | `text` | `new/ack/in_progress/resolved/closed` | |
| `priority` | `text` | `p1/p2/p3/p4` | |
| `service_id` | `uuid` |  | FK → `service.id` |
| `primary_ci_id` | `uuid` |  | FK → `configuration_item.id`（任意） |
| `reporter_principal_id` | `text` | `kc-sub` | Keycloak `sub` |
| `assignee_group_id` | `text` | `kc-group-id` | |
| `assignee_principal_id` | `text` | `kc-sub` | |
| `started_at` | `timestamptz` |  | SLA 計測起点 |
| `resolved_at` | `timestamptz` |  | |
| `closed_at` | `timestamptz` |  | |
| `visibility` | `text` | `internal/confidential` | **ACL の補助**（後述） |
| `created_at` | `timestamptz` |  | |
| `updated_at` | `timestamptz` |  | |

#### `itsm.change_request`（RFC/Change）

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `realm_id` | `uuid` |  | FK |
| `number` | `text` | `CHG-000077` | |
| `title` | `text` | `Upgrade n8n` | |
| `risk_level` | `text` | `low/medium/high` | |
| `change_type` | `text` | `standard/normal/emergency` | |
| `status` | `text` | `draft/assess/approve/scheduled/implement/review/closed` | |
| `service_id` | `uuid` |  | FK |
| `requested_by_principal_id` | `text` | `kc-sub` | |
| `planned_start_at` | `timestamptz` |  | |
| `planned_end_at` | `timestamptz` |  | |
| `implementation_plan` | `text` |  | 重要なら GitLab MR/Runbook を正にし、ここは要約にする |
| `backout_plan` | `text` |  | |
| `created_at` | `timestamptz` |  | |
| `updated_at` | `timestamptz` |  | |

#### `itsm.service_request`（サービス要求）

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `realm_id` | `uuid` |  | FK |
| `number` | `text` | `SRQ-000055` | |
| `title` | `text` | `Add user to group` | |
| `status` | `text` | `new/approved/in_progress/fulfilled/closed` | |
| `service_id` | `uuid` |  | FK |
| `requester_principal_id` | `text` | `kc-sub` | |
| `assignee_group_id` | `text` | `kc-group-id` | |
| `catalog_item_key` | `text` | `access.add_group_member` | カタログの識別子（GitLab/DB どちらが正でもよいが固定する） |
| `inputs` | `jsonb` | `{ "target_user": "..." }` | フォーム入力（PII は最小化） |
| `visibility` | `text` | `internal/confidential` | |
| `created_at` | `timestamptz` |  | |
| `updated_at` | `timestamptz` |  | |

#### `itsm.problem`（問題）

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `realm_id` | `uuid` |  | FK |
| `number` | `text` | `PRB-000012` | |
| `title` | `text` | `Recurring DB timeouts` | |
| `status` | `text` | `new/analysis/known_error/resolved/closed` | |
| `priority` | `text` | `p1/p2/p3/p4` | |
| `service_id` | `uuid` |  | FK |
| `owner_group_id` | `text` | `kc-group-id` | |
| `root_cause_summary` | `text` |  | 詳細は GitLab に寄せてもよい |
| `created_at` | `timestamptz` |  | |
| `updated_at` | `timestamptz` |  | |

#### `itsm.task`（チェックリスト/実行タスク）

Change/Incident/Request にぶら下げる “作業” を表現します（Exastro/CI/CD 連携の粒度を揃えるための器）。

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `realm_id` | `uuid` |  | FK |
| `resource_type` | `text` | `incident/change_request/service_request` | 親レコード種別 |
| `resource_id` | `uuid` |  | 親レコード ID |
| `title` | `text` | `Run migration` | |
| `status` | `text` | `todo/doing/done/blocked` | |
| `assignee_group_id` | `text` | `kc-group-id` | |
| `assignee_principal_id` | `text` | `kc-sub` | |
| `due_at` | `timestamptz` |  | |
| `external_execution` | `jsonb` | `{ "exastro_job": "...", "gitlab_pipeline": "..." }` | 実行系への参照 |
| `created_at` | `timestamptz` |  | |
| `updated_at` | `timestamptz` |  | |

#### `itsm.approval`（共通承認）

Incident/Change/Export 等の “承認” を共通テーブルで扱い、**承認 ID** を証跡の核にします。

- 運用（チャット）では、AIOpsAgent の approve/deny（承認確定）を **Zulip の `/decision`** として同一トピックへ投稿し、GitLab Issue にも証跡化する（参照: `docs/usage-guide.md`）。必要に応じて `/decisions` で時系列サマリを参照する。

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK（承認 ID） |
| `realm_id` | `uuid` |  | FK |
| `resource_type` | `text` | `change_request/export/…` | 承認対象の種別 |
| `resource_id` | `uuid` |  | 対象レコード ID |
| `status` | `text` | `pending/approved/rejected/canceled` | |
| `requested_by_principal_id` | `text` | `kc-sub` | |
| `approved_by_principal_id` | `text` | `kc-sub` | |
| `approved_at` | `timestamptz` |  | |
| `decision_reason` | `text` |  | |
| `evidence` | `jsonb` | `{ "gitlab_issue": "...", "hmac": "..." }` | 改ざん検知や外部証跡の最小メタ |
| `created_at` | `timestamptz` |  | |
| `updated_at` | `timestamptz` |  | |

#### `itsm.audit_event`（監査イベント：追記型）

- 目的: “誰が・いつ・何を” を DB 側でも追えるようにする（GitLab だけに寄せない）
- 原則: **更新ではなく追記**（イベントログは append-only）

| 列 | 型 | 例 | 備考 |
|---|---|---|---|
| `id` | `uuid` |  | PK |
| `realm_id` | `uuid` |  | FK |
| `occurred_at` | `timestamptz` |  | |
| `actor_principal_id` | `text` | `kc-sub` | |
| `actor_type` | `text` | `human/automation` | |
| `action` | `text` | `incident.create/change.approve/...` | |
| `resource_type` | `text` | `incident/change_request/...` | |
| `resource_id` | `uuid` |  | |
| `correlation_id` | `text` | `evt-...` | CloudWatch/EventBridge/n8n で引き回す |
| `before` | `jsonb` |  | 変更前（必要に応じて） |
| `after` | `jsonb` |  | 変更後（必要に応じて） |
| `integrity` | `jsonb` | `{ "prev_hash": "...", "hash": "..." }` | ハッシュチェーン等（任意） |

---

## 4. ACL（認可）設計

本基盤は **Keycloak（OIDC）を認証の正** とし、ITSM コア DB では以下の 2 層で認可を成立させます。

1. **アプリ/API 層 RBAC**: JWT の `roles/groups/realm` で API をガード
2. **DB 層 RLS（Row Level Security）**: `realm_id` とサービス/担当グループを基点に、誤実装・直 DB アクセスでも漏洩しにくくする

### 4-1. 標準ロール（例）

| ロール | 想定 | 権限の目安 |
|---|---|---|
| `platform_admin` | 基盤運用 | 全テナント管理（ただし監査ログは読み取り中心） |
| `itsm_admin` | ITSM 管理者 | テナント内フル（設定/マスタ含む） |
| `service_owner` | サービス責任者 | 自サービスの Incident/Change/CI の読み書き/承認 |
| `resolver` | 対応担当 | 割当レコードの更新 |
| `requester` | 依頼者 | 自分が起票したレコード参照（必要なら更新） |
| `auditor` | 監査 | 参照中心（エクスポートは別承認必須） |
| `automation` | n8n/連携 | 代行操作（スコープ限定） |

### 4-2. 行レベルの基本ルール（推奨）

- **必須**: `realm_id` は API が `SET LOCAL app.realm_key`（または `app.realm_id`）で指定したテナントと一致する行のみ参照可能（クロステナント遮断）
- レコードの `service_id` から “担当グループ” を解決し、`service_owner/resolver` は該当範囲の更新可
- `visibility = confidential` の場合、`itsm_admin/auditor` か `itsm.resource_acl` で “付与された主体（group/principal/role）” のみ参照可

### 4-3. DB 実装（RLS）方針（例）

API サービスが DB 接続後に以下を `SET LOCAL` する前提:

- `app.realm_key`（例: `tenant-a`）
- `app.principal_id`（Keycloak `sub`）
- `app.roles`（CSV あるいは JSON）
- `app.groups`（Keycloak group IDs）

RLS は “誤実装時の保険” であり、**最終責任は API 層**に置きます（DB だけで完全なフィールド ACL をやり切らない）。

---

## 5. GitLab への寄せ方（変更/証跡）

### 5-1. 役割分担（DB vs GitLab）

- DB: 状態/関係/期限/担当/承認 ID といった **構造化の正**
- GitLab: 変更要求の議論、レビュー、承認の可視化、証跡リンク、Runbook/手順書の版管理

### 5-2. リンク規約（必須）

すべての GitLab Issue/MR から “正のレコード” に戻れるように、以下をテンプレへ必須項目にします。

- `ITSM Record`:
  - `number`（例: `CHG-000077`）
  - `id`（UUID）
  - `realm`（`tenant-a`）
- `Approval ID`（承認が絡む場合は必須）
- `correlation_id`（自動化/イベント起票は必須）

DB 側は `external_ref` に GitLab の参照を保存し、双方向リンクを固定します。

---

## 6. 秘密情報（SSM/Secrets Manager）取り扱い

- DB に秘密情報（パスワード/トークン/鍵）を保存しない
- DB に置けるのは以下のみ:
  - SSM パラメータ名（例: `/env/itsm/tenant-a/n8n/api_key`）
  - Secrets Manager の ARN
  - 秘密の種類/用途/ローテーション方針（メタデータ）

---

## 7. 段階導入（現状 GitLab 中心からの移行を壊さない）

本リポジトリは現状、GitLab（Issue/Repo）を中心に運用しやすい設計になっています。  
そのため導入は次の順で “二重管理” を最小化します。

1. **DB にレコードの正（number/id/status/service/approval）だけを作る**
2. GitLab は “議論/テンプレ/証跡” に寄せ、Issue テンプレに `number/id/approval_id` を必須化
3. n8n で DB↔GitLab の相互参照を `external_ref` に固定（同期は “最小” から）

---

## 8. 次の成果物（本書の後に作るもの）

- `docs/itsm/api.md`（OpenAPI: CRUD + 検索 + 承認 + 監査イベント）
- `apps/itsm_core/`（API サービス実装）※必要になったタイミングで追加
- GitLab テンプレの更新（Issue/MR の必須項目化）
