# Prompts

## Active
- aiops_chat_core_ja.txt (統合Chatノード / adapter.interaction_parse.v1)
- adapter_classify_ja.txt
- context_summary_ja.txt
- routing_decide_ja.txt
- rag_router_ja.txt
- jobs_preview_ja.txt
- initial_reply_ja.txt
- feedback_decide_ja.txt
- feedback_request_render_ja.txt
- job_result_reply_ja.txt

## Reserved (not wired)
- enrichment_plan_ja.txt

## Legacy (reference only)
- interaction_parse_ja.txt

上記 Legacy は統合Chatノード導入前の参照用で、現行フローでは使用しません。
Active/Reserved は `apps/aiops_agent/scripts/deploy_workflows.sh` の prompt_map を正とします。
