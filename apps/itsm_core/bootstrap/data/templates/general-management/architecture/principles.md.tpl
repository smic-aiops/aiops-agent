# アーキテクチャ原則

## 原則（例）
1. 変更・承認・証跡は GitLab Issue/MR に寄せる
2. 秘密情報は SSM/Secrets Manager に置き、Git に平文を入れない
3. realm 分離を前提にし、共有はテンプレと自動化で行う

