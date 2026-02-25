# 新規コンポーネント設計（案）: Horilla + n8n + GitLab で人材・タレント管理を実現する

対象: `docs/itsm/usecase_new_component_report_2026-02-25.md`（UC-3701〜UC-3724）

## 0. 目的

人材・タレント管理（スキル台帳、育成計画、RACI、レビュー/監査、指標）を、既存の ITSM 基盤（GitLab/Zulip/n8n/SoR）と矛盾しない形で運用可能にする。

本設計の狙い:
- HR の「事実データ」は Horilla（HRMS）で保持
- 意思決定・承認・証跡・版管理は GitLab に寄せる（全部 Issue + MR）
- 連携・自動化・定期レポートは n8n

## 1. 前提（固定）

- Horilla は realm ごとにデプロイされる（URL: `https://<realm>.horilla.<domain>`）
  - 認証連携（Keycloak OIDC）は **当面設定しない**
- GitLab は realm ごとにグループ分離される（例: `/<realm>/...`）
- 本リポジトリの SoR（RDS PostgreSQL: `itsm.*`）は ITSM コアの正を扱う。人材・タレントの正本は原則 GitLab/Horilla で、SoR は「監査イベント・集計の派生（任意）」に留める。

## 2. 役割分担（SoR と証跡の置き場）

| コンポーネント | 正のデータ（SoR） | このユースケースで担う役割 |
| --- | --- | --- |
| Horilla | HR の事実（従業員/組織/配属など） | 人・組織の台帳 UI、データ供給元 |
| GitLab | 意思決定/承認/証跡/版（MR/Issue/Repo） | RACI/ポリシー/標準/育成計画/スキル更新の証跡、監査可能な履歴 |
| n8n | なし（再実行可能なオーケストレーション） | Horilla↔GitLab↔Zulip の連携、承認フロー実行、定期レポート |
| Zulip | なし（会話の場） | 合意形成の会話・通知の到達点 |
| SoR（`itsm.*`） | ITSM の正 | （任意）監査イベント投入・レポート用の派生集計スナップショット |

## 3. GitLab 側のリポジトリ設計（realm ごと）

### 3-1. 推奨: 専用プロジェクトを用意

- Group: `/<realm>/...`
- Project（案）: `/<realm>/hr-talent-management`

理由:
- 人材データは取り扱いがセンシティブで、ITSM の運用プロジェクト（service-management 等）と分けやすい
- 版管理（MR）、監査（レビュー/承認）を「人材領域」で閉じられる

### 3-2. リポジトリ構成（MVP）

GitLab リポジトリ上で、最低限「構造化データ（YAML/CSV）」「証跡リンク」「レポート」を保持する。

- `catalog/`
  - `skills.yml`: スキルの辞書（skill_id, name, category, level定義）
  - `roles.yml`: ロール/職務（role_id, name, responsibilities）
- `people/`
  - `people.yml`: person_key と Horilla の employee_code などの対応
  - `org.yml`: 組織ツリー（Horilla 起点で同期する場合のスナップショット）
- `ledger/`
  - `people_skills.yml`: スキル台帳（person_key, skill_id, level, evidence_refs, updated_at）
  - `role_skills.yml`: ロール別の期待スキル（role_id, skill_id, expected_level）
- `plans/`
  - `development_plans.yml`: 育成計画（person_key, goal, due_date, status, linked_issues）
- `raci/`
  - `raci.yml`: 活動単位の RACI（activity_id, R/A/C/I の role_id リスト）
- `reports/`
  - `YYYY/people_skills_summary_YYYY-MM.md`: 月次レポート（n8n が生成し MR で反映）
- `docs/`
  - `policy.md`: 人材・スキル運用方針（変更は MR で審査）
  - `standard.md`: 標準/ガイドライン

データ形式の注意:
- person の識別子は `person_key`（例: `emp_12345`）を正とし、Horilla の内部IDに依存しない
- `evidence_refs` は GitLab Issue/MR の URL や `gitlab:issue:<path>#<iid>` 形式を推奨

## 4. n8n ワークフロー設計（MVP）

### 4-1. ワークフロー一覧（案）

| Workflow | トリガ | 目的 | 出力 |
| --- | --- | --- | --- |
| `hr_talent_horilla_snapshot_sync` | Cron（日次）/手動OQ | Horilla から人・組織のスナップショットを取得して GitLab に反映 | `people/people.yml`, `people/org.yml` を更新する MR |
| `hr_talent_skill_update_request` | Webhook | スキル更新の要求を受け、GitLab Issue を起票（承認フロー開始） | Issue 作成 + Zulip 通知 |
| `hr_talent_skill_update_apply` | GitLab Issue コメント監視（Cron） | Issue が承認状態になったら、台帳（YAML）へ反映する MR を作成 | MR 作成 + Issue へリンクコメント |
| `hr_talent_development_plan_report` | Cron（月次） | 育成計画・スキル台帳のサマリを生成して `reports/` へ MR | MR 作成 + Zulip 通知 |
| `hr_talent_test` | Webhook（テスト） | 接続（Horilla/GitLab/Zulip）と最小の read/write を検証 | テスト結果を JSON 返却 +（任意）Zulip 投稿 |

### 4-2. 承認フロー（MVP: GitLab Issue ベース）

GitLab CE 前提で「Issue + ラベル + コメント」で承認状態を表現する。

- 起票: `skill-update` ラベル付き Issue（テンプレで入力項目を固定）
- 承認: 権限者が `/approve` コメント（または `approved` ラベル付与）
- 反映: n8n が承認を検出し、YAML 変更の MR を作成
- 監査: Issue（承認コメント）と MR（差分）が証跡

実装メモ（MVP の具体ルール）:
- Issue ラベル（例）:
  - `hr-skill-update`
  - `status:pending-approval` → `status:applied`
  - `status:approved`（ラベル承認を許可する場合）
- 承認検出（いずれか）:
  - コメント本文が `/approve` で始まる
  - ラベル `status:approved` が付与されている
- Issue 本文に JSON payload を HTML comment として埋め込み、反映側がパースする:
  - `<!--HR_TALENT_SKILL_UPDATE_JSON:{...}-->`
- MR で更新するファイル（MVP）:
  - `ledger/skill_updates/skill_update_<issue_iid>.yml`（追記型、パース不要にして簡素化）

## 5. Horilla 連携（設計の置き方）

Horilla は HR の「事実データ」の正であり、MVP では以下のどちらかで進める。

- 方式A（推奨）: Horilla に API がある前提で、n8n から read-only 同期（人/組織）を実施
- 方式B（フォールバック）: Horilla から CSV エクスポート（人/組織）を GitLab にコミットし、n8n は GitLab 側だけを見る

注意:
- 認証統合は当面しないため、n8n は Horilla のサービスアカウント/APIトークンでアクセスする（値は SSM 管理）

## 6. セキュリティ・秘密情報

- n8n で利用するトークン/資格情報は tfvars に平文で置かず、SSM/Secrets Manager から注入する
- GitLab リポジトリに個人情報（PII）を持ち込みすぎない
  - `people/people.yml` は最小限（employee_code, person_key 程度）に留める
  - 氏名・メール等は原則 Horilla 側で参照し、GitLab は識別子と証跡リンクに寄せる

## 7. realm 対応（必須）

- Horilla: `https://<realm>.horilla.<domain>`
- GitLab: `/<realm>/...` の group/path を realm 設定として持つ
- Zulip: realm ごとに stream/topic の規約（例: `#gm-people`）を固定し、n8n が realm→宛先を解決する

推奨: `itsm_hr_talent_management` が realm 設定（Horilla URL, GitLab project, Zulip stream）を 1 箇所で管理する。

## 8. 実装フェーズ（提案）

### Phase 0（設計固め）
- GitLab 側のリポジトリ構成（ディレクトリ/ファイル形式）を確定
- Issue テンプレ（スキル更新/育成計画/レビュー）を確定

### Phase 1（MVP）
- n8n:
  - 承認付きスキル更新（Issue→承認→MR）
  - 月次レポート生成（MR）
  - テスト workflow（`hr_talent_test`）
- GitLab:
  - `hr-talent-management` プロジェクトの雛形投入（テンプレ/初期データ）
- Horilla:
  - 人・組織スナップショット同期（方式A or B）

### Phase 2（任意）
- SoR（`itsm.*`）へ監査イベント投入（`itsm.audit_event`）
- 指標の可視化（Athena/Grafana）用に S3 へ集計結果を出す

## 9. 受け入れ条件（MVP）

- スキル台帳が realm ごとに更新履歴つきで管理できる（MR 差分）
- スキル更新が「承認」を経て反映される（Issue→承認→MR）
- 育成計画が Issue とレポートで追跡できる（定期レポート MR）
- Horilla の人・組織の“正”と矛盾しない（少なくとも識別子の整合が取れる）

## 10. UC-3701〜UC-3724 詳細設計（トレーサビリティ）

詳細設計（実装/運用の置き場）:
- `apps/itsm_core/itsm_hr_talent_management/docs/cs/cs.md`
- `apps/itsm_core/itsm_hr_talent_management/docs/cs/usecases_uc3701_uc3724.md`

MVP 実装（主要）:
- 承認付きスキル更新: `apps/itsm_core/itsm_hr_talent_management/workflows/hr_talent_skill_update_*.json`
- 月次レポート生成: `apps/itsm_core/itsm_hr_talent_management/workflows/hr_talent_monthly_report_*.json`
- GitLab テンプレ（台帳/方針/Issueテンプレ）: `scripts/itsm/gitlab/templates/hr-talent-management/`
