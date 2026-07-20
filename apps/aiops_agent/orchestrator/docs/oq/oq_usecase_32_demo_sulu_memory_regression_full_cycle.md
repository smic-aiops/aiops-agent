# OQ-USECASE-32: Suluメモリ回帰の統合デモ

## 目的

Suluの直近デプロイ後に発生したメモリ高騰2件とOutOfMemoryを相関し、復旧候補の順位付け、CAB承認、修正branch/MR/RFC生成、テスト・リスク評価、修正版デプロイ、CMDB同期、関連チケットのクローズ、KEDB/Qdrant同期までを同一`trace_id`で追跡できることを確認する。

対象ワークフローは`wf.sulu_memory_regression_demo`、Webhookは`POST /webhook/sulu/memory-regression-demo`である。
復旧候補の契約は`apps/workflow_manager/service_request/schemas/aiops.recovery_candidates.v1.schema.json`を正とする。

## 安全設計

- 既定はローカルdry-runで、n8n、GitLab、ECR、ECS、CMDBへ変更を行わない。
- `--execute`だけではn8n上のdry-runを実行する。
- フルOQには`--full-oq --confirm-realm <realm> --decision-id <id> --gitlab-code-project <path>`が必要である。
- フルOQでは、GitLab書込み、CI、ECR push、サービス変更、状態更新の各ガードがすべて明示的に有効化される。
- ワークフローはCAB/eCABの`decision_id`、全必須テストの合格、High以外のリスク評価が揃わない限り、修正版の適用準備完了と判定しない。
- CMDB同期、チケットクローズ、KEDB登録には、同一実行の`execute_fixed_deploy=true`または`post_deploy_verified=true`と`verification_id`を必須とする。
- ライブ経路ではcode projectとservice-management projectを分離する。code projectはfix branch/MR/CI、service-management projectはRFC、CMDB、Incident/Problem/Change、Known Errorを保持する。
- CodeBuildのソースリポジトリがGitLab code projectのpush mirrorである場合、修正branchがmirror先へ到達し、期待するcommit SHAを取得できることをECR push前に確認する。未到達またはSHA不一致の場合は停止する。
- 統合ワークフローは`build_source.source_ref`をCodeBuildへ渡す前に参照先APIで解決し、`artifacts.commit_id`と`artifacts.source_mirror.resolved_commit_sha`を自動照合する。

## 固定フィクスチャ

`apps/aiops_agent/orchestrator/scripts/tests/fixtures/sulu_memory_regression_full_cycle.json`を使用する。

- `V_PREVIOUS=3.0.3`
- `V_LATEST=3.0.4`
- `V_FIXED=3.0.4-smic.1`
- メモリ92%と94%の2イベント
- 同じrealm、service、image tagのOOMイベント
- デプロイ後30分以内の時系列

## 受入基準

1. `correlation.status=correlated`かつ`confidence>=0.9`である。
2. 異なる2つのメモリイベント、OOM、直近デプロイが根拠として保存される。
3. `aiops.recovery_candidates.v1`として3件以上の復旧候補が返る。
4. 第1候補が`wf.sulu_version_deploy`による`V_PREVIOUS`へのロールバックである。
5. 各候補に順位、根拠、リスク、可逆性、承認要否が含まれる。
6. fix branch、MR、RFC、選択テスト、テスト結果、リスクスコアが返る。
7. service-management projectにIncident、Emergency Change、Problem、恒久対策Change/RFCを自動生成し、相互リンクする。
8. フルOQでは`V_FIXED`のECR作成とECSデプロイがCAB承認後にだけ行われる。
9. 最終検証IDを保存した後にCMDBの現行バージョンを更新し、入力Issueと自動生成Issueを重複なくクローズする。
10. CMDBへ`last_change_trace_id`、RFC URL、`last_verification_id`、検証時刻を保存する。
11. Known Error Issueを作成し、GitLab Issue backfillでSoR同期、Issue RAG syncでQdrant同期を完了する。
12. `demo_screens.video_1_*`から`video_4_*`がすべて`ready`となる。
13. フルOQでは`artifacts.source_mirror.status=verified`で、期待SHAと解決SHAが一致する。SHA不一致はHTTP 409で停止する。
14. リスクスコアは基礎リスク、変更ファイル数、相関confidence、失敗／未完了テスト、全テスト合格の加減点根拠を返す。

## 実行

```bash
# ローカルdry-run。外部通信なし
bash apps/aiops_agent/orchestrator/scripts/run_oq_usecase_32_demo_sulu_memory_regression_full_cycle.sh

# n8n上のdry-run
bash apps/aiops_agent/orchestrator/scripts/run_oq_usecase_32_demo_sulu_memory_regression_full_cycle.sh \
  --execute \
  --evidence-dir outputs/oq/sulu-memory-dry-run

# 実変更を含むフルOQ
bash apps/aiops_agent/orchestrator/scripts/run_oq_usecase_32_demo_sulu_memory_regression_full_cycle.sh \
  --full-oq \
  --realm aiops \
  --confirm-realm aiops \
  --decision-id <CAB_DECISION_ID> \
  --gitlab-code-project aiops/aiops-agent \
  --gitlab-service-project aiops/service-management \
  --ticket-iids <INC_IID>,<PRB_IID>,<CHG_IID> \
  --evidence-dir outputs/oq/sulu-memory-full
```

## 30秒録画手順

録画前にブラウザタブを、Grafana／n8n、Zulip、GitLab、CMDB/KEDBの順に並べる。各動画では同じ`trace_id`を表示し、秘密情報をマスクする。

### 動画1：複数情報の相関分析（PPTX 58ページ）

| 秒 | 画面 | 操作・表示 |
| ---: | --- | --- |
| 0–5 | Grafana | メモリ92%、94%とOOMを時系列で表示 |
| 5–15 | n8n | `correlation.evidence`で直近デプロイ、2メトリクス、OOMを順に展開 |
| 15–24 | n8n | 同一realm／service／image tagと30分窓のチェックを表示 |
| 24–30 | Zulip | 原因候補、confidence、trace_idを表示 |

### 動画2：復旧策を優先順位付きで提示（PPTX 60ページ）

| 秒 | 画面 | 操作・表示 |
| ---: | --- | --- |
| 0–8 | Zulip | 障害要約と「復旧候補を表示」を投稿 |
| 8–20 | n8n/Zulip | 1位ロールバック、2位再起動、3位手動診断を表示 |
| 20–26 | Zulip | 各候補の根拠、risk、reversible、requires_approvalを表示 |
| 26–30 | Zulip | 1位を選択し、CAB承認リンクへ遷移 |

### CAB承認画面（PPTX 66ページ）

既存OQ-31の承認リンク、`/decision`、Approval Historyを流用する。統合デモの`trace_id`、第1候補、テスト結果、リスクスコア、ロールバック先を承認メッセージへ含める。

### 動画3：変更要求と影響分析（PPTX 64ページ）

| 秒 | 画面 | 操作・表示 |
| ---: | --- | --- |
| 0–8 | GitLab | 自動生成されたfix branchとMRを表示 |
| 8–16 | GitLab | 変更ファイルとメモリ対策コードを表示 |
| 16–23 | GitLab CI/CD | 選択テストと成功結果を表示 |
| 23–30 | GitLab Issue | RFC、影響CI、リスクスコア、CAB判断材料を表示 |

### 動画4：CMDB・KEDB・プロセス連携（PPTX 71ページ）

| 秒 | 画面 | 操作・表示 |
| ---: | --- | --- |
| 0–7 | Sulu/Grafana | `V_FIXED`とHTTP／メモリ正常化を表示 |
| 7–15 | GitLab CMDB | `current_version=V_FIXED`と変更traceを表示 |
| 15–22 | GitLab/RDS | Incident、Problem、ChangeのClosedを表示 |
| 22–28 | GitLab/Qdrant | Known ErrorとKEDB検索結果を表示 |
| 28–30 | n8n | `video_4_closure.status=ready`とtrace_idを表示 |

## フォールバック

ライブ実行が中断した場合は、`outputs/oq/<run_id>/integrated-demo-response.json`を表示する。どの地点から保存済み証跡へ切り替えたかを明示し、未実行の処理を実行済みとして説明しない。
