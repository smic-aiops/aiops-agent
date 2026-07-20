#!/usr/bin/env node

import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const workflowPath = resolve(scriptDir, '../workflows/aiops_job_engine_queue.json');
const workflow = JSON.parse(await readFile(workflowPath, 'utf8'));
const node = workflow.nodes.find((item) => item.name === 'Execute Job');
if (!node?.parameters?.jsCode) {
  throw new Error('Execute Job code node was not found');
}

const marker = "  throw new Error(`unsupported workflow_id: ${workflowId}`);";
const sentinel = "workflowId === 'wf.sulu_version_deploy'";
let changed = false;

const helperAnchor = 'const workflowsToken = $env.N8N_WORKFLOWS_TOKEN;';
const helperCapture = `${helperAnchor}\nconst httpRequest = (options) => this.helpers.httpRequest(options);`;
if (!node.parameters.jsCode.includes('const httpRequest = (options) => this.helpers.httpRequest(options);')) {
  if (!node.parameters.jsCode.includes(helperAnchor)) throw new Error('workflow token anchor was not found');
  node.parameters.jsCode = node.parameters.jsCode.replace(helperAnchor, helperCapture);
  changed = true;
}
if (node.parameters.jsCode.includes('await this.helpers.httpRequest({')) {
  node.parameters.jsCode = node.parameters.jsCode.replaceAll('await this.helpers.httpRequest({', 'await httpRequest({');
  changed = true;
}

const legacyWebhookBase = "  const webhookBase = deriveWebhookBaseFromCallbackUrl(callbackUrl) || String($env.N8N_WEBHOOK_BASE_URL ?? '').trim().replace(/\\/+$/, '');";
const normalizedWebhookBase = `  const webhookOrigin = deriveWebhookBaseFromCallbackUrl(callbackUrl) || String($env.N8N_WEBHOOK_BASE_URL ?? '').trim().replace(/\\/+$/, '').replace(/\\/api\\/v1$/, '');
  const webhookBase = webhookOrigin ? (webhookOrigin.endsWith('/webhook') ? webhookOrigin : \`${'${webhookOrigin}'}/webhook\`) : '';`;
if (node.parameters.jsCode.includes(legacyWebhookBase)) {
  node.parameters.jsCode = node.parameters.jsCode.replace(legacyWebhookBase, normalizedWebhookBase);
  changed = true;
}

if (!node.parameters.jsCode.includes(sentinel)) {
  if (!node.parameters.jsCode.includes(marker)) {
    throw new Error('unsupported workflow marker was not found');
  }
  const dispatchCode = `  if (workflowId === 'wf.sulu_version_deploy') {
    const body = { ...params, realm };
    const response = await httpRequest({
      method: 'POST',
      url: \`${'${webhookBase}'}/sulu/version-deploy\`,
      json: true,
      timeout: 300000,
      headers: workflowsToken ? { Authorization: \`Bearer ${'${workflowsToken}'}\` } : {},
      body
    });
    resultPayload.workflow_api_response = response;
    resultPayload.note = 'executed via n8n webhook: /sulu/version-deploy';
    return;
  }

  if (workflowId === 'wf.sulu_rfc_source_analysis') {
    const body = { ...params, realm };
    const response = await httpRequest({
      method: 'POST',
      url: \`${'${webhookBase}'}/sulu/rfc-source-analysis\`,
      json: true,
      timeout: 600000,
      headers: workflowsToken ? { Authorization: \`Bearer ${'${workflowsToken}'}\` } : {},
      body
    });
    resultPayload.workflow_api_response = response;
    resultPayload.note = 'executed via n8n webhook: /sulu/rfc-source-analysis';
    return;
  }

  if (workflowId === 'wf.sulu_memory_regression_demo') {
    const body = { ...params, realm, trace_id: params.trace_id ?? traceId };
    const response = await httpRequest({
      method: 'POST',
      url: \`${'${webhookBase}'}/sulu/memory-regression-demo\`,
      json: true,
      timeout: 900000,
      headers: workflowsToken ? { Authorization: \`Bearer ${'${workflowsToken}'}\` } : {},
      body
    });
    resultPayload.workflow_api_response = response;
    resultPayload.note = 'executed via n8n webhook: /sulu/memory-regression-demo';
    return;
  }

`;
  node.parameters.jsCode = node.parameters.jsCode.replace(marker, `${dispatchCode}${marker}`);
  changed = true;
}

if (changed) {
  workflow.meta = { ...(workflow.meta || {}), suluDispatchRevision: 2 };
  await writeFile(workflowPath, `${JSON.stringify(workflow, null, 2)}\n`, 'utf8');
  process.stdout.write('updated aiops_job_engine_queue.json with normalized Sulu dispatch routes\n');
} else {
  process.stdout.write('aiops_job_engine_queue.json already contains Sulu dispatch routes\n');
}
