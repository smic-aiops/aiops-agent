# ITIL4 ユースケース拡張（ITSM / GitLab テンプレート）

## 目的
`scripts/itsm/gitlab/templates/*/docs/usecases/` にある ITIL4 プラクティスグループ（General / Service / Technical）のユースケース集を読み込み、
現状に未記載で、かつ **バリューストリームとして評価が高い ITSM ユースケース**を各カテゴリ（3カテゴリ）につき 1 件ずつ特定して追加する。

## 入力（必読）
- 既存ユースケース（テンプレート）:
  - `scripts/itsm/gitlab/templates/general-management/docs/usecases/`
  - `scripts/itsm/gitlab/templates/service-management/docs/usecases/`
  - `scripts/itsm/gitlab/templates/technical-management/docs/usecases/`
- 各ディレクトリの `usecase_guide.md.tpl`（既存の番号体系と目次の更新規約があるため）

## 成果物（変更対象）
各カテゴリにつき 1 件、合計 3 件のユースケースを追加する。

- General management practices: `scripts/itsm/gitlab/templates/general-management/docs/usecases/` に 1 ファイル追加
- Service management practices: `scripts/itsm/gitlab/templates/service-management/docs/usecases/` に 1 ファイル追加
- Technical management practices: `scripts/itsm/gitlab/templates/technical-management/docs/usecases/` に 1 ファイル追加

加えて、各カテゴリの `usecase_guide.md.tpl` の目次へ追加し、リンクを通す。

## 進め方（手順）
1) 既存ユースケースをすべて読み、各カテゴリで扱っているテーマ（番号・タイトル・対象者・イベント起点・成果）を要約する。
2) 各カテゴリについて、既存にない（重複しない）候補ユースケースを 3〜5 件、インターネット上の信頼できる情報源を検索して抽出する。
   - ITIL4 公式（AXELOS / PeopleCert）や、業界で広く参照される ITSM 解説、実務事例、カンファレンス資料、主要ベンダーのベストプラクティスを優先する。
3) 各カテゴリごとに **1 件**に絞り込む（選定理由を明示）。
   - 判断軸（例）: 「発生頻度」「顧客価値/ビジネス価値」「自動化しやすさ」「他プロセスへの波及」「メトリクスで管理できる」「監査観点で説明しやすい」。
4) ユースケースを追加する。
   - 既存ファイルの文体（人物ドラマ形式、共通世界観、合言葉など）に合わせる。
   - 具体的な価値の流れ（トリガー → 判断 → 作業 → 連携 → 完了条件）を明確に書く。
   - GitLab Issue と Zulip 通知、必要に応じて n8n / Grafana 連携が自然に登場する形にする。
5) `usecase_guide.md.tpl` を更新し、追加ユースケースへのリンクを入れる。

## 制約・注意
- 既存ユースケースとの重複を避ける（同じテーマを言い換えただけの追加は禁止）。
- 追加は **各カテゴリ 1 件のみ**（合計 3 件）。
- 参照した情報源は、追加ユースケース末尾に「参考（Sources）」として列挙する。
  - URL と参照日（YYYY-MM-DD）を併記する。
  - 文章の丸写しはせず、要点を自分の言葉で要約する（引用が必要な場合も短く）。
- 機微情報（トークン、URL、アカウント等）や、社内固有の秘密前提は書かない。

## 出力フォーマット（推奨）
追加した各ユースケース末尾に、次の章を追加する。

- ねらい（このユースケースが「価値が高い」理由）
- 価値指標（測る KPI 例）
- 参考（Sources: URL + 参照日）

