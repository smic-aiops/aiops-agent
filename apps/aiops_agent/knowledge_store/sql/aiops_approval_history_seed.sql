-- Seed data for approval history and evaluation store.
-- Japanese-friendly descriptions; safe to re-run.

INSERT INTO aiops_approval_history (
  approval_history_id,
  context_id,
  approval_id,
  actor,
  decision,
  comment,
  job_plan
) VALUES (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '{"user_id":"ops_user_01","display_name":"運用オペレーター","roles":["ops"]}'::jsonb,
  'approved',
  'Sulu 再起動案のリスクと影響を確認後に承認。',
  '{"workflow_id":"wf.redeploy.sulu","summary":"Sulu 再起動","risk":"medium"}'::jsonb
) ON CONFLICT DO NOTHING;

INSERT INTO aiops_approval_history (
  approval_history_id,
  context_id,
  approval_id,
  actor,
  decision,
  comment,
  job_plan
) VALUES (
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
  'ffffffff-ffff-ffff-ffff-ffffffffffff',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '{"user_id":"ops_manager","display_name":"問題管理担当","roles":["problem_owner"]}'::jsonb,
  'denied',
  '再起動はロールバックが必要な変更に該当すると判断。後続手順を再検討。',
  '{"workflow_id":"wf.rollback.sulu","summary":"ロールバック","risk":"high"}'::jsonb
) ON CONFLICT DO NOTHING;

INSERT INTO aiops_candidate_evaluation (
  evaluation_id,
  context_id,
  job_id,
  candidate_ref,
  feedback_type,
  score,
  details,
  actor
) VALUES (
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  NULL,
  'wf.redeploy.sulu',
  'preview',
  4,
  '{"summary":"プレレビューでSulu再起動が候補1位","confidence":0.92}'::jsonb,
  '{"user_id":"ops_user_01","display_name":"運用オペレーター"}'::jsonb
) ON CONFLICT DO NOTHING;

INSERT INTO aiops_candidate_evaluation (
  evaluation_id,
  context_id,
  job_id,
  candidate_ref,
  feedback_type,
  score,
  details,
  actor
) VALUES (
  'bbbbbbbb-bbbb-4444-cccc-dddddddddddd',
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  '11111111-2222-3333-4444-555555555555',
  'wf.redeploy.sulu',
  'job_result',
  3,
  '{"outcome":"success","remarks":"再起動後に502減少"}'::jsonb,
  '{"user_id":"ops_user_01","display_name":"運用オペレーター"}'::jsonb
) ON CONFLICT DO NOTHING;
