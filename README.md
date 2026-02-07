# aiops-agent

ITSM x AI Ops x AI Agent を組み合わせた運用のアイデアと手順を、**GAMP® 5 第2版（2022）/ CSA / NIST AI RMF** の観点で説明しやすい形で整理したリポジトリです。

本リポジトリは「最小で試す」ためのプロトタイプであり、規制対応を“自動的に満たす”ことを保証するものではありません。  
ただし、**変更管理下の構成**・**リスクベースの検証**・**証跡の保全**・**人による監督**を「実装とドキュメントの導線」として揃えることを重視します。

用語の読み替えは `docs/glossary.md` を参照してください。

## 留意点（作成・検証モデル / Codex の制約）

- 本リポジトリは **ChatGPT 5.2** で作成されています。
- 本リポジトリの拡張を含む動作検証も **ChatGPT 5.2** で実施されています。
- **ChatGPT 5.2** では自律的拡張（自律的に作業を進める振る舞い）が機能しますが、**ChatGPT 5.2 Codex** では自律拡張プロンプト類は想定動作になりません（作業確認のために中断が多いため）。このため **自律的機能拡張の実施には実質的に人手が必要**になります。
- 自律拡張を行う場合は、まず ChatGPT に `ai/prompts/itsm/itsm_usecase_enrichment.md` の実行を指示し、ユースケース追加（`scripts/itsm/gitlab/templates/*/docs/usecases/` と各 `usecase_guide.md.tpl` の更新）まで実施します。その後 `apps/*/data/default/prompt/system.md` などの「実行指示（system prompt）」を与えることで、以降は原則としてモデルが自律的に拡張を進める前提です。

## 1. 目的と対象（スコープ）

### 1.1 目的

- ITSM 運用に対して AI 有効化機能（AI-enabled functionality）をどのように組み込むかを、実装と検証で体感する
- DQ/IQ/OQ/PQ と証跡（evidence）の運用により「後から説明できる」状態を作る

### 1.2 対象（本リポジトリで管理するもの）

- IaC: Terraform による基盤（AWS 上の ECS 等）
- ITSM 構成サービス: Keycloak / Zulip / GitLab / n8n / Exastro ITA
- AIOps Agent（プロンプト/ポリシー/ワークフロー/運用手順）
- Workflow Manager（サービスリクエスト/カタログ同期のワークフロー）

### 1.3 非対象（外部前提・外部依存）

- AI モデルを稼働させるための API キー（OpenAI 互換 API Key 等）は本リポジトリでは提供しません（利用者側で用意）。

## OpenAI API Key の購入（課金有効化）と発行

OpenAI の API Key は「購入するもの」ではなく、**OpenAI Platform で課金（支払い方法/クレジット）を有効化したうえで発行する Secret Key** です。

1. OpenAI Platform（`platform.openai.com`）へログインする（未作成ならアカウント作成）。
2. Billing（課金）で支払い方法を設定する。
   - ChatGPT（`chatgpt.com`）のサブスク課金と、API（`platform.openai.com`）の課金は別管理です。
3. 必要に応じてクレジット購入（prepaid）または利用上限（budget）を設定する。
4. API Keys から **Secret Key を発行**し、安全な場所に保管する（作成後に再表示できない前提で扱う）。

本リポジトリでの設定方法（`terraform.apps.tfvars` の `OPENAI_MODEL_API_KEY` / SSM パラメータ運用など）は `docs/apps/README.md` を参照してください。

## 2. システム概要（System Description）

監査・説明用のシステム概要は次を正とします。

 - 全体像・境界・方針: `docs/itsm/itsm-platform.md`
- プロダクト概要（任意・説明用）: `docs/product-overview.md`

## 3. 成果物マップ（GAMP/CSA の読み替え）

本リポジトリ内の主要ドキュメント/資産を、CSV成果物として読み替えた対応表です。

| 成果物（読み替え） | 主目的 | 参照先 |
| --- | --- | --- |
| システム概要（System Description） | 全体像・境界の共有 | `docs/itsm/itsm-platform.md` / `apps/aiops_agent/docs/aiops_agent_design.md` |
| 要件（URS相当） | 期待値・制約・前提の明確化 | `apps/aiops_agent/docs/app_requirements.md` |
| 仕様（FS/DS相当） | 動作仕様・設計の明確化 | `apps/aiops_agent/docs/aiops_agent_specification.md` |
| 実装（参考） | 実装方針の共有 | `apps/aiops_agent/docs/aiops_agent_implementation.md` |
| 構築手順（Installation/Configuration） | 再現性ある環境構築 | `docs/setup-guide.md` / `docs/usage-guide.md` / `docs/itsm/README.md` |
| DQ（設計適格性確認） | 設計・構成の妥当性確認 | `apps/aiops_agent/docs/dq/dq.md` |
| IQ（据付適格性確認） | 環境が正しく構築されたことの確認 | `apps/aiops_agent/docs/iq/iq.md` |
| OQ（運用適格性確認） | 想定ユースケースでの動作確認 | `apps/aiops_agent/docs/oq/oq.md` / `apps/workflow_manager/docs/oq/oq.md` |
| PQ（性能適格性確認） | 性能・限界値の定義と検証 | `apps/aiops_agent/docs/pq/pq.md` |
| 運用手順（SOP/Runbook相当） | 定常運用・障害対応の明確化 | `apps/aiops_agent/docs/aiops_agent_usage.md` / `apps/aiops_agent/data/default/prompt/README.md` |
| 変更管理・監査ログ運用 | 変更の統制と証跡の一貫性 | `docs/change-management.md` |
| 証跡（evidence） | 実行結果の保全 | `evidence/` |

## 4. 構造と構成アイテム（GAMP® 5 第2版の説明用）

本リポジトリは、実体（現行のフォルダ構成）と、監査説明のための「レイヤ読み替え」を分けて扱います。

### 4.1 構造上の意図（重要）

#### `/oss` — OSS 製品レイヤ（推奨構造）

- 上流 OSS のソースのみを格納する
- バージョン固定し、直接改変しない
- OSS ごとにライセンスと出自を記録する
- **GAMP® 5 カテゴリ 4（設定可能な製品: Configured Product）**

※ 本リポジトリでは現時点で `/oss` は未配置です（必要に応じて導入）。

#### `/apps` — アプリケーション / デプロイレイヤ

- ECS にデプロイされる実行アプリケーション群を表す（`apps/*`）
- 上流 OSS（参照）/カスタム拡張/構成（設定）/コンテナ化を組み合わせる
- 変更管理上の **主要な構成アイテム（CI: Configuration Item）**

#### `root terraform + modules/stack/` — プラットフォームレイヤ（`/infra` 相当）

- Terraform により定義された AWS リソース（`main.tf` / `variables.tf` / `outputs.tf` / `modules/stack/`）
- ECS サービスは `apps/*` と 1:1 で対応することを目安にする
- **Configuration Specification（構成定義）**

#### `apps/*/docs/cs/` + `apps/aiops_agent/data/` — AI 有効化機能（AI-enabled Functionality）（`/ai` 相当）

- AI は **共有され、ガバナンスされた能力**として扱う
- プロンプトとツールは変更管理下の構成アイテムとして扱う
- 振る舞いは AIS で定義する

※ 本リポジトリでは AIS は `apps/*/docs/cs/ai_behavior_spec.md`、プロンプト/ポリシーは主に `apps/aiops_agent/data/` 配下で管理しています（`/ai` をトップレベルに切り出すのは必要に応じて導入）。

### 4.2 GAMP® 5 分類サマリ（目安）

| 領域 | 分類 | 注記 |
|---|---|---|
| `/oss/*` | Cat 4 | 設定可能な製品（上流 OSS / 本リポジトリでは未配置） |
| `apps/*/workflows` | 構成アイテム | 変更管理されたワークフロー定義（例: n8n） |
| `apps/*/data` | 構成アイテム | プロンプト/ポリシー/テンプレート等（環境依存の値は平文で置かない） |
| `apps/*/docs/cs` | 構成アイテム | AIS（AI Behavior Spec）等の仕様（説明・監査用） |
| `main.tf` + `variables.tf` + `outputs.tf` + `modules/stack/` | 構成アイテム | IaC 定義（`/infra` 相当） |

### 4.3 監査向けの重要ステートメント（説明用）

> 複数の OSS 製品を統合して ITSM プラットフォームを構成しています。  
> 各 OSS は「設定可能な製品（Configured Product）」として管理し、デプロイされるアプリケーションは変更管理下の構成アイテムとして扱います。  
> 基盤、アプリケーションの振る舞い、AI 有効化機能は、統一されたリスクベースのアシュアランスアプローチで統治します。

## 5. リスクベースの保証（CSA）と証跡

プロトタイプでも「後から説明できる」状態を作るため、最低限は以下を意識しています。

- **アクセス制御**: 認証（Keycloak）や権限設計を前提に、誰が何を実行できるかを分離する
- **証跡（audit trail / evidence）**: OQ/PQ 実行結果を `evidence/` に保存し、判断の根拠と紐付ける
- **変更管理**: 設定・ワークフロー・プロンプト変更を `docs/change-management.md` の手順で記録し、追跡可能にする

## 6. AI ガバナンス（NIST AI RMF を意識した整理）

- AI の「意図された振る舞い（Intended Behavior）」は AIS として定義し、変更管理下で維持します
  - 例: `apps/aiops_agent/docs/cs/ai_behavior_spec.md`、`apps/*/docs/cs/ai_behavior_spec.md`
- GxP に関連する出力は、人による監督（レビュー/承認）を前提にします

## 7. 進め方（CSV 最小フロー）

- 全体の導線: `docs/csv-minimal-flow.md`
- ドキュメントレイヤの説明: `docs/README.md`
- アプリ一覧と共通フォーマット: `apps/README.md`

## 8. 検証（DQ/IQ/OQ/PQ）と証跡

- 検証観点は `apps/aiops_agent/docs/{dq,iq,oq,pq}.md` を参照。
- OQ の実行手順と証跡（evidence）は `apps/aiops_agent/docs/oq/oq.md` を起点にし、`docs/change-management.md` の方針で保存する。

## 9. クイックスタート（環境構築）

- 環境構築ガイド: `docs/setup-guide.md`
- 環境の利用手順と SSO の流れ: `docs/usage-guide.md`
- ITSM セットアップ: `docs/itsm/README.md`

## 10. ディレクトリ構成（クイック参照）

- `main.tf` / `variables.tf` / `outputs.tf`: ルート Terraform
- `modules/stack/`: Terraform モジュール（VPC/RDS/SSM/ECS/WAF 等）
- `apps/`: アプリケーション（CSV ドキュメント、ワークフロー、データ（プロンプト/ポリシー等））
- `docs/`: 共通ドキュメント（セットアップ、運用、変更管理）
- `scripts/`: 運用補助スクリプト（pull/build/redeploy 等）
- `docker/`: ビルドコンテキスト
- `evidence/`: 検証証跡（環境により外部保存も併用）
- `images/`: ローカルイメージキャッシュ（git 管理外）

## 11. 参考情報・外部リンク

- AWS CLI SSO: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html
- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- VPC エンドポイント: https://docs.aws.amazon.com/vpc/latest/privatelink/
- ECR: https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html
- CloudFront OAC: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html
- Route53/ACM: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-configuring.html , https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html
