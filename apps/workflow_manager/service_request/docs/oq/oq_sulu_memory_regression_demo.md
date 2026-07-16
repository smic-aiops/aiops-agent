# OQ: Suluメモリ回帰統合デモ

## 目的

直近デプロイ、同一対象のメモリ高騰2件、OOMを相関し、復旧候補、修正branch/MR/RFC、選択テスト、CI、リスク評価、CMDB／チケット／KEDB連携を1つの応答で追跡できることを確認する。

## 安全設計

- `POST /webhook/sulu/memory-regression-demo`の既定はdry-runである。
- ライブGitLab書込み、CI、ECR push、ECS変更、状態変更は個別の明示許可を必要とする。
- `gitlab.code_project_path`にはfix branch、commit、MR、Pipelineを作成し、`gitlab.service_project_path`にはRFC、CMDB、Incident/Problem/Change、Known Errorを作成する。ライブ経路では両プロジェクトを分離する。
- CodeBuild実行前に、code projectの修正branchがCodeBuildの参照するソースリポジトリまたはpush mirrorへ到達し、期待するcommit SHAを取得できることを確認する。
- サービス変更にはCAB/eCABの`decision_id`、必須テスト合格、High以外のリスク評価を必要とする。
- セルフテストは固定フィクスチャだけを使用し、外部HTTPを呼ばない。

## 受入基準

- 4証拠が同一realm・service・image tag、デプロイ後30分以内である。
- `aiops.recovery_candidates.v1`に3候補以上あり、第1候補が旧版へのVersion Deployである。
- code projectのbranch／MR／CIとservice-management projectのRFC、選択テスト、テスト結果、リスクスコアを返す。
- 応答の`artifacts.code_project_path`と`artifacts.service_project_path`が入力した別プロジェクトを示す。
- 4動画に対応する`demo_screens`がすべて`ready`である。
- 別realmのOOM、時間窓外のOOM、`..`を含む修正パス、認証不一致を拒否する。

## 非破壊テスト

```bash
node apps/workflow_manager/service_request/scripts/tests/test_sulu_memory_regression_demo.mjs
bash apps/aiops_agent/orchestrator/scripts/run_oq_usecase_32_demo_sulu_memory_regression_full_cycle.sh --realm aiops
```

詳細なライブOQと30秒録画手順は`apps/aiops_agent/orchestrator/docs/oq/oq_usecase_32_demo_sulu_memory_regression_full_cycle.md`を正とする。
