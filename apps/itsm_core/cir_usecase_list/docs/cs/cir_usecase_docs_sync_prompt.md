# CIR → Apps Docs Sync Prompt（テンプレート）
## apps/itsm_core/cir_usecase_list/docs/cs/cir_usecase_docs_sync_prompt.md

> 本書は「CIR（継続的改善レジスター）＝ GitLab Issue」を起点に、
> Approved な改善機会からユースケースを抽出し、各アプリの Requirements/DQ を更新するための **プロンプトテンプレート**である。
> 形式は `apps/*/docs/cs/ai_behavior_spec.md` に準拠する。

---

## 1. 目的と適用範囲

本プロンプトは、CIR（一般管理プロジェクトの GitLab Issue）で `状態/Approved` のレコードを一覧し、そこから抽出されたユースケース（`UC-*`）をもとに、対象アプリのドキュメント（Requirements/DQ）を **不足があれば追記**して整合性を維持する。

適用対象（realm overlay へ追記する。共通 docs は編集しない）:
- `vendor/<name_prefix>/apps/<app>/realms/<realm_key>/docs/app_requirements.md`
- `vendor/<name_prefix>/apps/<app>/realms/<realm_key>/docs/dq/dq.md`
- `vendor/<name_prefix>/apps/itsm_core/<sub_app>/realms/<realm_key>/docs/app_requirements.md`
- `vendor/<name_prefix>/apps/itsm_core/<sub_app>/realms/<realm_key>/docs/dq/dq.md`

参照対象（読み取りのみ）:
- `apps/<app>/docs/app_requirements.md`（共通ベース）
- `apps/<app>/docs/dq/dq.md`（共通ベース）
- `apps/itsm_core/<sub_app>/docs/app_requirements.md`（共通ベース）
- `apps/itsm_core/<sub_app>/docs/dq/dq.md`（共通ベース）

非対象:
- 本プロンプトは実装変更（コード/ワークフロー同期）そのものを目的としない（ドキュメント整合の維持が目的）。
- realm overlay 以外（`scripts/`, `workflows/`, `README.md`, 共通 docs 等）への書き込みは行わない。

---

## 2. 前提（入力/環境）

### 2.1 必須入力（プロンプト入力として渡す）

- `target_app_root`: 対象アプリのルートパス（例: `apps/aiops_agent` / `apps/workflow_manager` / `apps/itsm_core/gitlab_issue_metrics_sync`）
- `name_prefix`: `terraform output -raw name_prefix` を正として解決した name_prefix（例: `prod-aiops`）
- `realm_key`: 組織（realm）キー（例: `smoc` / `tenant-a`）。`default` を暗黙採用しない（必ず入力で与える）
- `mode`: `dry-run` または `apply`

### 2.2 任意入力

- `n8n_base_url`: 既定は環境設定（terraform output 等）を正とする
- `gitlab_project_id` / `gitlab_project_path`: 一般管理プロジェクトの明示指定（未指定の場合はワークフロー既定に従う）

---

## 3. 禁止・制限される振る舞い（Hard Rules）

- 秘匿情報（APIキー/パスワード/SSM値等）を出力しない（マスクが不十分な推測も含む）
- 外部 URL へのアクセスは `mode=apply` のときのみ許可する（`dry-run` では呼び出しを行わない）
- ドキュメントの追記は **最小差分**で行い、既存の構造・採番・表記を崩さない
- 既存ユースケース/既存DQ項目と **重複する追記**をしない
- 不確実性が残る場合は、追記しない（代わりに「不足情報」を列挙する）
- 書き込み先は realm overlay に限定する（共通ベース docs は read-only とみなす）

---

## 4. 手順（このプロンプトが実施すること）

### 4.1 対象アプリのドキュメント位置（共通ベース/realm overlay）を特定する

1. `target_app_root` 配下の `data/default/prompt/system.md` を読み、References（参照）セクションから次のファイルパスを特定する:
   - 共通 Requirements（例: `.../docs/app_requirements.md`）
   - 共通 DQ（例: `.../docs/dq/dq.md`）
2. 上記が見つからない場合は、既定の探索ルールで解決する:
   - 共通 Requirements: `${target_app_root}/docs/app_requirements.md`
   - 共通 DQ: `${target_app_root}/docs/dq/dq.md`
3. realm overlay の更新先を **必ず**次で解決する（このファイル群だけを編集する）:
   - overlay Requirements: `vendor/${name_prefix}/${target_app_root}/realms/${realm_key}/docs/app_requirements.md`
   - overlay DQ: `vendor/${name_prefix}/${target_app_root}/realms/${realm_key}/docs/dq/dq.md`
4. overlay ファイルが存在しない場合は作成する（最小構成。共通 docs を複製しない）:
   - overlay Requirements: 少なくとも `## 2.1 代表ユースケース（realm overlay）` セクションを作り、追記はそこへ行う
   - overlay DQ: 少なくとも `## Realm Overlay（追加/差分）` セクションを作り、追記はそこへ行う
   - いずれも先頭に「このファイルは realm overlay であり、共通ベース docs を参照する」旨を明記する

### 4.2 CIR Approved Usecase List ワークフローをコールする（`mode=apply` のみ）

1. n8n Webhook を呼び出す（例: `POST {n8n_base_url}/webhook/itsm/cir/usecases/approved/list`）。
2. 送る body は最小とし、必要なら上書きする:
   - `dry_run`: `mode=dry-run` の場合は `true`、`mode=apply` の場合は `false`
   - `gitlab_project_id` または `gitlab_project_path`（指定がある場合）
3. 応答 JSON を受け取る（期待キー例）:
   - `usecase_ids`: 抽出された `UC-*` の配列
   - `issues`: 参照元 Issue（`web_url`, `iid`, `title` 等）

### 4.3 対象アプリに関係するユースケースだけを抽出する

1. 共通 Requirements（read-only）から既存の `UC-*` を抽出し、**プレフィックス集合**を作る。
   - 例: `UC-AIOPS-` / `UC-WM-` / `UC-ITSM-` / `UC-ZS-` など
2. ワークフロー応答の `usecase_ids` を上記プレフィックスでフィルタし、対象候補を得る。
3. プレフィックスが推定できない場合は、次を順に試す:
   - `target_app_root`（アプリ名）から既知の prefix を推定
   - Issue の本文（`usecase_lines` など）に「当該アプリ名」「当該アプリの識別子」が含まれるものだけを採用
4. それでも不明な場合は、追記しない（不足情報として「CIR Issue に UC-ID を明記してほしい」を返す）。

### 4.4 Requirements（realm overlay）を更新する（不足分のみ追記）

1. 既に記載済みの `UC-*` を **共通 Requirements + overlay Requirements** の両方から抽出して除外し、未記載のユースケースだけを対象にする。
2. overlay Requirements 内の `## 2.1 代表ユースケース（realm overlay）` を探し、なければ作成してそこへ追記する（共通の `## 2.1 ...` は編集しない）。
3. 追記は既存の書式に合わせる:
   - 箇条書き（`- UC-...: ...`）が基本
   - 採番・接頭辞（`UC-AIOPS-*` 等）は **CIR Issue に書かれているものを正**として採用する
4. 追跡性（traceability）のため、追記行末に参照元 CIR Issue（URL または iid）を括弧で付与する（可能な場合）。

### 4.5 DQ（realm overlay）を更新する（最小差分）

1. overlay DQ 内の `## Realm Overlay（追加/差分）` を探し、なければ作成する（共通 DQ は編集しない）。
2. 追記したユースケースに対応する DQ 追記を 1 点以上行う（最小でよい）:
   - 「設計スコープ」相当の追記（例: “UC-XXX 追加に伴い、○○の検証を追加する”）
   - または「変更管理（再検証トリガ）」相当の追記（例: “UC-XXX に関係するワークフロー変更時は再検証”）
3. Requirements にユースケースを追記したのに、DQ への反映ができない場合は、Requirements への追記も取りやめる（中途半端な整合崩れを防ぐ）。

---

## 5. 出力要件（このプロンプトの期待出力）

- 対象アプリ:
  - `target_app_root`
  - `realm_key`
- 参照した CIR:
  - 対象 Issue の件数、参照 URL（可能な範囲）
- 抽出したユースケース:
  - 採用した `UC-*` の一覧（アプリ関連に絞った結果）
  - 既に記載済みでスキップした `UC-*` の一覧
- 変更内容（差分サマリ）:
  - overlay Requirements の追記点
  - overlay DQ の追記点
- 前提・不確実性:
  - 例: 「CIR Issue に UC-ID が書かれていないため自動追記できない」

---

## 6. 参照（構成品目）

- Approved CIR 一覧/抽出（n8n）:
  - ワークフロー: `apps/itsm_core/cir_usecase_list/workflows/itsm_cir_approved_usecases_list.json`
  - Webhook: `POST /webhook/itsm/cir/usecases/approved/list`
- 既存プロンプト（参照元）:
  - `apps/*/data/default/prompt/system.md`
- AIS（形式の準拠先）:
  - `apps/*/docs/cs/ai_behavior_spec.md`
