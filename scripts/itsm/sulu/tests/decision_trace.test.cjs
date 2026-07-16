'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const {pathToFileURL} = require('node:url');

let buildDecisionExplanation;
let isScenario2Event;

test.before(async() => {
    const modulePath = path.resolve(
        __dirname,
        '../admin_monitoring_assets/assets/admin/views/AiNodeMonitoring/decisionTrace.mjs'
    );
    const decisionTrace = await import(pathToFileURL(modulePath).href);
    buildDecisionExplanation = decisionTrace.buildDecisionExplanation;
    isScenario2Event = decisionTrace.isScenario2Event;
});

function event(node, output, overrides = {}) {
    return {
        id: overrides.id || 1,
        received_at: '2026-07-16T06:00:00Z',
        realm: 'aiops',
        workflow: overrides.workflow || 'aiops-orchestrator',
        node,
        execution_id: overrides.execution_id || 'scenario2-execution-1',
        payload: {
            phase: 'after',
            output: [output],
        },
    };
}

test('シナリオ2の承認判断を女子高生向けの言葉へ変換する', () => {
    const explanation = buildDecisionExplanation(event('OpenAI Jobs Preview', {
        trace_id: 'demo-scenario-2-001',
        next_action: 'require_approval',
        required_confirm: true,
        confidence: 0.92,
        rationale: 'high_risk_configuration_change',
        job_plan: {
            workflow_id: 'wf.sulu_configuration_recovery',
            risk_level: 'high',
            summary: 'GitLabの誤設定を戻してSuluを復旧する',
        },
    }));

    assert.equal(explanation.stage, '実行前チェック');
    assert.match(explanation.decision, /人のOKを待ちます/);
    assert.match(explanation.reason, /影響が大きい/);
    assert.match(explanation.humanAction, /承認してください/);
    assert.equal(explanation.confidenceText, '確信度 92%（かなり自信あり）');
    assert.equal(explanation.workflowId, 'wf.sulu_configuration_recovery');
    assert.equal(explanation.isScenario2, true);
    assert.equal(explanation.tone, 'approval');
});

test('分類結果を技術用語だけでなく意味のある説明にする', () => {
    const explanation = buildDecisionExplanation(event('OpenAI Classify Event', {
        trace_id: 'demo-scenario-2-001',
        normalized_event: {
            source: 'cloudwatch',
            classification: {
                category: 'incident',
                priority: 'critical',
            },
        },
        confidence: 0.84,
    }));

    assert.equal(explanation.stage, '受付・分類');
    assert.match(explanation.observed, /サービス障害/);
    assert.match(explanation.decision, /サービス障害/);
    assert.match(explanation.confidenceText, /84%/);
});

test('ドライラン成功を本番変更と誤解させない', () => {
    const explanation = buildDecisionExplanation(event('Sulu Configuration Recovery Result', {
        trace_id: 'demo-scenario-2-001',
        workflow_id: 'wf.sulu_configuration_recovery',
        status: 'validated',
        dry_run: true,
        simulated: true,
        applied: false,
        summary: '復旧手順の事前検証が完了',
    }));

    assert.match(explanation.decision, /リハーサルに成功/);
    assert.match(explanation.humanAction, /本番実行を判断/);
    assert.equal(explanation.dryRun, true);
    assert.equal(explanation.applied, false);
    assert.equal(explanation.tone, 'success');
});

test('LLM応答異常時のフォールバックを安全側判断として説明する', () => {
    const explanation = buildDecisionExplanation(event('OpenAI Jobs Preview', {
        trace_id: 'demo-scenario-2-001',
        next_action: 'require_approval',
        required_confirm: true,
        confidence: 0,
        llm_error: 'invalid_llm_response',
        llm_fallback: 'cloudwatch_monitoring_hint',
        workflow_id: 'wf.sulu_configuration_recovery',
    }));

    assert.match(explanation.reason, /決められた形式ではなかった/);
    assert.match(explanation.confidenceText, /慎重に確認が必要/);
});

test('専用aiops.sulu_log形式からノード名とtrace IDを取り出せる', () => {
    const explanation = buildDecisionExplanation({
        id: 9,
        received_at: '2026-07-16T06:00:00Z',
        payload: {
            raw: {
                kind: 'aiops.sulu_log',
                phase: 'after',
                ai_node: 'OpenAI Routing Decide',
                trace_id: 'demo-scenario-2-direct',
                payload: {
                    routing: {summary: 'CAB担当者へ承認依頼を送る'},
                },
            },
        },
    });

    assert.equal(explanation.node, 'OpenAI Routing Decide');
    assert.equal(explanation.traceId, 'demo-scenario-2-direct');
    assert.equal(explanation.stage, '担当選び');
    assert.equal(isScenario2Event({
        payload: {output: [{trace_id: 'demo-scenario-2-direct'}]},
    }), true);
});

test('旧Observerが接続先をnodeへ保存したログでも実際のAIノードを復元する', () => {
    const explanation = buildDecisionExplanation({
        id: 11,
        node: 'Sulu Decision Observer',
        execution_id: 'demo-scenario-2-old-observer',
        payload: {
            phase: 'after',
            output: [{
                trace_id: 'demo-scenario-2-old-observer',
                next_action: 'require_approval',
                required_confirm: true,
            }],
            raw: {
                event: {
                    phase: 'after',
                    source: 'OpenAI Jobs Preview',
                    target: 'Sulu Decision Observer',
                },
            },
        },
    });

    assert.equal(explanation.node, 'OpenAI Jobs Preview');
    assert.equal(explanation.stage, '実行前チェック');
});

test('出力が欠けても空のサマリにしない', () => {
    const explanation = buildDecisionExplanation({
        id: 10,
        node: 'OpenAI Unknown Node',
        execution_id: 'generic-execution',
        payload: {phase: 'after', output: []},
    });

    assert.ok(explanation.observed.length > 0);
    assert.ok(explanation.decision.length > 0);
    assert.ok(explanation.reason.length > 0);
});
