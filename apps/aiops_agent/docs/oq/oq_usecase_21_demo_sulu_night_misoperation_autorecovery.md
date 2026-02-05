# OQ-USECASE-21: デモ（夜間の誤停止→自動復旧 / Sulu）

## 目的
夜間メンテナンス中の人為ミス（Sulu を誤って停止）により Service Down が発生した際、AIOps Agent が周辺情報（操作ログ/Runbook/CMDB/Service Window）を根拠として自動復旧（再起動）を判断し、`apps/workflow_manager` のワークフロー実行まで到達できることを確認します。

## 前提
- 監視通知（CloudWatch 等）を `source=cloudwatch` として受信できる（OQ-USECASE-02 相当）。
- 周辺情報収集（enrichment）が有効で、最低限 `runbook` と `cmdb` を参照できる（OQ-USECASE-04 相当）。
- サービスリクエストカタログが参照可能で、Workflow Manager の `Sulu Service Control` が取得できること。
  - `apps/workflow_manager/workflows/service_request/aiops_sulu_service_control.json`
  - `meta.workflowId = wf.sulu_service_control`
- 自動復旧の実行は Workflow Manager 側のワークフローを実行する（本 OQ では、AIOps Agent が **再起動を選定し実行要求を出せる**ことを主に確認する）。

## 入力
- 監視通知（例: CloudWatch Alarm）: 「Service Down（Sulu）」を示す payload
  - `detail.state.value = ALARM`
  - `detail.alarmName` などに Sulu のサービスダウンを識別できる値（例: `SuluServiceDown` / `prod-smahub-sulu-updown`）。ただし最終的な workflow 選定は文字列フィルタの強制分岐ではなく、`jobs.Preview`（LLM）が `monitoring_workflow_hints` 等の facts を踏まえて判断する。
- 直近の操作ログ（期待される enrichment 結果）
  - 「直近の操作: 手動停止（誤操作の可能性）」を示す要約/参照が得られる
- Runbook（期待される enrichment 結果）
  - 「再起動可」「自動復旧 OK」等の記述が得られる
- CMDB（期待される enrichment 結果）
  - 対象 CI が `service=sulu` であること
  - Service Window が `24x7`（稼働必須）であること

## 期待出力
- `aiops_context.source='cloudwatch'` の context が作成される。
- `enrichment_summary` / `enrichment_refs` に、操作ログ/Runbook/CMDB（24x7）の根拠が残る。
- `jobs/preview` の結果（`job_plan`）が次を満たす。
  - 対象サービスが `sulu` として識別されている
  - 自動復旧の候補として `workflow_id=wf.sulu_service_control`（または同等のカタログ ID）を選定している
  - 実行パラメータに `action=restart`（または `command=restart`）が含まれる
  - 選定根拠として、監視通知（アラーム名/source）と `monitoring_workflow_hints`（ポリシー）を整合させている（単純な `includes('sulu')` などの固定ルールで上書きしていない）
- 実行が行われる場合（環境/ポリシーで許可されている場合）は、ユーザー向け通知として次の趣旨が出力される。
  - 「サービスダウンを検知しました」
  - 「自動再起動を実行しました」
  - 「現在は正常に稼働しています」

## 手順
1. 監視通知（Sulu Service Down）を送信し、受信が 2xx になることを確認する。
2. `aiops_context` を `trace_id` で抽出し、`source=cloudwatch` と保存内容を確認する。
3. `aiops_context.normalized_event.enrichment_*` を確認し、操作ログ/Runbook/CMDB（24x7）が根拠として残っていることを確認する。
4. `aiops_orchestrator` の `jobs/preview` 実行結果で、`wf.sulu_service_control`（Sulu Service Control）が選定されていることを確認する。
5. 実行が有効な環境では、Workflow Manager の `Sulu Service Control` の実行履歴（および Service Control API の応答）を確認する。

## テスト観点

### 正常系
- 監視通知（ALARM）→ enrichment で Runbook/CMDB が取得され、`wf.sulu_service_control`（restart）が候補に出る。
- 実行が許可されている場合、再起動が実行され、復旧メッセージが出る。

### 異常系
- CMDB が `run_window != 24x7`（例: メンテ時間）を返す場合、**自動復旧を実行しない**（`jobs/preview` が実行抑制/確認要求になる）。
- Runbook に「自動復旧不可/要承認」がある場合、**自動復旧を実行しない**（承認フローへ）。
- `Sulu Service Control` がカタログに存在しない/取得できない場合、代替案（手順案内/人手対応/エスカレーション）へフォールバックする。

## 失敗時の調査ポイント（ログ・設定）
- 受信が失敗する: `aiops_adapter_ingest` の `Validate CloudWatch` と `source` 判定、必須フィールド（`detail-type`/`detail.alarmName` 等）を確認。
- enrichment が空/不足: `Build Enrichment Plan` / `Collect Enrichment` の実行ログ、`policy_context` の `enrichment_plan` defaults/fallbacks を確認。
- `wf.sulu_service_control` が出ない: Workflow Manager 側の `catalog/workflows/list`/`catalog/workflows/get` の応答、`N8N_WORKFLOWS_TOKEN` 設定、`meta.aiops_catalog.available_from_monitoring` を確認。
- 実行はしたが復旧しない: Workflow Manager の `Sulu Service Control` 実行ログと Service Control API のレスポンス（HTTP/本文）、対象 realm の解決（`realm`/`tenant`）を確認。

## 関連
- `apps/aiops_agent/docs/cs/ai_behavior_spec.md`
- `apps/aiops_agent/docs/oq/oq_usecase_02_monitoring_auto_reaction.md`
- `apps/aiops_agent/docs/oq/oq_usecase_04_enrichment.md`
- `apps/workflow_manager/workflows/service_request/aiops_sulu_service_control.json`
