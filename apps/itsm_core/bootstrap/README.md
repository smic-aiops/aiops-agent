# コンピュータ化システムバリデーション（CSV）
## 最小ドキュメントセット
### ITSM Bootstrap（GitLab） / GAMP® 5 第2版（2022, CSA ベース, IQ/OQ/PQ を含む）

---

## 1. CSV / CSA ポリシー
**目的**
`apps/README.md` の共通フォーマットに従い、リスクベース（CSA）で最小限の成果物として本 README と検証証跡を維持する。

**内容**
- 本アプリ（ITSM Bootstrap）の仕様・運用・検証の入口を README に集約し、詳細は `apps/itsm_core/bootstrap/docs/` / `apps/itsm_core/bootstrap/scripts/` を参照する。
- テンプレート（Docs/Wiki/Issue template 等）の正は `apps/itsm_core/bootstrap/data/templates/` とする。
- 秘密情報（GitLab/Grafana のトークン等）は tfvars に平文で置かず、SSM/Secrets Manager → 環境変数注入を前提とする。

---

## 2. バリデーション計画（VP）
**目的**
対象範囲（スコープ）と検証戦略を定義する。

**内容**
- システム名: ITSM Bootstrap（GitLab）
- 対象:
  - ITSM テンプレート（GitLab 側へ投入する Markdown/YAML/Issue template/Wiki template 等）
  - GitLab へのブートストラップ実行スクリプト群（realm グループ作成、テンプレ投入、トークン更新等）
  - ユースケース関連の補助スクリプト（Grafana ユースケースダッシュボード同期 等）
- 非対象:
  - GitLab/Grafana 自体の製品バリデーション
  - ネットワーク/認証基盤（Terraform/IaC 側）全般
- バリデーション成果物（最小）:
  - 本 README
  - Requirements: `apps/itsm_core/bootstrap/docs/app_requirements.md`
  - CS（AIS）: `apps/itsm_core/bootstrap/docs/cs/ai_behavior_spec.md`
  - OQ 入口: `apps/itsm_core/bootstrap/docs/oq/oq.md`
  - OQ 実行補助: `apps/itsm_core/bootstrap/scripts/run_oq.sh`

---

## 3. 意図した使用（Intended Use）とシステム概要
**目的**
GitLab 側の ITSM 用プロジェクト/テンプレート/運用資材を、レルム単位で再現性高く投入し、運用手順とユースケースの参照先（SSoT）を一貫させる。

**内容**
- Intended Use（意図した使用）
  - GitLab のレルム用グループ/プロジェクトを整備し、テンプレ（Docs/Wiki/Issue template 等）を投入/同期する。
  - ITSM のユースケース（UC-*）定義テンプレを SSoT として維持し、参照箇所の一貫性を担保する。
  - （任意）Grafana のユースケース向けダッシュボード雛形を realm ごとに同期し、運用導線を整備する。
- 高レベル構成
  - Operator →（Terraform output/環境変数解決）→ Bootstrap scripts → GitLab API（＋任意で Grafana API）

---

## 主要ファイル（SSoT）
- テンプレ（正）: `apps/itsm_core/bootstrap/data/templates/`
- GitLab bootstrap（入口/正）: `apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh`
- GitLab realm 前提整備: `apps/itsm_core/bootstrap/scripts/ensure_realm_groups.sh`
- Grafana ユースケース同期: `apps/itsm_core/bootstrap/scripts/sync_usecase_dashboards.sh`

---

## 4. GxP 影響評価とリスクアセスメント
**目的**
データ完全性/再現性/監査性の観点で、重大なリスクのみを識別する。

**内容（critical のみ）**
- テンプレ誤投入・差分不整合 → SSoT を 1 箇所（`apps/itsm_core/bootstrap/data/templates/`）へ集約し、OQ（静的チェック）で参照切れ/構文エラーを検出
- 過剰な上書き（本番資産の破壊）→ `--files-only` / `DRY_RUN` 等の段階適用と、適用対象の明示

---

## 5. 検証戦略（Verification Strategy）
**目的**
Intended Use に適合することを、最小の検証で示す。

**内容**
- IQ: テンプレ/スクリプトが配置され、実行に必要な前提（コマンド等）が満たせること
- OQ: 静的チェック（参照切れ/シェル構文）と、段階適用用の `--dry-run` が成立すること
- PQ: 実運用の適用頻度/差分量に対する成立性（最小）

---

## 6. 設置時適格性確認（IQ）
**文書**
- `apps/itsm_core/bootstrap/docs/iq/iq.md`

---

## 7. 運転時適格性確認（OQ）
**文書**
- `apps/itsm_core/bootstrap/docs/oq/oq.md`

**実行**
- `apps/itsm_core/bootstrap/scripts/run_oq.sh --dry-run`

---

## 8. 稼働性能適格性確認（PQ）
**文書**
- `apps/itsm_core/bootstrap/docs/pq/pq.md`

---

## 9. バリデーションサマリレポート（VSR）
**目的**
本アプリのバリデーション結論を最小で残す。

**内容（最小）**
- 実施した IQ/OQ/PQ の一覧、結果サマリ、逸脱と対処、運用開始可否の判断

---

## 10. 継続的保証（運用フェーズ）
**目的**
バリデート状態を維持する。

**内容**
- 変更は Git の差分 + 必要最小限の OQ 再実施で追跡する（変更管理は `docs/change-management.md` を参照）。
