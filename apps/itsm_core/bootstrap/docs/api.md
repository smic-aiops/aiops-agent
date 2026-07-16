# ITSM Core API

ITSM Core API は n8n Webhook と PostgreSQL の `itsm.core_api_dispatch_v2` で提供します。API の正規仕様は [OpenAPI](openapi/itsm-core-api.yaml) です。

## エンドポイント

- `POST /webhook/itsm/core/api`
- 認証: `Authorization: Bearer <ITSM_CORE_API_TOKEN>` または `x-itsm-api-token`
- realm: request body の `realm`。省略時は n8n の realm 環境設定を利用
- 上限: `limit` は 1〜200

トークンは SSM/ECS 経由で `ITSM_CORE_API_TOKEN` に注入し、文書・workflow JSON・Git 管理対象の tfvars へ記載しません。

## 操作

| action | resource_type | 用途 |
|---|---|---|
| `get`, `list`, `search` | API 有効 resource | ID 取得、一覧、全文検索 |
| `create`, `update`, `delete` | `incident`, `service_request`, `problem`, `change_request`, `service`, `configuration_item` | CRUD |
| `add_comment`, `set_tag`, `grant_acl`, `add_attachment` | 対象 resource | 共通付加情報 |
| `sync_cmdb` | `cmdb` | Service/CI/relation の dry-run・冪等同期 |
| `list_attachment_deletions`, `ack_attachment_deletion` | `attachment_deletion` | ストレージ実体削除キューの取得・完了/失敗記録 |

書き込みは DB の realm/RLS、参照整合性 trigger、状態遷移規則、必須辞書により検証されます。

## 例

```json
{
  "realm": "aiops",
  "action": "create",
  "resource_type": "incident",
  "payload": {
    "title": "API疎通エラー",
    "description": "監視から起票",
    "priority": "high",
    "service_number": "SVC-UNASSIGNED"
  }
}
```

## 実装・検証

- workflow: `apps/itsm_core/sor_webhooks/workflows/itsm_sor_core_api.json`
- DB API: `apps/itsm_core/sor_ops/sql/itsm_sor_core.sql`
- OQ: `apps/itsm_core/sor_webhooks/scripts/run_oq.sh`
- 機能 OQ/PQ: `apps/itsm_core/sor_ops/scripts/run_feature_oq_pq.sh`

HR Talent Management など個別サブアプリ固有の Webhook は各 `apps/itsm_core/*/docs/usage/README.md` を参照してください。
