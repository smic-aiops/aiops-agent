# ルールベース判断の逸脱点一覧（改善案付き）

方針: ルールはプロンプト内のポリシー/条件分岐に集約し、本文やコードの固定判断を減らす。

> 注記: 参照パスは旧構成のものを含みます（例：`custom_ai_agenet/*` → 現行は概ね `apps/aiops_agent/*`、`docs/aiops_custom_ai_agent_design.md` → `apps/aiops_agent/docs/aiops_agent_design.md`）。行番号は目安で、更新により変動します。

1. `custom_ai_agenet/prompt/adapter_classify_ja.txt:5`  共通ガードレールは `policy_context.rules.common`（no_fabrication / pii_handling / uncertainty_handling / output_format / url_policy）を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
2. `custom_ai_agenet/prompt/adapter_classify_ja.txt:6`  事実不足/不確実の扱いは `policy_context.rules.common.uncertainty_handling` と `policy_context.limits.adapter_classify.max_clarifying_questions` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
3. `custom_ai_agenet/prompt/adapter_classify_ja.txt:7`  破壊的・広範囲・権限逸脱の可能性がある場合は、`policy_context.rules.adapter_classify.safety_bias_rules` に従って安全側に倒す。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
4. `custom_ai_agenet/prompt/adapter_classify_ja.txt:10`  `form` は `policy_context.rules.adapter_classify.form_rules` を上から評価して決定する。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
5. `custom_ai_agenet/prompt/adapter_classify_ja.txt:11`  `category` は `policy_context.rules.adapter_classify.category_rules` を上から評価して決定する。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
6. `custom_ai_agenet/prompt/adapter_classify_ja.txt:12`  `impact`/`urgency`/`priority` の語彙と優先度マトリクスは `policy_context.taxonomy` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
7. `custom_ai_agenet/prompt/adapter_classify_ja.txt:13`  `priority` は `policy_context.rules.adapter_classify.priority_matrix_usage` に従い、`policy_context.taxonomy.priority_matrix` を評価する。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
8. `custom_ai_agenet/prompt/adapter_classify_ja.txt:14`  語彙や既定値が欠けている場合は、`policy_context.defaults.adapter_classify` を参照しつつ `policy_context.rules.common.uncertainty_handling` に従う。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
9. `custom_ai_agenet/prompt/context_summary_ja.txt:5`  共通ガードレールは `policy_context.rules.common`（pii_handling / uncertainty_handling / output_format）を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
10. `custom_ai_agenet/prompt/context_summary_ja.txt:6`  文数や含める観点は `policy_context.limits.context_summary` と `policy_context.rules.context_summary` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
11. `custom_ai_agenet/prompt/enrichment_plan_ja.txt:5`  あなたは計画（意思決定）と構造化出力のみを行う。実行はしない。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
12. `custom_ai_agenet/prompt/enrichment_plan_ja.txt:6`  共通ガードレールは `policy_context.rules.common`（no_fabrication / pii_handling / uncertainty_handling / output_format / url_policy）を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
13. `custom_ai_agenet/prompt/enrichment_plan_ja.txt:9`  目的の明確化、取得範囲、手段選択、失敗時の扱いは `policy_context.rules.enrichment_plan` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
14. `custom_ai_agenet/prompt/enrichment_plan_ja.txt:10`  チャット履歴/ログ/メトリクスの上限や既定値は `policy_context.limits.enrichment_plan` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
15. `custom_ai_agenet/prompt/feedback_decide_ja.txt:5`  共通ガードレールは `policy_context.rules.common`（uncertainty_handling / output_format）を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
16. `custom_ai_agenet/prompt/feedback_decide_ja.txt:6`  ルールベースの閾値をコード側に固定しない。判断基準は `policy_context.rules.feedback_decide` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
17. `custom_ai_agenet/prompt/feedback_decide_ja.txt:7`  `resolved=true/false` や `smile_score` とコメントは矛盾し得る。矛盾処理は `policy_context.rules.feedback_decide.conflict_resolution` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
18. `custom_ai_agenet/prompt/feedback_decide_ja.txt:10`  `case_status` の判定は `policy_context.rules.feedback_decide.case_status_rules` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
19. `custom_ai_agenet/prompt/feedback_decide_ja.txt:11`  `followups` の上限は `policy_context.limits.feedback_decide` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
20. `custom_ai_agenet/prompt/feedback_request_render_ja.txt:5`  共通ガードレールは `policy_context.rules.common`（pii_handling / url_policy / uncertainty_handling / output_format）を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
21. `custom_ai_agenet/prompt/feedback_request_render_ja.txt:6`  方式選択（ボタン/フォーム/テキストコマンド/自然文など）は `policy_context.rules.feedback_request_render` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
22. `custom_ai_agenet/prompt/feedback_request_render_ja.txt:7`  不確実な場合のフォールバックは `policy_context.fallbacks.feedback_request_render` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
23. `custom_ai_agenet/prompt/feedback_request_render_ja.txt:20`  `job_id` が無い場合の扱いは `policy_context.fallbacks.feedback_request_render` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
24. `custom_ai_agenet/prompt/feedback_request_render_ja.txt:21`  テキスト例は `policy_context.interaction_grammar.feedback.templates` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
25. `custom_ai_agenet/prompt/feedback_request_render_ja.txt:22`  score のレンジは `policy_context.interaction_grammar.feedback.smile_score_range` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
26. `custom_ai_agenet/prompt/initial_reply_ja.txt:5`  共通ガードレールは `policy_context.rules.common`（pii_handling / uncertainty_handling / output_format / url_policy）を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
27. `custom_ai_agenet/prompt/initial_reply_ja.txt:6`  機密情報の例外扱い（承認トークンや job_id の出力可否）は `policy_context.rules.common.pii_handling.allow_fields` を正とする（理由欄には書かない）。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
28. `custom_ai_agenet/prompt/initial_reply_ja.txt:7`  判断（どの文面を出すか、どの順番で情報を出すか、どの入力方式を案内するか）は `policy_context.rules.initial_reply` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
29. `custom_ai_agenet/prompt/initial_reply_ja.txt:34`  `job_plan.next_action` ごとの流れは `policy_context.rules.initial_reply.message_flow` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
30. `custom_ai_agenet/prompt/initial_reply_ja.txt:35`  承認案内の方式は `policy_context.rules.initial_reply.approval_guidance` と `context.source_capabilities` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
31. `custom_ai_agenet/prompt/initial_reply_ja.txt:36`  承認コマンドの例は `policy_context.interaction_grammar.approval.templates` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
32. `custom_ai_agenet/prompt/initial_reply_ja.txt:37`  `clarifying_questions` が空の場合の汎用質問は `policy_context.defaults.initial_reply.fallback_questions` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
33. `custom_ai_agenet/prompt/interaction_parse_ja.txt:5`  共通ガードレールは `policy_context.rules.common`（no_fabrication / pii_handling / uncertainty_handling / output_format / url_policy）を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
34. `custom_ai_agenet/prompt/interaction_parse_ja.txt:6`  不確実な場合の追加質問は `policy_context.limits.interaction_parse.max_clarifying_questions` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
35. `custom_ai_agenet/prompt/interaction_parse_ja.txt:9`  `event_kind` の判定順は `policy_context.rules.interaction_parse.event_kind_order` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
36. `custom_ai_agenet/prompt/interaction_parse_ja.txt:10`  `approval` 判定は `policy_context.rules.interaction_parse.approval` と `policy_context.interaction_grammar.approval` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
37. `custom_ai_agenet/prompt/interaction_parse_ja.txt:11`  `feedback` 判定は `policy_context.rules.interaction_parse.feedback` と `policy_context.interaction_grammar.feedback` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
38. `custom_ai_agenet/prompt/interaction_parse_ja.txt:12`  文法/テンプレ/語彙は `policy_context.interaction_grammar` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
39. `custom_ai_agenet/prompt/interaction_parse_ja.txt:13`  文法や語彙が不足している場合は `policy_context.defaults.interaction_parse` を参照しつつ `needs_clarification=true` とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
40. `custom_ai_agenet/prompt/interaction_parse_ja.txt:16`  `approval.decision` は `policy_context.interaction_grammar.approval.decisions` の語彙を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
41. `custom_ai_agenet/prompt/interaction_parse_ja.txt:17`  `approval.approval_token` は `policy_context.defaults.interaction_parse.approval_token_pattern`（またはルールに明記されたパターン）に一致するものだけを抽出する。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
42. `custom_ai_agenet/prompt/interaction_parse_ja.txt:18`  `feedback.job_id` は入力に含まれる識別子をそのまま返す（UUID かどうかの検証はコード側で行う）。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
43. `custom_ai_agenet/prompt/interaction_parse_ja.txt:19`  `feedback.smile_score` のレンジは `policy_context.interaction_grammar.feedback.smile_score_range` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
44. `custom_ai_agenet/prompt/interaction_parse_ja.txt:20`  `feedback.comment` は任意（機密/個人情報は伏字にしてよい）。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
45. `custom_ai_agenet/prompt/job_result_reply_ja.txt:5`  共通ガードレールは `policy_context.rules.common`（pii_handling / output_format）を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
46. `custom_ai_agenet/prompt/job_result_reply_ja.txt:6`  長い `result_payload`/`error_payload` は `policy_context.limits.job_result_reply.max_payload_chars` を上限として要約する。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
47. `custom_ai_agenet/prompt/job_result_reply_ja.txt:7`  再実行の扱いは `policy_context.rules.job_result_reply.retryable_handling` を正とし、**提案**のみに留める。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
48. `custom_ai_agenet/prompt/job_result_reply_ja.txt:8`  フィードバック依頼は入力の `feedback_request_text` を正とし、本文末尾に必ず付ける（入力に無い場合は `policy_context.fallbacks.job_result_reply` を正とする）。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
49. `custom_ai_agenet/prompt/job_result_reply_ja.txt:11`  成功時/失敗時の構成は `policy_context.rules.job_result_reply.success_flow` / `failure_flow` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
50. `custom_ai_agenet/prompt/jobs_preview_ja.txt:5`  あなたは「意思決定」と「構造化出力」のみを行う。実行はしない。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
51. `custom_ai_agenet/prompt/jobs_preview_ja.txt:6`  共通ガードレールは `policy_context.rules.common`（no_fabrication / pii_handling / uncertainty_handling / output_format / url_policy）を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
52. `custom_ai_agenet/prompt/jobs_preview_ja.txt:9`  承認ポリシーの事実データは `policy_context.approval_policy_doc` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
53. `custom_ai_agenet/prompt/jobs_preview_ja.txt:10`  `policy_context.approval_policy` をキーに `approval_policy_doc.policies[<key>]` を参照し、その内容に従って判断する。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
54. `custom_ai_agenet/prompt/jobs_preview_ja.txt:13`  `policy_context.rules.jobs_preview.decision_order` の順に評価し、最初に合致した行動を採用する。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
55. `custom_ai_agenet/prompt/jobs_preview_ja.txt:14`  `ask_clarification_conditions` / `require_approval_conditions` / `auto_enqueue_conditions` / `reject_conditions` は `policy_context.rules.jobs_preview` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
56. `custom_ai_agenet/prompt/jobs_preview_ja.txt:15`  `required_confirm` は `policy_context.rules.jobs_preview.required_confirm_by_next_action` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
57. `custom_ai_agenet/prompt/jobs_preview_ja.txt:16`  追加質問の上限は `policy_context.limits.jobs_preview.max_clarifying_questions` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
58. `custom_ai_agenet/prompt/jobs_preview_ja.txt:19`  `candidates` の上限は `policy_context.limits.jobs_preview.max_candidates` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
59. `custom_ai_agenet/prompt/jobs_preview_ja.txt:20`  `workflow_id` はカタログ整合を優先し、候補（automation_hint 等）がある場合も必ずカタログ整合を意識する。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
60. `custom_ai_agenet/prompt/jobs_preview_ja.txt:21`  `params` は実行に必要な最小セットを埋める。曖昧な値は埋めず、`missing_params` と `clarifying_questions` で回収する。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
61. `custom_ai_agenet/prompt/jobs_preview_ja.txt:22`  `missing_params` の上限は `policy_context.limits.jobs_preview.max_missing_params` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
62. `custom_ai_agenet/prompt/jobs_preview_ja.txt:25`  `risk_level`/`impact_scope` の語彙は `policy_context.taxonomy` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
63. `custom_ai_agenet/prompt/jobs_preview_ja.txt:26`  既定値が必要な場合は `policy_context.defaults.jobs_preview` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
64. `custom_ai_agenet/prompt/rag_router_ja.txt:5`  `policy_context.taxonomy.rag_mode_vocab` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
65. `custom_ai_agenet/prompt/rag_router_ja.txt:8`  共通ガードレールは `policy_context.rules.common`（no_fabrication / pii_handling / uncertainty_handling / output_format / url_policy）を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
66. `custom_ai_agenet/prompt/rag_router_ja.txt:9`  ルーティング条件は `policy_context.rules.rag_router.selection_rules` を上から評価して決める。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
67. `custom_ai_agenet/prompt/rag_router_ja.txt:10`  迷う/曖昧な場合の扱いは `policy_context.rules.rag_router.ambiguity_handling` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
68. `custom_ai_agenet/prompt/rag_router_ja.txt:11`  追加質問の上限は `policy_context.limits.rag_router.max_clarifying_questions` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
69. `custom_ai_agenet/prompt/rag_router_ja.txt:14`  `policy_context.rules.rag_router.query_rules` に従い、検索に効く短い日本語フレーズを作る。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
70. `custom_ai_agenet/prompt/rag_router_ja.txt:15`  `filters` は分かる範囲で埋め、分からない値は `null` にする（無理に埋めない）。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
71. `custom_ai_agenet/prompt/rag_router_ja.txt:16`  `top_k` の既定値/上限は `policy_context.limits.rag_router` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
72. `custom_ai_agenet/prompt/routing_decide_ja.txt:5`  共通ガードレールは `policy_context.rules.common`（no_fabrication / pii_handling / uncertainty_handling / output_format / url_policy）を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
73. `custom_ai_agenet/prompt/routing_decide_ja.txt:6`  事実が不足している場合や迷う場合は `policy_context.limits.routing_decide.max_clarifying_questions` と `policy_context.rules.common.uncertainty_handling` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
74. `custom_ai_agenet/prompt/routing_decide_ja.txt:7`  返信先が未確定のまま処理を止めない。候補がある場合は `policy_context.rules.routing_decide` に従い安全側を選ぶ。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
75. `custom_ai_agenet/prompt/routing_decide_ja.txt:8`  選定ロジック（優先順位/フォールバック/エスカレーション判断）は `policy_context.rules.routing_decide` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
76. `custom_ai_agenet/prompt/routing_decide_ja.txt:9`  候補が 0 件の場合の扱いは `policy_context.fallbacks.routing_decide` を正とする。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
77. `custom_ai_agenet/prompt/routing_decide_ja.txt:12`  `routing_candidates`: エスカレーション表から抽出された候補行の配列。各行には `policy_id`、`service_name/ci_name`、`escalation_level`、`reply_target`、`notify_targets`、SLA などが含まれる。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
78. `custom_ai_agenet/prompt/routing_decide_ja.txt:13`  `context_age_minutes`: このケース（context）の経過時間（分）。SLA/エスカレーションの判断に使う。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
79. `custom_ai_agenet/prompt/routing_decide_ja.txt:16`  `policy_context.rules.routing_decide.match_order`、`escalation_rules`、`urgent_rules`、`reply_target_policy` を順に適用する。
   改善案: ルール/例外/上限は `policy_context.rules.*` + `policy_context.limits/defaults/fallbacks` に移し、本文は参照のみにする。
80. `docs/aiops_custom_ai_agent_design.md:15`  1. 短時間で応答し、実行処理をリコメンドし、`jobs.Preview` の出力 `next_action`（語彙は `policy_context.taxonomy.next_action_vocab` を正とする）に従って後続処理（自動投入/承認提示/追加質問/拒否）を行う
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
81. `docs/aiops_custom_ai_agent_design.md:21`  複数のソース（CloudWatch、Zulip/Slack/Mattermost など）を共通フローで扱える（正規化・冪等化・承認・通知）
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
82. `docs/aiops_custom_ai_agent_design.md:22`  実行前承認と権限チェックにより、誤実行/権限逸脱を防ぐ
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
83. `docs/aiops_custom_ai_agent_design.md:23`  `trace_id`/`context_id`/`approval_id`/`job_id` により、監査・トラブルシュート可能なトレーサビリティを確保する
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
84. `docs/aiops_custom_ai_agent_design.md:29`  CloudWatch からのイベント通知やチャットプラットフォームからのイベント受信（Webhook / Bot / Event API）
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
85. `docs/aiops_custom_ai_agent_design.md:30`  アダプターによるイベント正規化・認証検証・冪等化・周辺情報収集
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
86. `docs/aiops_custom_ai_agent_design.md:31`  LLM による意図解析（intent/params）およびツール呼び出し（ジョブ実行）
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
87. `docs/aiops_custom_ai_agent_design.md:32`  AI Ops ジョブ実行エンジン Queue Mode によるジョブ実行（`job_id`/内部実行IDの追跡）
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
88. `docs/aiops_custom_ai_agent_design.md:33`  AI Ops ジョブ実行エンジン → アダプターへの完了通知（Webhook）とチャット返信投稿
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
89. `docs/aiops_custom_ai_agent_design.md:34`  Zulip 受信口（Outgoing Webhook）は `POST /ingest/zulip` に集約する（推奨）。tenant/realm 分岐は URL 末尾パスでは行わず、受信 `token`（`N8N_ZULIP_OUTGOING_TOKEN/YAML`）または payload/params の `tenant/realm` により解決する。承認レスポンスや評価も同じ口で処理する（イベント種別はプロンプトのポリシー＋条件分岐により `event_kind` を JSON 出力させ、語彙は `policy_context.taxonomy.event_kind_vocab` を正とする。コードは署名/冪等性/スキーマ検証、承認トークンの形式/TTL/ワンタイム性検証などのハード制約に限定する）。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
90. `docs/aiops_custom_ai_agent_design.md:35`  Bot が複数/マルチテナントになる場合の Webhook 配置（単一 n8n に集約するか、レルム単位で n8n を分割するか等）は `deployment_mode` 等の設定値として定義し、本文に「必要/奨励」の判断を書かない。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
91. `docs/aiops_custom_ai_agent_design.md:39`  各ワークフローの業務ロジック詳細（AI Ops ジョブ実行エンジンの個別フロー設計）
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
92. `docs/aiops_custom_ai_agent_design.md:40`  チャット UI のカスタム表示（Block Kit 等の詳細設計）
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
93. `docs/aiops_custom_ai_agent_design.md:44`  **チャットプラットフォーム**：Zulip/Slack/Mattermost 等を想定したイベント発生源
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
94. `docs/aiops_custom_ai_agent_design.md:45`  **ソース**：イベント発生源（例：Zulip/Slack/CloudWatch）。送信主体（sender）と発言者/actor を区別し、NormalizedEvent に両方の情報を保持できる設計とします。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
95. `docs/aiops_custom_ai_agent_design.md:46`  **問合せ者**：チャット上で依頼/問い合わせを行うユーザー（ソース側の actor）
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
96. `docs/aiops_custom_ai_agent_design.md:47`  **アダプター**：受信口。検証・正規化・冪等化・周辺情報収集・承認提示・ジョブ投入・コンテキスト保持・返信投稿を担う
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
97. `docs/aiops_custom_ai_agent_design.md:48`  **オーケストレーター**：意図解析し、承認要否を判定し、AI Ops ジョブ実行エンジンのツール（ワークフロー）を呼び出す実行主体
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
98. `docs/aiops_custom_ai_agent_design.md:49`  **AI Ops ジョブ実行エンジン**：ツール棚（組織/ロール単位で公開されるワークフロー群）を提供し、Queue Mode で非同期実行する基盤
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
99. `docs/aiops_custom_ai_agent_design.md:50`  **ワークフロー**：実務担当が定義・公開する自動化手順（例：ログ収集、チケット起票、再起動、設定変更、診断等）
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
100. `docs/aiops_custom_ai_agent_design.md:51`  **ワークフローカタログ**：ワークフローのメタデータを提供する参照情報
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
101. `docs/aiops_custom_ai_agent_design.md:52`  例：`workflow_id`, `required_roles`, `required_groups`, `risk_level`, `impact_scope`, `required_confirm`
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
102. `docs/aiops_custom_ai_agent_design.md:53`  **ツール呼び出し（ジョブ実行）**：オーケストレーターが外部ツール（ジョブ実行エンジン等）を呼び出すためのインターフェース（本書では `jobs.Preview`, `jobs.enqueue` を含む）
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
103. `docs/aiops_custom_ai_agent_design.md:54`  **正規化イベント（NormalizedEvent）**：ソースイベントを共通スキーマに変換したもの。分類（定型/定形外、種別）、優先度、抽出パラメータ、周辺情報参照などを含む
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
104. `docs/aiops_custom_ai_agent_design.md:55`  **イベントコンテキスト**：返信先に必要な情報（workspace/channel/thread/user 等）
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
105. `docs/aiops_custom_ai_agent_design.md:56`  **コンテキストストア**：`context_id`/`job_id` を起点に返信先・正規化イベント・保留中承認・ジョブ実行状態を保存し、TTL/保持期間を管理する DB/Redis 層（本プロトタイプは n8n の Postgres インスタンスに `aiops_*` テーブルを同居）
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
106. `docs/aiops_custom_ai_agent_design.md:57`  **承認履歴/評価ストア**：過去の承認結果やユーザー評価を蓄積し、オーケストレーターの意思決定に参照するストア
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
107. `docs/aiops_custom_ai_agent_design.md:58`  **実行計画（job_plan）**：`jobs.Preview` で組み立てる `{workflow_id, params, summary, required_roles, risk_level, impact_scope}`。複数候補（ランキング）を返すことがある
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
108. `docs/aiops_custom_ai_agent_design.md:59`  **保留中承認（PendingApproval）**：実行前承認の記録。`approval_id`, `expires_at`, `token_nonce`, `approved_at`, `used_at` 等を持つ。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
109. `docs/aiops_custom_ai_agent_design.md:61`  **承認トークン（approval_token）**：`workflow_id + params + actor + expiry + token_nonce` 等を署名して埋め込んだ短 TTL のワンタイムトークン。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
110. `docs/aiops_custom_ai_agent_design.md:63`  **event_kind**：受信イベントの種別（プロンプトで推定する）。語彙は `policy_context.taxonomy.event_kind_vocab` を正とする（本文の列挙は例）。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
111. `docs/aiops_custom_ai_agent_design.md:64`  **next_action**：`jobs.Preview` の意思決定出力（プロンプト内ポリシーの結論）。語彙は `policy_context.taxonomy.next_action_vocab` を正とする（本文の列挙は例）。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
112. `docs/aiops_custom_ai_agent_design.md:65`  **required_confirm**：後方互換のフラグ（`next_action` を正とし、語彙や扱いは `custom_ai_agenet/prompt/jobs_preview_ja.txt` のポリシーに従う）。本文では `required_confirm` の意味論を固定しない。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
113. `docs/aiops_custom_ai_agent_design.md:66`  **Impact / Urgency**：優先度推定の軸。分類プロンプトのポリシー（優先度マトリクス）で `impact`/`urgency` を推定し、`priority` を決定する
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
114. `docs/aiops_custom_ai_agent_design.md:67`  **エスカレーション表**：分類・優先度・対象システム等に基づき、返信先/担当/エスカレーション先を決める対応表（DB 参照を想定）
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
115. `docs/aiops_custom_ai_agent_design.md:68`  **trace_id**：アダプター→オーケストレーター→AI Ops ジョブ実行エンジン→Callback→投稿まで伝搬する相関 ID
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
116. `docs/aiops_custom_ai_agent_design.md:70`  
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
117. `docs/aiops_custom_ai_agent_design.md:78`  これは LLM に委ねず、コード/DB で強制する（安全のための最小限）。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
118. `docs/aiops_custom_ai_agent_design.md:80`  これは意思決定ではなく運用要件の固定値であり、環境変数/terraform 変数/設定値として管理する。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
119. `docs/aiops_custom_ai_agent_design.md:82`  これはプロンプト本文と `policy_context`（ポリシー JSON）を正とし、コード側で追加の IF/閾値/例外を増やさない。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
120. `docs/aiops_custom_ai_agent_design.md:84`  意思決定ポリシーに関する数値/語彙/上限/条件分岐/フォールバック（例：最大件数、閾値、`priority` 語彙、選定順序、無効出力時の扱い等）は、プロンプト本文に直書きせず **ポリシー JSON としてデータ化**し、`policy_context`（`rules`/`defaults`/`fallbacks`）経由でプロンプトへ渡します。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
121. `docs/aiops_custom_ai_agent_design.md:87`  `rules`: 条件分岐の順序・選定ルール・判定ロジック
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
122. `docs/aiops_custom_ai_agent_design.md:88`  `defaults`: 語彙・既定値・テンプレート
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
123. `docs/aiops_custom_ai_agent_design.md:89`  `fallbacks`: モデル出力無効時の挙動/理由/テンプレート
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
124. `docs/aiops_custom_ai_agent_design.md:90`  共通ガードレール（PII/出力形式/不確実性/URL方針など）は `policy_context.rules.common` を正とする
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
125. `docs/aiops_custom_ai_agent_design.md:94`  承認ポリシー（事実データ）：`custom_ai_agenet/policy/approval_policy_ja.json`
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
126. `docs/aiops_custom_ai_agent_design.md:95`  意思決定ポリシー（上限/語彙/既定値/条件分岐/フォールバックなど）：`custom_ai_agenet/policy/decision_policy_ja.json`
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
127. `docs/aiops_custom_ai_agent_design.md:96`  ソース別の入力制約（facts）：`custom_ai_agenet/policy/source_capabilities_ja.json`
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
128. `docs/aiops_custom_ai_agent_design.md:102`  アダプターは、ソースからのイベントを受けて「正規化 → プレビュー → `next_action` によるディスパッチ（承認提示/追加質問/拒否/自動投入） → ジョブ投入 → 結果通知 → 評価」を一貫して扱います。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
129. `docs/aiops_custom_ai_agent_design.md:106`  **認証/検証**：ソース別に検証方式を分ける。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
130. `docs/aiops_custom_ai_agent_design.md:107`  Slack：署名検証（HMAC）
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
131. `docs/aiops_custom_ai_agent_design.md:108`  Zulip：payload token（共有シークレット）
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
132. `docs/aiops_custom_ai_agent_design.md:109`  **IdP 参照（将来/任意）**：IdP に接続し `realm/group/role` 等を取得できること（未実装の場合は、ソース側の actor 情報を暫定の IAM コンテキストとして扱う）。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
133. `docs/aiops_custom_ai_agent_design.md:110`  **冪等化**：`dedupe_key` は `ingest_policy` の `dedupe_key_template` を正とし、重複受信を検出して二重処理を防止する（本文の式は例）。Zulip の承認/評価メッセージも同一ポリシーに従う。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
134. `docs/aiops_custom_ai_agent_design.md:111`  **周辺情報収集のトリガー**：検知/受付したイベントに対して、ソースや対象システムへ周辺情報照会を行う（次項）。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
135. `docs/aiops_custom_ai_agent_design.md:112`  **出力**：受信イベントの raw payload、actor、reply_target（返信先の事実データ）、`context_id`。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
136. `docs/aiops_custom_ai_agent_design.md:116`  **問い合わせ（チャット起点）**：収集ルーティング（どの情報を、どの手段で、どこまで取るか）は `enrichment_plan` プロンプトが `policy_context.rules.enrichment_plan` を評価して決める。コードは **計画どおりにツール実行**し、結果（本文/要約/参照）を保存する（Zulip REST / ワークフロー API / 公式 API の優先度をコードに固定しない）。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
137. `docs/aiops_custom_ai_agent_design.md:117`  **システム通知（監視起点）**：対象システムを特定し、関連ログ/メトリクス/アラート詳細などを収集する（例：CloudWatch Logs、外部監視、APM 等）。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
138. `docs/aiops_custom_ai_agent_design.md:118`  **出力**：収集結果（本文そのもの/要約/参照 URL/オブジェクトキー等）を NormalizedEvent に紐付けて扱えること。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
139. `docs/aiops_custom_ai_agent_design.md:122`  **共通スキーマ化**：イベントを NormalizedEvent に変換し、保存する。
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
140. `docs/aiops_custom_ai_agent_design.md:123`  **記録・分類**
   改善案: 本文の語彙/閾値/判断は `policy_context`/`ingest_policy`/`interaction_grammar` 参照へ置換し、例示は「例」と明示する。
