# 全Apps IQ/OQ/PQ

## 対象と正

`scripts/validation/apps_iq_oq_pq_manifest.tsv` に、workflowを持つ全Apps/サブAppsとOQ runnerを明示する。新しいAppを追加してmanifestを更新しない場合、IQは discovery 差分で失敗する。

## 今回是正した重要事項

| # | 是正前の問題 | 是正内容 |
|---:|---|---|
| 1 | workflow Appの全件一覧がなく、検証漏れを検出できない | 27 Appをmanifestで明示し、discovery差分をIQでfailさせる |
| 2 | HR Talent ManagementのIQ文書がない | IQ目的・合格基準・実行方法を追加 |
| 3 | HR Talent ManagementのPQ文書がない | 定量的PQ基準を追加 |
| 4 | Practice Review SyncのIQ文書がない | IQ文書を追加 |
| 5 | Practice Review SyncのOQ文書がない | 空応答/HTTPエラーを許容しないOQ基準を追加 |
| 6 | Practice Review SyncのPQ文書がない | 定量的PQ基準を追加 |
| 7 | SLA Metrics SyncのIQ文書がない | SoR依存を含むIQ文書を追加 |
| 8 | SLA Metrics SyncのPQ文書がない | DB PQを含むPQ文書を追加 |
| 9 | 27 App中、直接実行可能なIQ入口が3 Appだけ | 全App共通IQ runnerとsuite別wrapperを追加 |
| 10 | 全Appに実行可能なPQ runnerがない | 全App共通PQ runnerとsuite別wrapperを追加 |
| 11 | JSON parseだけでは壊れたnode接続を検出できない | node名一意性とconnection参照整合性をIQに追加 |
| 12 | OQ runnerがハングした場合の終了条件がない | 30〜3600秒のrunner timeoutを追加 |
| 13 | OQ証跡の保存形式・場所がAppごとに不統一 | App別log、runner evidence、TSV、JSON summaryへ統一 |
| 14 | ローカル定義がn8nへ反映・activeかをIQで確認しない | `--execute` IQで全本番workflowの存在・activeを検証 |
| 15 | dry-runと実環境試験の境界が曖昧 | 既定をdry-runとし、外部試験は明示的な`--execute`のみに限定 |
| 16 | 共通OQ wrapperを重複実行し、同じ副作用を複数回発生させる | runner単位で一度だけ実行し、共有証跡を`COVERED`として記録 |
| 17 | PQ文書に数値の合格基準がないものがある | 20回解析5秒、2 MiB/件、n8n API 5秒を共通基準化 |
| 18 | API keyが証跡へ混入するリスク | token値を引数・log・summaryへ出さずterraform outputからメモリ上で解決 |
| 19 | 人手でログを読まないと全体結果が分からない | `summary.json`にPASS/COVERED/FAIL件数を出力 |
| 20 | macOS標準Bash/BSDツールでrunner自体が動かない | Bash 3.2互換の配列・大文字変換・パス処理へ修正 |
| 21 | Zulip受信経路で先行Ackと最終返信の2つのWebhook応答が直列実行され、最終返信が破棄される | 先行Ackを削除し、本文を返さない先行`Respond to Webhook`をIQで禁止、Zulip実返信をOQで確認 |
| 22 | Zulipの10秒timeout後の再送が重複排除され、空本文となるため返信が失われる | 重複イベントは副作用を再実行せず、受信済みの安全な確認本文を返す |
| 23 | OQ-11/12が旧slow経路だけを参照し、現行fast応答をnullと誤判定する | fast/slow両経路からfactsを抽出し、fast経路にも曖昧依頼の確認質問を実装 |
| 24 | fast応答が一般的なAPI案内へ固定され、品質OQ-15〜19を満たさない | 不確実性、承認、デプロイ手順、機密情報、SLO説明の安全な応答規則を実装 |
| 25 | fast意図判定に同一トピック履歴が混入し、過去返信の語を現在依頼と誤認する | `normalized_event.original_text`を分類対象の正とし、履歴は会話参照に限定 |
| 26 | OQ streamを無条件fast扱いし、Web検索などの遅延処理がdefer経路へ到達しない | 現在発言から遅延対象を先に判定し、即時defer応答後にslow処理・Messenger通知へ継続 |

## 共通合格基準

### IQ

- README、IQ/OQ/PQ文書、workflow directory、OQ runnerが存在する。
- 全workflow JSONのname/nodes/connections、node名の一意性、connection参照が正しい。
- 最終本文を横取りする`response_not_required`専用の先行`Respond to Webhook` nodeが存在しない。
- 全shell scriptが実行可能で `bash -n` に合格する。
- OQ runnerは `--help` と `--dry-run` を提供し、タイムアウト内に終了する。
- `--execute` 時は全本番workflowが対象realmのn8nに存在しactiveである。

### OQ

- 既存の各App OQ runnerを実行し、終了コード0かつ非空ログを必須とする。
- 共通runnerを利用するAIOpsコンポーネントは一度だけ実行し、他コンポーネントへ同一証跡を割り当てる。
- runnerごとに最大実行時間を設定し、ハングを合格扱いしない。

### PQ

- App単位で全workflow JSONを20回解析し5秒以内、workflow 1件2 MiB以下とする。
- `--execute` 時はAppの代表本番workflowをn8n APIで検索し、HTTP 200、active、5秒以内を必須とする。
- ITSM SoRは追加でDB機能OQ/PQを実行し、検索200回が規定時間内であることを確認する。

## 実行

```bash
# 外部変更を行わない事前確認
scripts/validation/run_all_apps_iq_oq_pq.sh --phase all --dry-run

# 実環境の全IQ/OQ/PQ
scripts/validation/run_all_apps_iq_oq_pq.sh \
  --phase all --execute --realm aiops \
  --evidence-dir evidence/validation/apps-iq-oq-pq/$(date -u +%Y%m%dT%H%M%SZ)
```

証跡は `results.tsv`、`summary.json`、`logs/`、各runner固有証跡に分け、トークン値は保存しない。
