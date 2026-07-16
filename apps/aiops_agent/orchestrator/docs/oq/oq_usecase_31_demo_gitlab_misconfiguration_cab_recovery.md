# OQ-31: GitLab 構成誤変更からの CAB 承認付き Sulu 復旧

## 目的

デモシナリオ2について、GitLab 上の構成誤変更、修正 Merge Request、変更 Issue、AIOps Agent の承認要求、CAB 承認、復旧ワークフロー実行、検証、記録・クローズまでが一連の証跡として追跡できることを確認する。

## 安全設計

- 既定は `dry_run=true` であり、Sulu や Exastro ITA へ実変更を行わない。
- GitLab の既定ブランチは変更しない。OQ 専用の誤設定ブランチと修正ブランチを作り、その間の MR を作成する。
- 実サービス変更には `--apply-service-change` とワークフロー引数 `allow_service_change=true` の両方が必要である。
- 実停止を含むフルOQには `--full-oq --confirm-service-stop <realm>` が必要である。
- フルOQは `EXIT` trap を設定し、途中失敗でもSuluへ `action=up` を送り、ECSと外形HTTPの復旧を確認する。

## 対象

- `Sulu Configuration Recovery`
  - `meta.workflowId=wf.sulu_configuration_recovery`
  - Webhook: `POST /webhook/sulu/configuration-recovery`
- `Test Sulu Configuration Recovery`
  - Webhook: `POST /webhook/tests/sulu/configuration-recovery`
- `aiops-job-engine-queue`
  - `wf.sulu_configuration_recovery` のディスパッチ
- AIOps Adapter の明示実行・承認経路
  - `run wf.sulu_configuration_recovery {...}`
  - `POST /webhook/approval/confirm`

## 受入基準

1. GitLab のOQ専用ブランチに `demo/sulu-runtime.yml` の `desired_state: down` が作成される。
2. 修正ブランチで `desired_state: up` へ戻すMRと変更Issueが作成される。
3. Agent が `next_action=require_approval` と承認トークンを発行する。
4. CAB 承認後、ジョブエンジンが `wf.sulu_configuration_recovery` を実行する。
5. 非破壊モードでは結果が `status=validated`, `dry_run=true`, `simulated=true`, `applied=false` となる。
6. リスク、影響CI、テスト、ロールバック計画、GitLab Issue/MR URL が結果に含まれる。
7. 結果がGitLab Issueへ追記され、Issueと未マージMRがクローズされる。
8. フルOQではSuluが実際に `desiredCount=0/runningCount=0` へ遷移する。
9. CloudWatchイベント時刻からGitLab全refの直近commit差分を検索し、`desired_state: down` のcommitを原因候補として選択する。
10. 復旧後にSuluが `desiredCount>=1/runningCount>=1` かつ外形HTTP 2xxとなる。
11. CAB承認後のZulip通知が成功する。

## 実行

```bash
# 必須dry-run
apps/aiops_agent/orchestrator/scripts/run_oq_usecase_31_demo_gitlab_misconfiguration_cab_recovery.sh

# 非破壊の実環境OQ
apps/aiops_agent/orchestrator/scripts/run_oq_usecase_31_demo_gitlab_misconfiguration_cab_recovery.sh \
  --execute \
  --evidence-dir outputs/oq/usecase-31-$(date +%Y%m%d-%H%M%S)

# 実Sulu停止を含むフルOQ（停止許可済み時間帯のみ）
apps/aiops_agent/orchestrator/scripts/run_oq_usecase_31_demo_gitlab_misconfiguration_cab_recovery.sh \
  --execute \
  --full-oq \
  --confirm-service-stop aiops \
  --evidence-dir outputs/oq/usecase-31-full-$(date +%Y%m%d-%H%M%S)
```

## Exastro ITA の位置付け

復旧ワークフローには `EXASTRO_ITA_DEFAULT_BACKEND=exastro` の場合にConductor実行APIを呼び、返却された `conductor_instance_id` を記録し、Service Control APIでSulu復旧を確認する経路を実装した。

ただし2026-07-16時点の実環境は `exastro-web` とSystem Management APIの `exastro-api-admin` のみであり、Conductor APIを提供する `ita-api-organization`、Conductor同期ワーカー、Ansible実行ワーカーが配備されていない。実APIでConductor endpointが404となるため、今回の合格実行は `execution_backend=service-control` を使用した。Exastro適用を有効化するには、これらの公式コンポーネントに加えてorganization/workspace、Conductor、Operation、Movement、Parameter Set、n8n側の `EXASTRO_ITA_*` 環境変数を配備する必要がある。

## 現在の既知事項

- CAB承認、ジョブ投入、承認履歴記録、承認後Zulip通知は成功する。
- Zulipはrealm別の実Botメール/API keyで `aiops-zulip-basic` を更新し、form-urlencodedで送信する。検証実行 `35080` はmessage id `60` を返した。
- CloudWatchイベント時刻を基準にGitLab commits APIを `all=true` で検索し、対象ファイルのdiffから原因commitを自動選択する。
- フルOQ合格実行は `trace_id=4df35d54-d0ec-4ee4-8937-ce859a702d66`、証跡は `outputs/oq/usecase-31-full-pass-20260716-155658/` に保存した。

## 実サービス変更モードの前提

`--apply-service-change` 単独は承認済み復旧として `action=up` のみを実行する。実停止からの全経路は `--full-oq --confirm-service-stop <realm>` を使用する。フルOQは実サービスへ影響するため、停止許可済み時間帯でのみ実施する。
