# OQ-31: GitLab 構成誤変更からの CAB 承認付き Sulu 復旧

## 目的

デモシナリオ2について、GitLab 上の構成誤変更、修正 Merge Request、変更 Issue、AIOps Agent の承認要求、CAB 承認、復旧ワークフロー実行、検証、記録・クローズまでが一連の証跡として追跡できることを確認する。

## 安全設計

- 既定は `dry_run=true` であり、Sulu や Exastro ITA へ実変更を行わない。
- GitLab の既定ブランチは変更しない。OQ 専用の誤設定ブランチと修正ブランチを作り、その間の MR を作成する。
- 実サービス変更には `--apply-service-change` とワークフロー引数 `allow_service_change=true` の両方が必要である。
- 共有 `aiops` realm では、専用デモ realm の確認なしに `--apply-service-change` を使用しない。

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

## 実行

```bash
# 必須dry-run
apps/aiops_agent/orchestrator/scripts/run_oq_usecase_31_demo_gitlab_misconfiguration_cab_recovery.sh

# 非破壊の実環境OQ
apps/aiops_agent/orchestrator/scripts/run_oq_usecase_31_demo_gitlab_misconfiguration_cab_recovery.sh \
  --execute \
  --evidence-dir outputs/oq/usecase-31-$(date +%Y%m%d-%H%M%S)
```

## Exastro ITA の位置付け

本OQでは、CAB承認後の適用を `Sulu Service Control` 経由で表現する。Exastro ITA API は起動済みでも、現在の環境では Keycloak SSO を有効にしたAPI認証契約が確定していないため、既定経路には組み込まない。ITAを本適用へ組み込む場合は、Keycloak client、token endpoint、ITA organization/workspace、Conductor ID、Operation ID、Movement/Parameter Set、完了待ちAPIを追加設定する。

## 現在の既知事項

- CAB承認、ジョブ投入、承認履歴記録は成功する。
- CloudWatchイベントからGitLab差分を自動検索する相関処理は本OQの対象外である。OQはIssue/MR/commitを作成した後、明示実行パラメータとしてAgentへ渡す。
- 承認後のZulip完了通知は、`aiops-zulip-basic` 資格情報の認証エラーにより失敗する場合がある。OQの合格判定はn8n実行結果とGitLab証跡を正とするが、ライブデモ前にZulip botのメール/API keyを更新し、通知成功を再確認する。

## 実サービス変更モードの前提

`--apply-service-change` はSulu停止を再現するものではなく、承認済みの復旧として `action=up` を実行する。誤変更による停止そのものを含むフルデモは、専用realmまたは停止許可済み時間帯で別途実施する。
