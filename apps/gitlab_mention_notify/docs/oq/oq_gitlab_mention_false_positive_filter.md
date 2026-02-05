# OQ: GitLab Mention Notify - メンション抽出の誤検出防止

## 対象

- アプリ: `apps/gitlab_mention_notify`
- ワークフロー: `apps/gitlab_mention_notify/workflows/gitlab_mention_notify.json`
- 参照: `apps/gitlab_mention_notify/data/mention_exclude_words.txt`（運用上の除外語）

## 受け入れ基準

- コードブロック/インラインコード内の `@` はメンションとして扱わない
- メールアドレス/URL の一部はメンションとして扱わない
- `@group/subgroup` 形式はメンションとして扱わない
- 除外語（`all,group,here,channel,everyone` など）はメンションとして扱わない

## テストケース

### TC-01: コードブロック/インラインコードは除外

- 入力例:
  - ```\ncode @someone\n```
  - `` `@someone` ``
- 期待: `@someone` が `mentions` に含まれない

### TC-02: メールアドレス/URL は除外

- 入力例:
  - `foo@bar.com`
  - `https://example.com/@someone`
- 期待: `@someone` が `mentions` に含まれない

### TC-03: @group/subgroup 形式は除外

- 入力例: `@group/subgroup`
- 期待: `@group` が `mentions` に含まれない

### TC-04: 除外語は除外

- 入力例: `@all @group @here @channel @everyone`
- 期待: `mentions=[]`

## 証跡（evidence）

- dry-run（`GITLAB_MENTION_NOTIFY_DRY_RUN=true`）時の応答（`mentions`, `unmapped`, `results`）

