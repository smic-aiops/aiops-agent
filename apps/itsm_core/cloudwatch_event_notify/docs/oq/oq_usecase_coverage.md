# OQ: ユースケース別カバレッジ（cloudwatch_event_notify）

## 目的

`apps/itsm_core/cloudwatch_event_notify/docs/app_requirements.md` に列挙したユースケース（SSoT: `scripts/itsm/gitlab/templates/*-management/docs/usecases/`）について、**OQ としての実施シナリオが存在する**ことを保証する。

## 対象

- アプリ: `apps/itsm_core/cloudwatch_event_notify`
- OQ 正: `oq_cloudwatch_event_notify.md`（外部通知の成立性）

## ユースケース別 OQ シナリオ

### 12_incident_management（12. インシデント管理）

- SSoT: `scripts/itsm/gitlab/templates/service-management/docs/usecases/12_incident_management.md.tpl`
- シナリオ（OQ-CWN-UC12-01）:
  - `oq_cloudwatch_event_notify.md` の OQ ケース（OQ-CWN-001〜007）を実施する
- 受け入れ基準:
  - 受信→整形→（任意）Zulip/GitLab/Grafana 連携が成立し、追跡（リンク/結果）が残る
- 証跡:
  - `/webhook/cloudwatch/notify` 応答 JSON、外部連携先の生成物

### 23_proactive_detection（23. 予兆検知（プロアクティブ検知））

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/23_proactive_detection.md.tpl`
- シナリオ（OQ-CWN-UC23-01）:
  - `oq_cloudwatch_event_notify.md` の OQ-CWN-006/007（外部連携 + 部分失敗の可視化）を実施する
- 受け入れ基準:
  - 通知/起票/Annotation 等が自動化され、失敗時も結果（どこが失敗したか）が残る
- 証跡:
  - `results[]` / `status_code=207` の記録、外部連携先のログ

### 22_automation（22. 自動化）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/22_automation.md.tpl`
- シナリオ（OQ-CWN-UC22-01）:
  - `oq_cloudwatch_event_notify.md` の手順に従い、ワークフロー同期（dry-run→apply）とテスト Webhook を実施する
- 受け入れ基準:
  - 再現可能な手順で同期/検証できる
- 証跡:
  - 同期ログ、テスト Webhook 応答

### 24_security（24. セキュリティ）

- SSoT: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/24_security.md.tpl`
- シナリオ（OQ-CWN-UC24-01）:
  - `oq_cloudwatch_event_notify.md` の OQ-CWN-004（Webhook token/secret 不一致）を実施する
- 受け入れ基準:
  - 受信認可が成立し、不正送信を拒否できる
- 証跡:
  - `401` 応答（または同等の拒否証跡）

