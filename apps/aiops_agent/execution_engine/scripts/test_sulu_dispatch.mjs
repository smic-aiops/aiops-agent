#!/usr/bin/env node

import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const workflowPath = resolve(scriptDir, '../workflows/aiops_job_engine_queue.json');
const workflow = JSON.parse(await readFile(workflowPath, 'utf8'));
const code = workflow.nodes.find((item) => item.name === 'Execute Job (stub)')?.parameters?.jsCode || '';

for (const workflowId of [
  'wf.sulu_service_control',
  'wf.sulu_configuration_recovery',
  'wf.sulu_version_deploy',
  'wf.sulu_rfc_source_analysis',
  'wf.sulu_memory_regression_demo'
]) {
  assert.ok(code.includes(`workflowId === '${workflowId}'`), `missing dispatch: ${workflowId}`);
}

assert.ok(code.includes('/sulu/version-deploy'));
assert.ok(code.includes('/sulu/rfc-source-analysis'));
assert.ok(code.includes('/sulu/memory-regression-demo'));
assert.ok(code.includes("webhookOrigin.endsWith('/webhook')"));
assert.ok(!code.includes('await this.helpers.httpRequest'));

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const execute = new AsyncFunction('$json', '$env', 'require', code);
const require = createRequire(import.meta.url);
for (const [workflowId, route] of [
  ['wf.sulu_version_deploy', '/webhook/sulu/version-deploy'],
  ['wf.sulu_rfc_source_analysis', '/webhook/sulu/rfc-source-analysis']
]) {
  const urls = [];
  const result = await execute.call(
    { helpers: { httpRequest: async (options) => { urls.push(options.url); return { ok: true }; } } },
    {
      job_id: `test-${workflowId}`,
      trace_id: 'trace-dispatch-test',
      callback_url: 'https://n8n.example/webhook/callback/job-engine',
      job_plan: { workflow_id: workflowId, params: { realm: 'aiops', dry_run: true } }
    },
    { N8N_WORKFLOWS_TOKEN: 'test-token' },
    require
  );
  assert.equal(result[0].json.status, 'success', JSON.stringify(result[0].json));
  assert.deepEqual(urls, [`https://n8n.example${route}`]);
}
process.stdout.write('Sulu job-engine dispatch routes: PASS\n');
