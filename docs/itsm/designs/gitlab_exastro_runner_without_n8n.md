# デプロイメント管理（n8n 非依存）設計: GitLab + Exastro ITA + GitLab Runner

本設計は、`docs/itsm/itsm-platform.md` の方針に従い、**連携/自動化を n8n に寄せなくても成立する**デプロイメント管理のユースケースを、**GitLab / Exastro ITA / GitLab Runner** のみで実現するための設計メモです。

対象（CSV のユースケース群）:
- デプロイメント管理: `UC-2902`〜`UC-3028` のうち、ワークフロー・カタログ（n8n 前提）を除くもの

## 前提

- GitLab は変更・証跡・CI/CD の正本（SoR は ITSM 監査/決定の正規化領域として別途存在）
- GitLab Runner は、本リポジトリの Terraform でデプロイされる ECS/Fargate の shell executor を想定
  - runner 作成/トークン管理は `scripts/itsm/gitlab/ensure_gitlab_runner.sh` を利用する
- Exastro ITA は「構成作業の実行面」に限定し、GUI（Web）か API を GitLab CI から呼び出す

## 役割分担（最小構成）

- GitLab
  - 変更要求/設計/実装の記録（Issue/MR）
  - 承認ゲート（Protected branch / MR approval / protected environments）
  - 実行オーケストレーション（CI/CD pipelines / pipeline schedule）
  - 監査証跡（pipeline/job log、Artifacts、Releases、Deployments）
- GitLab Runner
  - `terraform plan/apply`、テスト、署名/検証、API 呼び出し（Exastro）等を実行
- Exastro ITA（Web/API）
  - Conductor / Movement / Operation による「構成作業の定義と実行」

## 実行フロー（標準）

1. 変更要求（Change/Deploy request）を GitLab Issue（サービス管理プロジェクト）として起票し、対象リポジトリ/MR と相互リンクする。
2. MR で差分レビュー → 承認（MR approval）。
3. GitLab CI が以下を順に実行（環境ごとに分岐）:
   - validate: lint / unit test / policy check
   - build: アーティファクト作成（必要なら SBOM/署名）
   - deploy(staging): Exastro ITA の Conductor を起動（API 呼び出し）または Runner 上で構成適用
   - smoke/e2e: スモーク/回帰
   - deploy(prod): protected environment + manual job で本番反映
   - verify: デプロイ結果（バージョン/ヘルス）を確認し、証跡（Artifacts/Release/Deployment）を更新
4. 失敗時は rollback ジョブ（manual）を提示し、実行結果を Issue/MR に紐付ける。

## 実装パターン（ユースケース対応の考え方）

- カナリア/ダークローンチ/段階ロールアウト
  - GitLab の Environments を「tenant/region/stage」単位で分ける
  - `when: manual` + `needs:` で段階実行（例: `prod-canary` → `prod-10%` → `prod-100%`）
- スケジュール管理
  - GitLab pipeline schedules を正とし、freeze window は protected environment のルールで担保
- DB 変更を伴うデプロイ
  - schema migration を独立ジョブ化し、`manual` + 承認を必須にする
  - migration の実行証跡は job log + artifact（SQL/ログ）を保存
- 署名/検証（リリース資産）
  - build ジョブで署名し、deploy ジョブで検証する（鍵は GitLab CI variables / runner secret 経由）
- トレーサビリティ/監査証跡
  - pipeline/job log、Artifacts、Release（tag）、Deployment（environment）を必須にする

## Exastro ITA 呼び出し（GitLab CI から）

- Exastro ITA の API は GitLab CI ジョブから `curl` 等で呼び出す（n8n は不要）
- 起動する単位:
  - Conductor: デプロイ手順全体（標準フロー）
  - Movement: 個別の構成適用（例: restart、config update）
  - Operation: 対象（tenant/region/env）をパラメータとして切り替える

## 運用ルール（最低限）

- 本番反映は protected environment + manual job を必須とし、誰がいつ実行したかを GitLab で追える状態にする
- 失敗時に備え、rollback ジョブは「常に定義」し、入力 validation と安全側の失敗（no-op）を優先する

