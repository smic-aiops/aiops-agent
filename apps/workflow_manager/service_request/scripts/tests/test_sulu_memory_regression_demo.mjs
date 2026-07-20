#!/usr/bin/env node

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const serviceRequestDir = resolve(scriptDir, '../..');
const repoRoot = resolve(serviceRequestDir, '../../..');
const sourcePath = resolve(serviceRequestDir, 'workflow_sources/sulu_memory_regression_demo.code.js');
const selfTestSourcePath = resolve(serviceRequestDir, 'workflow_sources/test_sulu_memory_regression_demo.code.js');
const fixturePath = resolve(repoRoot, 'apps/aiops_agent/orchestrator/scripts/tests/fixtures/sulu_memory_regression_full_cycle.json');
const recoverySchemaPath = resolve(serviceRequestDir, 'schemas/aiops.recovery_candidates.v1.schema.json');

const source = await readFile(sourcePath, 'utf8');
const selfTestSource = await readFile(selfTestSourcePath, 'utf8');
const fixture = JSON.parse(await readFile(fixturePath, 'utf8'));
const recoverySchema = JSON.parse(await readFile(recoverySchemaPath, 'utf8'));
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const execute = new AsyncFunction('$json', '$env', source);
const executeSelfTest = new AsyncFunction('$json', '$env', selfTestSource);

async function run(payload, env = {}, headers = {}, httpRequest = async () => { throw new Error('dry-run must not call external HTTP'); }) {
  return await execute.call(
    { helpers: { httpRequest } },
    { body: payload, headers },
    env
  );
}

const result = await run(fixture);

assert.deepEqual(
  Object.values(fixture.recording).map((item) => item.pptx_page),
  [58, 60, 64, 71, 66]
);

assert.equal(Array.isArray(result), true);
const output = result[0].json;
assert.equal(output.ok, true);
assert.equal(output.workflow_id, 'wf.sulu_memory_regression_demo');
assert.equal(output.correlation.status, 'correlated');
assert.ok(output.correlation.confidence >= 0.9);
assert.equal(output.recovery.schema_version, 'aiops.recovery_candidates.v1');
for (const key of recoverySchema.required) assert.ok(Object.hasOwn(output.recovery, key), `recovery schema key is missing: ${key}`);
for (const candidate of output.recovery.candidates) {
  for (const key of recoverySchema.properties.candidates.items.required) {
    assert.ok(Object.hasOwn(candidate, key), `candidate schema key is missing: ${key}`);
  }
}
assert.equal(output.recovery.candidates.length, 3);
assert.equal(output.recovery.candidates[0].workflow_id, 'wf.sulu_version_deploy');
assert.equal(output.recovery.candidates[0].rank, 1);
assert.equal(output.test_and_risk.all_required_tests_passed, true);
assert.equal(output.test_and_risk.level, 'medium');
assert.equal(output.test_and_risk.factors.length, 6);
assert.equal(output.test_and_risk.factors.reduce((sum, item) => sum + item.score_delta, 0), output.test_and_risk.score);
assert.equal(output.demo_screens.video_1_correlation.status, 'ready');
assert.equal(output.demo_screens.video_2_recovery.status, 'ready');
assert.equal(output.demo_screens.video_3_change.status, 'ready');
assert.equal(output.demo_screens.video_4_closure.status, 'ready');
assert.equal(output.artifacts.code_project_path, 'aiops/aiops-agent');
assert.equal(output.artifacts.service_project_path, 'aiops/service-management');
assert.equal(output.artifacts.source_mirror.status, 'planned');
assert.equal(output.artifacts.source_mirror.source_ref, 'fix/sulu-memory-regression-demo');
assert.equal(output.change_automation.fix_files[0].file_path, 'scripts/itsm/sulu/source_overrides/src/AIOpsDemo/MemorySafeReportIterator.php');
assert.deepEqual(Object.keys(output.artifacts.tickets.records), ['incident', 'emergency_change', 'problem', 'permanent_change']);

const wrongRealm = structuredClone(fixture);
wrongRealm.events[2].realm = 'another-realm';
const wrongRealmOutput = (await run(wrongRealm))[0].json;
assert.equal(wrongRealmOutput.ok, false);
assert.equal(wrongRealmOutput.status_code, 422);
assert.equal(wrongRealmOutput.checks.oom_detected, false);

const outsideWindow = structuredClone(fixture);
outsideWindow.events[2].occurred_at = '2026-07-16T10:45:00+09:00';
const outsideWindowOutput = (await run(outsideWindow))[0].json;
assert.equal(outsideWindowOutput.ok, false);
assert.equal(outsideWindowOutput.checks.within_correlation_window, false);

const unsafeFix = structuredClone(fixture);
unsafeFix.fix = { files: [{ action: 'create', file_path: '../escape.php', content: '<?php' }] };
const unsafeFixOutput = (await run(unsafeFix))[0].json;
assert.equal(unsafeFixOutput.ok, false);
assert.equal(unsafeFixOutput.error, 'unsafe fix file path');

const unauthorizedOutput = (await run(fixture, { N8N_WORKFLOWS_TOKEN: 'secret' }))[0].json;
assert.equal(unauthorizedOutput.status_code, 401);

const unguardedLive = structuredClone(fixture);
unguardedLive.dry_run = false;
const unguardedLiveOutput = (await run(unguardedLive))[0].json;
assert.equal(unguardedLiveOutput.status_code, 424);
assert.ok(unguardedLiveOutput.missing.includes('allow_gitlab_write=true'));

const failedCi = structuredClone(fixture);
failedCi.test_results = [{ id: 'memory_regression', status: 'failed' }];
const failedCiOutput = (await run(failedCi))[0].json;
assert.equal(failedCiOutput.test_and_risk.level, 'high');
assert.equal(failedCiOutput.approval.execution_ready, false);

const liveGitLab = structuredClone(fixture);
Object.assign(liveGitLab, {
  dry_run: false,
  allow_gitlab_write: true,
  allow_ci: true,
  wait_for_ci: false,
  approval: { approved: true, decision_id: 'CAB-DEMO-001' }
});
const calls = [];
const generatedCommitSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const gitlabMock = async (options) => {
  calls.push({ method: options.method, url: options.url, body: options.body, timeout: options.timeout });
  if (options.method === 'GET' && options.url.endsWith('/projects/aiops%2Faiops-agent')) return { id: 10 };
  if (options.method === 'GET' && options.url.endsWith('/projects/aiops%2Fservice-management')) return { id: 20 };
  if (options.url.includes('/repository/branches')) return { name: liveGitLab.gitlab.fix_branch };
  if (options.url.includes('/repository/commits')) return { id: generatedCommitSha };
  if (options.method === 'GET' && options.url.includes('/repository/files/')) {
    return { content: Buffer.from('current_version: 3.0.4\n').toString('base64') };
  }
  if (options.url.includes('/merge_requests/101/notes')) return { id: 102 };
  if (options.url.includes('/merge_requests')) return { iid: 101, web_url: 'https://gitlab.example/code/mr/101', state: 'opened' };
  if (options.method === 'POST' && options.url.endsWith('/projects/aiops%2Fservice-management/issues')) {
    const title = String(options.body?.title || '');
    if (title.startsWith('[INC]')) return { iid: 201, web_url: 'https://gitlab.example/service/issues/201', state: 'opened' };
    if (title.startsWith('[Emergency Change]')) return { iid: 202, web_url: 'https://gitlab.example/service/issues/202', state: 'opened' };
    if (title.startsWith('[PRB]')) return { iid: 203, web_url: 'https://gitlab.example/service/issues/203', state: 'opened' };
    if (title.startsWith('[Known Error]')) {
      return { iid: 404, web_url: 'https://gitlab.example/service/issues/404', state: 'closed' };
    }
    if (title.startsWith('[RFC]')) return { iid: 204, web_url: 'https://gitlab.example/service/issues/204', state: 'opened' };
    throw new Error(`unexpected service issue title: ${title}`);
  }
  if (options.url.includes('/issues/204/notes')) return { id: 301 };
  if (options.method === 'PUT' && options.url.endsWith('/issues/204') && options.body?.add_labels) return { state: 'opened' };
  if (options.method === 'PUT' && /\/issues\/(11|12|13|201|202|203|204)$/.test(options.url)) return { state: 'closed' };
  if (options.url.endsWith('/pipeline')) return { id: 303, status: 'success', web_url: 'https://gitlab.example/code/pipelines/303' };
  if (options.url.includes('api.github.com/repos/smic-aiops/aiops-agent/git/ref/heads/')) return { object: { sha: generatedCommitSha } };
  if (options.url === 'https://source.example/mismatch') return { commit: { sha: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' } };
  if (options.url.includes('/webhook/sulu/version-deploy')) return { ok: true, status: 'deployed', applied: true };
  if (options.url.includes('/webhook/sulu/rfc-source-analysis')) return { ok: true, status: 'built_and_pushed' };
  if (options.url.includes('/webhook/gitlab/issue/backfill/sor')) return { ok: true };
  if (options.url.includes('/webhook/gitlab/issue/rag/sync/oq')) return { ok: true };
  throw new Error(`unexpected mock request: ${options.method} ${options.url}`);
};
const liveOutput = (await run(
  liveGitLab,
  { GITLAB_API_BASE_URL: 'https://gitlab.example/api/v4', GITLAB_TOKEN: 'gitlab-token' },
  {},
  gitlabMock
))[0].json;
assert.equal(liveOutput.ok, true);
assert.equal(liveOutput.artifacts.project_id, 10);
assert.equal(liveOutput.artifacts.service_project_id, 20);
assert.equal(liveOutput.artifacts.tickets.records.incident.iid, 201);
assert.equal(liveOutput.artifacts.tickets.records.emergency_change.iid, 202);
assert.equal(liveOutput.artifacts.tickets.records.problem.iid, 203);
assert.equal(liveOutput.artifacts.tickets.records.permanent_change.iid, 204);
assert.equal(liveOutput.artifacts.mr.rfc_link_recorded, true);
assert.equal(liveOutput.artifacts.rfc.assessment_recorded, true);
assert.equal(liveOutput.artifacts.rfc.approval_recorded, true);
assert.equal(liveOutput.test_and_risk.all_required_tests_passed, true);
assert.equal(liveOutput.approval.execution_ready, true);
assert.ok(calls.some((call) => call.url.includes('/projects/aiops%2Faiops-agent/merge_requests')));
assert.ok(calls.some((call) => call.url.endsWith('/projects/aiops%2Fservice-management/issues')));

const prepareOnly = structuredClone(liveGitLab);
prepareOnly.approval = { approved: false, decision_id: null };
const prepareCallStart = calls.length;
const prepareOutput = (await run(
  prepareOnly,
  { GITLAB_API_BASE_URL: 'https://gitlab.example/api/v4', GITLAB_TOKEN: 'gitlab-token' },
  {},
  gitlabMock
))[0].json;
assert.equal(prepareOutput.artifacts.rfc.assessment_recorded, true);
assert.equal(prepareOutput.artifacts.rfc.approval_recorded, false);
assert.equal(prepareOutput.approval.execution_ready, false);
const prepareCalls = calls.slice(prepareCallStart);
assert.ok(prepareCalls.some((call) => String(call.body?.body || '').includes('AIOps CI・リスク評価')));
assert.ok(!prepareCalls.some((call) => String(call.body?.body || '').startsWith('/approve')));
assert.ok(calls.some((call) => String(call.body?.body || '').includes('CAB approved')));

const mirrorBuild = structuredClone(liveGitLab);
mirrorBuild.allow_ecr_push = true;
const mirrorCallStart = calls.length;
const mirrorOutput = (await run(
  mirrorBuild,
  {
    GITLAB_API_BASE_URL: 'https://gitlab.example/api/v4',
    GITLAB_TOKEN: 'gitlab-token',
    N8N_WEBHOOK_BASE_URL: 'https://n8n.example/webhook'
  },
  {},
  gitlabMock
))[0].json;
assert.equal(mirrorOutput.artifacts.source_mirror.status, 'verified');
assert.equal(mirrorOutput.artifacts.source_mirror.expected_commit_sha, generatedCommitSha);
assert.equal(mirrorOutput.artifacts.source_mirror.resolved_commit_sha, generatedCommitSha);
assert.equal(mirrorOutput.artifacts.workflow_dispatch.rfc_analysis.status, 'built_and_pushed');
const mirrorCalls = calls.slice(mirrorCallStart);
const pipelineIndex = mirrorCalls.findIndex((call) => call.url.endsWith('/pipeline'));
const assessmentIndex = mirrorCalls.findIndex((call) => String(call.body?.body || '').includes('AIOps CI・リスク評価'));
const approvalIndex = mirrorCalls.findIndex((call) => String(call.body?.body || '').startsWith('/approve'));
const sourceMirrorIndex = mirrorCalls.findIndex((call) => call.url.includes('api.github.com/repos/smic-aiops/aiops-agent/git/ref/heads/'));
const buildIndex = mirrorCalls.findIndex((call) => call.url.includes('/webhook/sulu/rfc-source-analysis'));
assert.ok(pipelineIndex >= 0 && pipelineIndex < assessmentIndex);
assert.ok(assessmentIndex < approvalIndex);
assert.ok(approvalIndex < sourceMirrorIndex);
assert.ok(sourceMirrorIndex < buildIndex);

const fullExecution = structuredClone(mirrorBuild);
Object.assign(fullExecution, {
  execute_rollback: true,
  execute_fixed_deploy: true,
  allow_service_change: true
});
const fullExecutionCallStart = calls.length;
const fullExecutionOutput = (await run(
  fullExecution,
  {
    GITLAB_API_BASE_URL: 'https://gitlab.example/api/v4',
    GITLAB_TOKEN: 'gitlab-token',
    N8N_WEBHOOK_BASE_URL: 'https://n8n.example/webhook'
  },
  {},
  gitlabMock
))[0].json;
assert.equal(fullExecutionOutput.artifacts.workflow_dispatch.rollback.applied, true);
assert.equal(fullExecutionOutput.artifacts.workflow_dispatch.rfc_analysis.status, 'built_and_pushed');
assert.equal(fullExecutionOutput.artifacts.workflow_dispatch.fixed_deploy.applied, true);
const fullExecutionCalls = calls.slice(fullExecutionCallStart);
const versionDeployCalls = fullExecutionCalls.filter((call) => call.url.includes('/webhook/sulu/version-deploy'));
assert.equal(versionDeployCalls.length, 2);
assert.ok(versionDeployCalls.every((call) => call.body.rfc_issue_url === 'https://gitlab.example/service/issues/204'));
assert.ok(versionDeployCalls.every((call) => call.timeout === 600000));
const rfcAnalysisCall = fullExecutionCalls.find((call) => call.url.includes('/webhook/sulu/rfc-source-analysis'));
assert.equal(rfcAnalysisCall.body.target_version, '3.0.4');
assert.equal(rfcAnalysisCall.body.image_tag, '3.0.4-smic.1');
assert.equal(rfcAnalysisCall.timeout, 3900000);

const mirrorMismatch = structuredClone(mirrorBuild);
mirrorMismatch.build_source = { ref_api_url: 'https://source.example/mismatch' };
const mismatchOutput = (await run(
  mirrorMismatch,
  {
    GITLAB_API_BASE_URL: 'https://gitlab.example/api/v4',
    GITLAB_TOKEN: 'gitlab-token',
    N8N_WEBHOOK_BASE_URL: 'https://n8n.example/webhook'
  },
  {},
  gitlabMock
))[0].json;
assert.equal(mismatchOutput.status_code, 409);
assert.equal(mismatchOutput.error, 'source mirror commit does not match the generated GitLab commit');
assert.equal(mismatchOutput.expected_commit_sha, generatedCommitSha);

const unsafeClose = structuredClone(liveGitLab);
unsafeClose.allow_state_change = true;
const unsafeCloseOutput = (await run(unsafeClose))[0].json;
assert.equal(unsafeCloseOutput.status_code, 422);

const verifiedClosure = structuredClone(liveGitLab);
Object.assign(verifiedClosure, {
  allow_state_change: true,
  post_deploy_verified: true,
  verification_id: 'healthcheck/demo-001',
  tickets: [11, 12, 13]
});
const closureOutput = (await run(
  verifiedClosure,
  {
    GITLAB_API_BASE_URL: 'https://gitlab.example/api/v4',
    GITLAB_TOKEN: 'gitlab-token',
    N8N_WEBHOOK_BASE_URL: 'https://n8n.example/webhook'
  },
  {},
  gitlabMock
))[0].json;
assert.deepEqual(closureOutput.artifacts.tickets.closed_iids, [11, 12, 13, 201, 202, 203, 204]);
assert.equal(closureOutput.artifacts.cmdb.status, 'synced');
assert.equal(closureOutput.artifacts.cmdb.trace_id, fixture.trace_id);
assert.equal(closureOutput.artifacts.cmdb.verification_id, 'healthcheck/demo-001');
const cmdbCommitCall = calls.findLast((call) => call.url.includes('/repository/commits') && call.body?.actions?.[0]?.file_path === 'cmdb/sulu.md');
assert.ok(cmdbCommitCall.body.actions[0].content.includes(`last_change_trace_id: ${fixture.trace_id}`));
assert.ok(cmdbCommitCall.body.actions[0].content.includes('last_verification_id: healthcheck/demo-001'));
assert.equal(closureOutput.artifacts.kedb.status, 'registered');
assert.equal(closureOutput.artifacts.kedb.sor_sync, 'completed');
assert.equal(closureOutput.artifacts.kedb.qdrant_sync, 'completed');
assert.equal(closureOutput.approval.verification_id, 'healthcheck/demo-001');
assert.equal(closureOutput.demo_screens.video_4_closure.status, 'ready');

const selfTestUrls = [];
const selfTestOutput = await executeSelfTest.call(
  { helpers: { httpRequest: async (options) => { selfTestUrls.push(options.url); return output; } } },
  { body: { realm: 'aiops' }, headers: { Authorization: 'Bearer self-test-token' } },
  { N8N_WORKFLOWS_TOKEN: 'self-test-token', N8N_PUBLIC_API_BASE_URL: 'https://n8n.example/api/v1' }
);
assert.equal(selfTestOutput[0].json.ok, true);
assert.deepEqual(selfTestUrls, ['https://n8n.example/webhook/sulu/memory-regression-demo']);

const unauthorizedSelfTest = await executeSelfTest.call(
  { helpers: { httpRequest: async () => { throw new Error('unauthorized self-test must not call target'); } } },
  { body: { realm: 'aiops' }, headers: {} },
  { N8N_WORKFLOWS_TOKEN: 'self-test-token', N8N_PUBLIC_API_BASE_URL: 'https://n8n.example' }
);
assert.equal(unauthorizedSelfTest[0].json.status_code, 401);

process.stdout.write('Sulu memory regression integrated demo dry-run, guardrails, and mocked GitLab flow: PASS\n');
