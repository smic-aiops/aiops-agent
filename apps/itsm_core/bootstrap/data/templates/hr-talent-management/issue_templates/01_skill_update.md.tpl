# スキル更新申請

## 申請内容
- realm: `{{REALM}}`
- person_key:
- skill_id:
- level:
- evidence（任意）:
- notes（任意）:

## 承認
- 承認者はコメントで `/approve` を投稿する（推奨）
- もしくはラベル `status:approved` を付与する

## 自動反映（n8n）
- 承認を検出すると、n8n が MR を作成して `ledger/skill_updates/` に追記します

## payload（任意）
自動起票の互換のため、必要なら HTML comment で payload を埋め込めます。

<!--HR_TALENT_SKILL_UPDATE_JSON:{"realm":"{{REALM}}","person_key":"","skill_id":"","level":""}-->

