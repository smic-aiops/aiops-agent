-- Seed data for ITSM-aligned problem management tables.
-- Safe to re-run; uses ON CONFLICT DO NOTHING.

INSERT INTO itsm_problem (
  problem_id,
  problem_number,
  title,
  description,
  status,
  category,
  subcategory,
  priority,
  impact,
  urgency,
  service_name,
  ci_ref,
  reported_at,
  detected_at,
  last_occurrence_at,
  owner_group,
  owner_user,
  root_cause,
  resolution,
  workaround_summary,
  source,
  external_refs,
  created_at,
  updated_at
) VALUES (
  '11111111-1111-1111-1111-111111111111',
  'PRB-0001',
  'Sulu サービス再起動ループ',
  'ECS タスクでメモリスパイク後に再起動が繰り返し発生。',
  'known_error',
  'application',
  'memory',
  'p1',
  'high',
  'high',
  'sulu',
  'ecs/sulu',
  NOW() - interval '2 days',
  NOW() - interval '2 days',
  NOW() - interval '1 day',
  '運用チーム',
  '当番',
  'キャッシュクリーンアップ処理でメモリリークが発生。',
  NULL,
  'Sulu サービスを再デプロイしてメモリを解放し、タスクを安定化する。',
  'cloudwatch',
  '{"alarm":"SuluHighMemory","runbook":"https://runbook.example/sulu"}'::jsonb,
  NOW(),
  NOW()
) ON CONFLICT (problem_id) DO NOTHING;

INSERT INTO itsm_workaround (
  workaround_id,
  title,
  steps,
  validation_steps,
  rollback_steps,
  risk_level,
  estimated_minutes,
  requires_confirm,
  automation_hint,
  created_at,
  updated_at
) VALUES (
  '22222222-2222-2222-2222-222222222222',
  'Sulu サービス再デプロイ',
  '1. 影響のある時間帯を確認する。 2. 強制再デプロイを実行する。 3. ログとメトリクスを監視する。',
  '/health が 200 を返し、エラー率が閾値以下であることを確認する。',
  '問題が解消しない場合は、直前のタスク定義リビジョンへロールバックする。',
  'medium',
  15,
  true,
  '{"workflow_id":"wf.redeploy.sulu","params":{"service":"sulu"},"summary":"Sulu サービスを再デプロイ"}'::jsonb,
  NOW(),
  NOW()
) ON CONFLICT (workaround_id) DO NOTHING;

INSERT INTO itsm_known_error (
  known_error_id,
  known_error_number,
  problem_id,
  workaround_id,
  status,
  title,
  symptoms,
  cause,
  resolution,
  service_name,
  ci_ref,
  risk_level,
  owner_group,
  owner_user,
  published_at,
  tags,
  created_at,
  updated_at
) VALUES (
  '33333333-3333-3333-3333-333333333333',
  'KE-0001',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  'published',
  '長時間アップロード後の Sulu メモリリーク',
  'メモリ使用量が継続的に増加し、タスクが再起動、ピーク時に 502 が発生する。',
  '長時間アップロード時にキャッシュクリーンアップが実行されない。',
  NULL,
  'sulu',
  'ecs/sulu',
  'high',
  '運用チーム',
  '当番',
  NOW() - interval '1 day',
  '["Sulu","メモリ","再起動"]'::jsonb,
  NOW(),
  NOW()
) ON CONFLICT (known_error_id) DO NOTHING;

INSERT INTO itsm_problem_incident (
  problem_id,
  incident_id,
  linked_at
) VALUES (
  '11111111-1111-1111-1111-111111111111',
  'INC-2024-0001',
  NOW() - interval '1 day'
) ON CONFLICT DO NOTHING;

INSERT INTO itsm_problem_change (
  problem_id,
  change_id,
  relation_type,
  linked_at
) VALUES (
  '11111111-1111-1111-1111-111111111111',
  'CHG-2024-0001',
  'fix',
  NOW() - interval '12 hours'
) ON CONFLICT DO NOTHING;

INSERT INTO itsm_kedb_documents (
  document_id,
  known_error_id,
  workaround_id,
  source_type,
  content,
  content_hash,
  language,
  metadata,
  embedding,
  active,
  created_at,
  updated_at
) VALUES (
  '44444444-4444-4444-4444-444444444444',
  '33333333-3333-3333-3333-333333333333',
  NULL,
  'known_error',
  '既知エラー: Sulu のメモリリークにより ECS タスクが再起動し、ピーク時に 502 応答が発生する。',
  'seed-known-error-0001',
  'ja',
  '{"service":"sulu","kind":"known_error","problem_number":"PRB-0001","known_error_number":"KE-0001"}'::jsonb,
  NULL,
  true,
  NOW(),
  NOW()
), (
  '55555555-5555-5555-5555-555555555555',
  NULL,
  '22222222-2222-2222-2222-222222222222',
  'workaround',
  '回避策: Sulu サービスを再デプロイしてメモリを解放し、タスクを安定化する。',
  'seed-workaround-0001',
  'ja',
  '{"service":"sulu","kind":"workaround","problem_number":"PRB-0001","known_error_number":"KE-0001"}'::jsonb,
  NULL,
  true,
  NOW(),
  NOW()
) ON CONFLICT (document_id) DO NOTHING;
