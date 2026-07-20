const request = $json ?? {};
const headers = request.headers && typeof request.headers === 'object' ? request.headers : {};
const payload = request.body && typeof request.body === 'object' ? request.body : request;
const expectedToken = String($env.N8N_WORKFLOWS_TOKEN || '').trim();
const authKey = Object.keys(headers).find((key) => ['authorization', 'x-aiops-workflows-token'].includes(String(key).toLowerCase()));
const providedToken = authKey ? String(headers[authKey] || '').replace(/^bearer\s+/i, '').trim() : '';
if (!expectedToken) return [{ json: { ok: false, status_code: 500, error: 'N8N_WORKFLOWS_TOKEN is not configured' } }];
if (providedToken !== expectedToken) return [{ json: { ok: false, status_code: 401, error: 'invalid workflows token' } }];
const rawOrigin = String($env.N8N_WEBHOOK_BASE_URL || $env.N8N_PUBLIC_API_BASE_URL || '')
  .replace(/\/+$/, '')
  .replace(/\/api\/v1$/, '');
const webhookBase = rawOrigin ? (rawOrigin.endsWith('/webhook') ? rawOrigin : `${rawOrigin}/webhook`) : '';
if (!webhookBase) return [{ json: { ok: false, status_code: 500, error: 'webhook base URL is not configured' } }];
const fixtureRealm = String(payload.realm || $env.N8N_REALM || $env.N8N_ENV_REALM || 'aiops');

const fixture = {
  realm: fixtureRealm,
  trace_id: 'oq-sulu-memory-regression-selftest',
  dry_run: true,
  service: 'sulu',
  fixed_version: '3.0.4-smic.1',
  deployment: {
    previous_version: '3.0.3',
    current_version: '3.0.4',
    deployed_at: '2026-07-17T01:00:00Z',
    change_id: 'CHG-OQ-SULU-304'
  },
  events: [
    { event_id: 'mem-001', kind: 'memory_high', occurred_at: '2026-07-17T01:01:00Z', metric_value: 92, service: 'sulu', realm: fixtureRealm, image_tag: '3.0.4' },
    { event_id: 'mem-002', kind: 'memory_high', occurred_at: '2026-07-17T01:02:00Z', metric_value: 94, service: 'sulu', realm: fixtureRealm, image_tag: '3.0.4' },
    { event_id: 'oom-001', kind: 'oom', occurred_at: '2026-07-17T01:03:00Z', service: 'sulu', realm: fixtureRealm, image_tag: '3.0.4' }
  ]
};

try {
  const response = await this.helpers.httpRequest({
    method: 'POST',
    url: `${webhookBase}/sulu/memory-regression-demo`,
    json: true,
    timeout: 120000,
    headers: expectedToken ? { Authorization: `Bearer ${expectedToken}` } : {},
    body: fixture
  });
  const candidates = response?.recovery?.candidates;
  const screens = response?.demo_screens;
  const passed = response?.ok === true
    && response?.workflow_id === 'wf.sulu_memory_regression_demo'
    && response?.correlation?.status === 'correlated'
    && Number(response?.correlation?.confidence || 0) >= 0.9
    && Array.isArray(candidates)
    && candidates.length >= 3
    && candidates[0]?.workflow_id === 'wf.sulu_version_deploy'
    && candidates[0]?.rank === 1
    && response?.test_and_risk?.all_required_tests_passed === true
    && response?.test_and_risk?.level === 'medium'
    && Array.isArray(response?.test_and_risk?.factors)
    && response.test_and_risk.factors.reduce((sum, item) => sum + Number(item?.score_delta || 0), 0) === response.test_and_risk.score
    && Object.keys(response?.artifacts?.tickets?.records || {}).length === 4
    && response?.artifacts?.source_mirror?.status === 'planned'
    && screens?.video_1_correlation?.status === 'ready'
    && screens?.video_2_recovery?.status === 'ready'
    && screens?.video_3_change?.status === 'ready'
    && screens?.video_4_closure?.status === 'ready';
  return [{ json: { ok: passed, status_code: passed ? 200 : 500, data: { target_response: response }, error: passed ? null : 'integrated demo assertions failed' } }];
} catch (error) {
  return [{ json: { ok: false, status_code: 500, error: error?.message ? String(error.message) : String(error) } }];
}
