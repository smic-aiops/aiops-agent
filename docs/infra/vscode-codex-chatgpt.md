# VS Code で Codex / ChatGPT を使う

このガイドは、`aiops-agent` を `Visual Studio Code` 上で安全に扱うための、**OpenAI 公式導線のみ**の個人向けセットアップ手順です。

- コーディング作業: `Codex` を VS Code で使う
- 要件整理・長文相談: `ChatGPT Web/Desktop` を併用する
- 認証: API キーではなく `ChatGPT` アカウントでサインインする

## 1. 前提

以下が利用できることを確認します。

- `Visual Studio Code`
- `Git`
- `Node.js`
- ターミナル
- `ChatGPT` へサインインできる OpenAI アカウント

確認コマンド例:

```bash
code --version
git --version
node --version
```

`code` コマンドが使えない場合は、VS Code の Command Palette から `Shell Command: Install 'code' command in PATH` を実行します。

## 2. 拡張の導入

OpenAI 公式の VS Code 拡張 `Codex – OpenAI's coding agent` を使います。

- Marketplace: <https://marketplace.visualstudio.com/items?itemName=openai.chatgpt>
- 参考ドキュメント: <https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan>
- IDE ガイド: <https://developers.openai.com/codex/ide>

GUI で導入する場合:

1. VS Code の Extensions を開く
2. `Codex` で検索する
3. `OpenAI` 提供の `Codex – OpenAI's coding agent` をインストールする

CLI で導入する場合:

```bash
code --install-extension openai.chatgpt
```

このリポジトリには [`.vscode/extensions.json`](/Volumes/Git%20Local/GitHub/aiops-agent/.vscode/extensions.json) を追加してあり、公式拡張を推奨表示します。

## 3. サインイン

1. VS Code で Codex パネルを開く
2. `Sign in with ChatGPT` を選ぶ
3. ブラウザで OpenAI にログインし、VS Code への接続を許可する

この構成では API キーを VS Code に保存しません。認証・利用枠は ChatGPT プランに従います。

## 4. このリポジトリでの使い分け

### Codex in VS Code に向く作業

- リポジトリ探索
- 小中規模のコード修正
- Terraform / shell / workflow JSON のレビュー補助
- 既存スクリプトの改善
- テストや検証コマンドの要約

### ChatGPT Web/Desktop に向く作業

- 実装前の要件整理
- 長文の設計相談
- 比較検討や文章作成
- 実装前の Plan 作成

## 5. 推奨ワークフロー

1. ChatGPT で要件・制約・成功条件を整理する
2. VS Code の Codex に、確定した実装タスクを渡す
3. 変更差分と実行結果を人間が確認する
4. 迷う設計判断は ChatGPT 側へ戻して再整理する

このリポジトリでは、**大きい設計変更は先に ChatGPT で整理し、具体的な実装は Codex で進める**運用を推奨します。

## 6. セキュリティ運用

このリポジトリでは、次を **AI 入力対象外** として扱います。

- `terraform.env.tfvars`
- `terraform.itsm.tfvars`
- `terraform.apps.tfvars`
- `terraform.tfvars`
- `.env` / `.env.*`
- 秘密鍵、証明書、トークン
- 顧客データ、個人情報、認証情報

運用ルール:

- 機微情報を含むファイルは開いた状態で AI へ渡さない
- 秘密値は `terraform output` や `SSM / Secrets Manager` で扱い、会話へ貼り付けない
- 差分レビュー時も秘密値が混ざっていないか人間が確認する

## 7. VS Code での操作範囲

タスク内容に応じて、Codex に許可する範囲を切り替えます。

- 読み取り中心: 調査、要約、レビュー
- 編集可: ドキュメント修正、実装補助
- コマンド実行可: `terraform validate`、`terraform fmt -check -recursive`、`git status` など
- テスト実行可: 既存の検証スクリプトや dry-run のみを必要最小限で実行

初期運用では、まず `読み取り中心` または `編集可` から始め、慣れてからコマンド実行範囲を広げるのが安全です。

## 8. 導入確認チェック

以下を順に確認します。

### セットアップ確認

- Codex 拡張が VS Code に表示される
- ChatGPT アカウントでサインインできる
- このリポジトリを開いた状態でファイル要約や検索が動く

### 実務確認

- 1 件の小さな修正依頼に対して、Codex が差分案を出せる
- 1 件のレビュー依頼に対して、Codex が懸念点を説明できる
- 1 件の検証コマンド結果を Codex が要約できる

### 運用確認

- `tfvars` や秘密値を AI へ渡さない運用が守れる
- 要件整理は ChatGPT、実装は Codex、という分担が無理なく回る

## 9. このリポジトリ向けの最初の使い方

最初の数回は、次のような依頼から始めると安全です。

- `README.md` や `docs/infra/README.md` の要約
- `terraform plan` 前提の確認項目の洗い出し
- `scripts/` 配下の dry-run 対応有無の確認
- 既存 shell script の quoting / `set -euo pipefail` 観点レビュー

反対に、最初から避けるべき依頼:

- `tfvars` の中身を貼って原因調査させる
- 秘密値を含む apply 後ログの丸投げ
- 本番変更をそのまま自動実行させる

## 10. 出典

- OpenAI Help: [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan)
- OpenAI Docs: [Codex IDE guide](https://developers.openai.com/codex/ide)
- Visual Studio Marketplace: [Codex – OpenAI's coding agent](https://marketplace.visualstudio.com/items?itemName=openai.chatgpt)
