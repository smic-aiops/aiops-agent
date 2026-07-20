#!/usr/bin/env node

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const appDir = resolve(scriptDir, '..');
const sourceDir = resolve(appDir, 'workflow_sources');
const workflowDir = resolve(appDir, 'workflows');

function webhookNode({ id, name, path, position }) {
  return {
    parameters: {
      httpMethod: 'POST',
      path,
      responseMode: 'responseNode',
      options: {}
    },
    id,
    name,
    type: 'n8n-nodes-base.webhook',
    typeVersion: 2,
    position
  };
}

function codeNode({ id, name, jsCode, position }) {
  return {
    parameters: { jsCode },
    id,
    name,
    type: 'n8n-nodes-base.code',
    typeVersion: 2,
    position
  };
}

function respondNode({ id, name, position }) {
  return {
    parameters: {
      respondWith: 'json',
      responseBody: '={{$json}}',
      options: {
        responseCode: '={{$json.status_code || ($json.ok === false ? 500 : 200)}}'
      }
    },
    id,
    name,
    type: 'n8n-nodes-base.respondToWebhook',
    typeVersion: 1.4,
    position
  };
}

function buildWorkflow({ name, workflowId, webhookName, webhookPath, codeName, code, responseName }) {
  return {
    name,
    nodes: [
      webhookNode({ id: `${workflowId}-webhook`, name: webhookName, path: webhookPath, position: [260, 300] }),
      codeNode({ id: `${workflowId}-code`, name: codeName, jsCode: code, position: [520, 300] }),
      respondNode({ id: `${workflowId}-respond`, name: responseName, position: [780, 300] })
    ],
    connections: {
      [webhookName]: { main: [[{ node: codeName, type: 'main', index: 0 }]] },
      [codeName]: { main: [[{ node: responseName, type: 'main', index: 0 }]] }
    },
    active: false,
    settings: { executionTimeout: 5400 },
    versionId: '',
    staticData: null,
    meta: {
      revision: 1,
      workflowId,
      createdBy: { id: '1', name: 'system' }
    },
    tags: []
  };
}

await mkdir(workflowDir, { recursive: true });

const targetCode = await readFile(resolve(sourceDir, 'sulu_memory_regression_demo.code.js'), 'utf8');
const testCode = await readFile(resolve(sourceDir, 'test_sulu_memory_regression_demo.code.js'), 'utf8');

const target = buildWorkflow({
  name: 'Sulu Memory Regression Integrated Demo',
  workflowId: 'wf.sulu_memory_regression_demo',
  webhookName: 'Webhook Sulu Memory Regression Demo',
  webhookPath: 'sulu/memory-regression-demo',
  codeName: 'Correlate and Run Integrated Demo',
  code: targetCode,
  responseName: 'Respond Sulu Memory Regression Demo'
});

const test = buildWorkflow({
  name: 'Test Sulu Memory Regression Integrated Demo',
  workflowId: 'test.wf.sulu_memory_regression_demo',
  webhookName: 'Webhook Test Sulu Memory Regression Demo',
  webhookPath: 'tests/sulu/memory-regression-demo',
  codeName: 'Run and Verify Integrated Demo',
  code: testCode,
  responseName: 'Respond Sulu Memory Regression Demo Test'
});

const outputs = [
  ['aiops_sulu_memory_regression_demo.json', target],
  ['test_aiops_sulu_memory_regression_demo.json', test]
];

for (const [filename, workflow] of outputs) {
  await writeFile(resolve(workflowDir, filename), `${JSON.stringify(workflow, null, 2)}\n`, 'utf8');
  process.stdout.write(`generated ${filename}\n`);
}
