# Runbook: サービス停止通知時の自動起動（{{SERVICE_NAME}}）
> 本ランブックは主に `{{SERVICE_NAME}}` が Sulu の場合（`{{SERVICE_ID}}=sulu`）を想定しています。

## 目的
サービス停止の通知を受けた際に、契約条件と運用状況を確認した上で、迅速にサービスを復旧する。

## 適用範囲
- サービス: {{SERVICE_NAME}} ({{SERVICE_ID}})
- 環境: {{ENVIRONMENT}}
- CMDB: `../{{ORG_ID}}/{{SERVICE_ID}}.md`
- SLA: `{{GITLAB_PROJECT_URL}}/-/blob/main/docs/sla_master.md`
- OLA: `{{GITLAB_PROJECT_URL}}/-/blob/main/docs/ola_master.md`
- UC: `{{GITLAB_PROJECT_URL}}/-/blob/main/docs/uc_master.md`

## 役割と責任 
- 運用当番: 本ランブックの実行、記録、一次復旧
- サービスオーナー: 例外判断、影響評価、恒久対策の承認
- 変更/問題管理: 再発防止策の登録と追跡

## 基本方針
- サービス停止の通知があった場合、契約期間・運用時間・ライフサイクルステータスをみて、運用中であるべき場合は、サービスを自動で起動する。
- 変更凍結・保守ウィンドウ・計画停止の場合は、自動起動を行わず、承認フローに従う。

## 事前確認
1. インシデント/障害チケットの有無を確認する。
2. 変更カレンダー/保守予定と突合する。
3. 監視アラートの誤検知を確認する。

## 判断基準
| 判定項目 | 参照先 | 判断 | アクション |
| --- | --- | --- | --- |
| 契約期間 | CMDB の「契約期間」 | 期間内 | 次へ |
| 契約期間 | CMDB の「契約期間」 | 期間外 | 自動起動せず、サービスオーナーへ確認 |
| 運用時間 | CMDB の「運用時間」 | 運用時間内 | 次へ |
| 運用時間 | CMDB の「運用時間」 | 運用時間外 | 自動起動せず、オンコールへ判断依頼 |
| ライフサイクル | CMDB の「ステータス」 | 運用中/移行中 | 自動起動を実行 |
| ライフサイクル | CMDB の「ステータス」 | 停止/廃止/準備中 | 自動起動せず、チケットに記録 |

## 手順
### 1. 通知受付と初動
- 監視通知または通報の内容を記録し、インシデントを起票する。
- 影響範囲 (ユーザー数、SLA) を一次評価する。

## Sulu Service Down → 自動復旧（再起動）のトリガー手順
> 運用窓口: Zulip `#itsm-incident` / topic `sulu`

### 定期トリガー（監視→自動復旧）
- 監視（CloudWatch/Synthetics 等）がサービス停止を検知すると、AIOps Agent の ingest（`/webhook/ingest/cloudwatch`）へイベントが投入される。（例: `prod-smahub-sulu-updown`）
- AIOps Agent が CMDB/Runbook/Service Window を参照して「自動復旧可」と判断した場合、Workflow Manager の `Sulu Service Control`（`wf.sulu_service_control`）へ `action=restart` を実行要求する。
- 実行・結果・エスカレーションは Zulip `#itsm-incident` / topic `sulu` に集約する（`@stream` を使う場合、購読者へ通知される）。

### 手動トリガー（運用が直接起動する）
> 自動復旧が抑制される/遅延する場合のフォールバックです（計画停止・保守ウィンドウ・要承認の疑いがある場合は、起動前に承認/確認を優先）。

#### 手動トリガー（推奨）: Workflow Manager の Webhook を直接叩く
```bash
curl -sS -H 'Content-Type: application/json' \
  -d '{"action":"restart","realm":"<realm>"}' \
  "<n8n_base_url>/webhook/sulu/service-control" | jq .
```

#### 手動トリガー（検証用）: CloudWatch 監視イベント相当を投入して全経路を確認
```bash
# 注意: <cloudwatch_webhook_token> は秘匿情報。平文でチケット/チャットへ貼らない。
curl -sS -H 'Content-Type: application/json' \
  -H "X-AIOPS-WEBHOOK-TOKEN: <cloudwatch_webhook_token>" \
  -d '{
    "detail-type":"CloudWatch Alarm State Change",
    "source":"aws.cloudwatch",
    "account":"123456789012",
    "region":"ap-northeast-1",
    "time":"2026-02-02T00:00:00Z",
    "detail":{
      "state":{"value":"ALARM"},
      "alarmName":"SuluServiceDown"
    }
  }' \
  "<n8n_base_url>/webhook/ingest/cloudwatch" | jq .
```

### 成功確認（必須）
- `{{GITLAB_PROJECT_URL}}/-/pipelines` / n8n 実行履歴で、`aiops-orchestrator` と `Sulu Service Control` の実行が確認できる。
- Zulip `#itsm-incident` / topic `sulu` に、実行と復旧結果（成功/失敗/エスカレーション）が投稿される。
- ヘルスチェック（合成監視/HTTP/アプリ監視）が復旧し、5xx/レイテンシ/CPU 等が平常に戻る。

### 2. CMDB で契約条件を確認
- `../{{ORG_ID}}/{{SERVICE_ID}}.md` の以下を確認する。
  - 契約期間
  - 運用時間
  - ライフサイクルステータス
- 条件に合致しない場合は、起動せずにエスカレーションする。

### 3. 自動起動を実行
- 自動化フローがある場合は優先して実行する（n8n: `Sulu Service Control`）。
- 例 (n8n/起動):
  - `curl -X POST "<n8n_base_url>/webhook/sulu/service-control" -H "Content-Type: application/json" -d '{"action":"up","realm":"prod"}'`
- 例 (n8n/停止):
  - `curl -X POST "<n8n_base_url>/webhook/sulu/service-control" -H "Content-Type: application/json" -d '{"action":"down","realm":"prod"}'`
- 例 (n8n/再起動):
  - `curl -X POST "<n8n_base_url>/webhook/sulu/service-control" -H "Content-Type: application/json" -d '{"action":"restart","realm":"prod"}'`
- 実行結果と開始時刻をチケットに記録する。

### 4. 健全性確認
- ヘルスチェックの復旧を確認する。
- 監視指標 (5xx, レイテンシ, CPU/メモリ) が通常に戻ることを確認する。

### 5. 通知と記録
- 復旧完了を関係者へ通知する。
- インシデントに以下を記録する。
  - 発生時刻/復旧時刻
  - 実施手順
  - 影響範囲
  - 一時対応/恒久対策の要否

#### Zulip へ記録する際の注意（改行の扱い）
- `curl --data-urlencode "content=..."` で Zulip に投稿する場合、`"\n"` を文字列として渡すと **改行ではなく `\n` がそのまま表示**されることがある。
- 改行を含む本文は `printf` で組み立て、変数の値抽出は `sed` 等を使って **行番号を混ぜない**（`rg -n` は行番号が混ざるため避ける）。

例:
```bash
ok="$(sed -n 's/^ok=//p' context.txt | head -n 1)"
url="$(sed -n 's/^sulu_url=//p' context.txt | head -n 1)"
head_code="$(sed -n 's/^http_code_head=//p' context.txt | head -n 1)"
get_code="$(sed -n 's/^http_code_get=//p' context.txt | head -n 1)"

msg="$(printf '%s\n- url: %s/\n- head: %s\n- get: %s\n' \
  \"[RUNBOOK] 健全性確認（Sulu）: ok=${ok}\" \
  \"${url}\" \"${head_code}\" \"${get_code}\")"

curl -sS -u \"<admin_email>:<admin_api_key>\" -X POST \"https://<realm>.zulip.../api/v1/messages\" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'type=stream' \
  --data-urlencode 'to=itsm-incident' \
  --data-urlencode 'topic=sulu' \
  --data-urlencode \"content=${msg}\"
```

## 失敗時の対応
- 自動起動が失敗した場合は、オンコールおよびサービスオーナーへ即時連絡する。
- 30 分以内に復旧しない場合は、エスカレーションフローに従う。

## 事後対応
- 問題管理: 恒久対策の要否を判断し、問題管理チケットを起票する。
- 変更管理: 必要に応じて変更申請を作成する。
- ナレッジ管理: 学びや更新点をランブックへ反映する。

## 変更履歴
| 日付 | 変更内容 | 変更者 |
| --- | --- | --- |
| 2025-01-01 | 初版 | ops-team |
| 2026-02-02 | Sulu down 自動復旧の定期/手動トリガー手順を追記 | ops-team |
