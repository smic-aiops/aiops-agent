'use strict';

const NEXT_ACTION_LABELS = {
    auto_enqueue: '安全条件を満たしたため、自動で次の処理へ進めます',
    require_approval: '影響が大きい可能性があるため、人のOKを待ちます',
    ask_clarification: '情報が足りないため、確認してから進みます',
    reply_only: 'システムは変更せず、説明だけを返します',
    reject: '安全ルールに合わないため、自動実行しません',
};

const CATEGORY_LABELS = {
    incident: 'サービス障害',
    problem: '繰り返し起きる問題',
    change: '設定変更',
    service_request: '作業依頼',
    request: '作業依頼',
    information: '情報の問い合わせ',
    feedback: '利用者からの評価',
};

const RISK_LABELS = {
    low: '影響は小さそうです',
    medium: '影響範囲を確認しながら進めます',
    high: '間違えるとサービスへ大きな影響が出る可能性があります',
    critical: 'サービス停止につながる可能性があるため、特に慎重に扱います',
};

function isObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function firstObject(value) {
    if (isObject(value)) return value;
    if (!Array.isArray(value)) return undefined;
    for (const entry of value) {
        if (isObject(entry)) return entry;
    }
    return undefined;
}

function unwrap(value) {
    let current = value;
    for (let depth = 0; depth < 4; depth += 1) {
        if (!isObject(current)) break;
        if (isObject(current.json)) {
            current = current.json;
            continue;
        }
        break;
    }
    return isObject(current) ? current : {};
}

function findByKeys(value, keys, maxDepth = 6, seen = new Set()) {
    if (maxDepth < 0 || value === null || value === undefined) return undefined;
    if (typeof value !== 'object') return undefined;
    if (seen.has(value)) return undefined;
    seen.add(value);

    if (isObject(value)) {
        for (const key of keys) {
            if (Object.prototype.hasOwnProperty.call(value, key)) {
                const candidate = value[key];
                if (candidate !== null && candidate !== undefined && candidate !== '') return candidate;
            }
        }
        for (const child of Object.values(value)) {
            const found = findByKeys(child, keys, maxDepth - 1, seen);
            if (found !== undefined) return found;
        }
    } else if (Array.isArray(value)) {
        for (const child of value) {
            const found = findByKeys(child, keys, maxDepth - 1, seen);
            if (found !== undefined) return found;
        }
    }
    return undefined;
}

function collectUrls(value, maxDepth = 6, result = new Set(), seen = new Set()) {
    if (maxDepth < 0 || value === null || value === undefined || result.size >= 4) return result;
    if (typeof value === 'string') {
        const matches = value.match(/https?:\/\/[^\s"'<>]+/g) || [];
        for (const match of matches) {
            result.add(match.replace(/[),.;]+$/, ''));
            if (result.size >= 4) break;
        }
        return result;
    }
    if (typeof value !== 'object' || seen.has(value)) return result;
    seen.add(value);
    const children = Array.isArray(value) ? value : Object.values(value);
    for (const child of children) {
        collectUrls(child, maxDepth - 1, result, seen);
        if (result.size >= 4) break;
    }
    return result;
}

function firstString(...values) {
    for (const value of values) {
        if (typeof value === 'string' && value.trim()) return value.trim();
        if (typeof value === 'number' && Number.isFinite(value)) return String(value);
    }
    return undefined;
}

function toBoolean(value) {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'number') return value !== 0;
    if (typeof value !== 'string') return undefined;
    const normalized = value.trim().toLowerCase();
    if (['true', '1', 'yes', 'required'].includes(normalized)) return true;
    if (['false', '0', 'no', 'not_required'].includes(normalized)) return false;
    return undefined;
}

function clampConfidence(value) {
    const number = Number(value);
    if (!Number.isFinite(number)) return undefined;
    return Math.max(0, Math.min(1, number));
}

function truncate(value, maxLength = 180) {
    if (value === null || value === undefined) return '';
    const text = String(value).replace(/\s+/g, ' ').trim();
    if (text.length <= maxLength) return text;
    return `${text.slice(0, Math.max(0, maxLength - 1))}…`;
}

function safeStringify(value) {
    try {
        return JSON.stringify(value);
    } catch (error) {
        return String(value ?? '');
    }
}

function eventData(event) {
    const payload = isObject(event && event.payload) ? event.payload : {};
    const raw = isObject(payload.raw) ? payload.raw : {};
    const output = unwrap(firstObject(payload.output));
    const direct = unwrap(isObject(raw.payload) ? raw.payload : payload.payload);
    const input = unwrap(firstObject(payload.input));
    const data = Object.keys(output).length > 0
        ? output
        : (Object.keys(direct).length > 0 ? direct : input);

    const phase = firstString(payload.phase, raw.phase, raw.event && raw.event.phase);
    const eventObject = isObject(raw.event) ? raw.event : {};
    const node = firstString(
        raw.ai_node,
        phase === 'after' ? eventObject.source : eventObject.target,
        event && event.node,
        payload.node,
        eventObject.source,
        eventObject.target
    ) || 'AIノード';

    const roots = [data, direct, output, input, payload, raw];
    const find = (keys) => {
        for (const root of roots) {
            const value = findByKeys(root, keys);
            if (value !== undefined) return value;
        }
        return undefined;
    };

    return {payload, raw, data, roots, find, node, phase};
}

function stageForNode(node) {
    const value = String(node || '').toLowerCase();
    if (value.includes('classify') || value.includes('chat core')) return ['受付・分類', '届いた内容が何の話かを整理しました'];
    if (value.includes('enrichment plan')) return ['調査計画', '判断に必要な資料やログを選びました'];
    if (value.includes('context summary') || value.includes('enrichment summary')) return ['情報整理', '集めた情報を短く整理しました'];
    if (value.includes('rag')) return ['資料検索', '過去の記録や手順書から参考情報を探しました'];
    if (value.includes('routing')) return ['担当選び', '誰へ知らせ、どこへ処理を渡すか決めました'];
    if (value.includes('preview') || value.includes('job')) return ['実行前チェック', '使う復旧手順と、人の承認が必要かを確認しました'];
    if (value.includes('approval') || value.includes('cab')) return ['人の確認', '人が実行してよいか確認しました'];
    if (value.includes('initial reply') || value.includes('reply')) return ['説明', '判断内容を人に伝わる文章へ直しました'];
    if (value.includes('callback') || value.includes('result') || value.includes('verify')) return ['結果確認', '実行結果を確認し、記録に残しました'];
    if (value.includes('queue') || value.includes('execute') || value.includes('recovery')) return ['実行', '承認された手順を実行しました'];
    return ['処理中', 'AIノードの処理結果を受け取りました'];
}

function humanizeReason(rationale, requiredConfirm, risk, nextAction) {
    const normalized = String(rationale || '').toLowerCase();
    if (normalized.includes('invalid_llm_response') || normalized.includes('llm_preview_missing_or_invalid')) {
        return 'AIの回答が決められた形式ではなかったため、勝手に進まず安全側のルールを使いました';
    }
    if (normalized.includes('fallback_preview_no_llm') || normalized.includes('cloudwatch_monitoring_hint')) {
        return 'AIの回答が使えなかったため、あらかじめ決めた監視ルールから候補を選びました';
    }
    if (requiredConfirm === true || nextAction === 'require_approval') {
        return risk === 'critical' || risk === 'high'
            ? 'サービス設定を変える可能性があり、失敗時の影響が大きいためです'
            : 'システムを変更する操作なので、人が内容を確認するルールになっているためです';
    }
    if (nextAction === 'ask_clarification') return '今ある情報だけで決めると間違える可能性があるためです';
    if (nextAction === 'reject') return '許可されていない操作、または安全を確認できない操作だからです';
    if (risk && RISK_LABELS[risk]) return RISK_LABELS[risk];
    if (rationale) return `記録された判断理由: ${truncate(rationale, 140)}`;
    return '入力データ、運用ルール、過去の記録を照らし合わせた結果です';
}

function buildDecisionExplanation(event) {
    const context = eventData(event || {});
    const [stage, action] = stageForNode(context.node);
    const find = context.find;

    const nextAction = firstString(find(['next_action', 'nextAction']));
    const risk = firstString(find(['risk_level', 'riskLevel', 'risk']));
    const requiredConfirm = toBoolean(find(['required_confirm', 'requiredConfirm', 'needs_approval']));
    const confidence = clampConfidence(find(['confidence', 'decision_confidence', 'decision_score']));
    const category = firstString(find(['category', 'event_kind', 'eventKind']));
    const source = firstString(find(['source']));
    const workflowId = firstString(find(['workflow_id', 'workflowId']));
    const status = firstString(find(['job_status', 'status']));
    const rationale = firstString(find(['rationale', 'reason', 'llm_error']));
    const summary = firstString(find(['confirmation_summary', 'summary', 'result_summary', 'text']));
    const traceId = firstString(find(['trace_id', 'traceId']), event && event.execution_id);
    const contextId = firstString(find(['context_id', 'contextId']));
    const promptVersion = firstString(find(['prompt_version', 'promptVersion']));
    const promptHash = firstString(find(['prompt_hash', 'promptHash']));
    const policyVersion = firstString(find(['policy_version', 'policyVersion']));
    const dryRun = toBoolean(find(['dry_run', 'dryRun']));
    const simulated = toBoolean(find(['simulated']));
    const applied = toBoolean(find(['applied']));

    let observed = summary ? truncate(summary) : '';
    if (!observed && category) observed = `届いた内容を「${CATEGORY_LABELS[category] || category}」として読み取りました`;
    if (!observed && source) observed = `${source} から届いた情報を確認しました`;
    if (!observed) observed = `${context.node} の処理ログを確認しました`;

    let decision = '';
    if (nextAction && NEXT_ACTION_LABELS[nextAction]) decision = NEXT_ACTION_LABELS[nextAction];
    else if (status === 'validated' && dryRun === true) decision = '本番を変更しないリハーサルに成功しました';
    else if (status && ['completed', 'success', 'succeeded', 'closed'].includes(status.toLowerCase())) decision = '処理は正常に完了しました';
    else if (workflowId) decision = `「${workflowId}」という手順を実行候補に選びました`;
    else if (category) decision = `これは「${CATEGORY_LABELS[category] || category}」として扱います`;
    else decision = action;

    let humanAction = '今は人の操作は必要ありません';
    if (nextAction === 'require_approval' || requiredConfirm === true) humanAction = '内容を確認し、実行してよければ承認してください';
    else if (nextAction === 'ask_clarification') humanAction = '不足している情報への回答が必要です';
    else if (nextAction === 'reject') humanAction = '実行せず、運用担当者へ相談してください';
    else if (status === 'validated' && dryRun === true && applied !== true) humanAction = 'リハーサル結果を確認してから、本番実行を判断してください';

    const evidence = Array.from(collectUrls(context.roots));
    if (workflowId) evidence.unshift(`選んだ手順: ${workflowId}`);
    if (risk && RISK_LABELS[risk]) evidence.push(`危険度: ${RISK_LABELS[risk]}`);

    const confidenceText = confidence === undefined
        ? '確信度はログに記録されていません'
        : `確信度 ${Math.round(confidence * 100)}%${confidence >= 0.8 ? '（かなり自信あり）' : confidence >= 0.6 ? '（おおむね自信あり）' : '（慎重に確認が必要）'}`;

    const haystack = safeStringify(context.roots).toLowerCase();
    const isScenario2 = /wf\.sulu_configuration_recovery|sulu configuration recovery|suluservicedown|desired_state|usecase[-_ ]?31|scenario[-_ ]?2|シナリオ2/.test(haystack);

    let tone = 'info';
    if (nextAction === 'require_approval' || requiredConfirm === true) tone = 'approval';
    else if (nextAction === 'reject' || risk === 'critical') tone = 'danger';
    else if (status === 'validated' || ['completed', 'success', 'succeeded'].includes(String(status || '').toLowerCase())) tone = 'success';
    else if (nextAction === 'ask_clarification' || risk === 'high') tone = 'warning';

    return {
        stage,
        action,
        observed,
        decision,
        reason: humanizeReason(rationale, requiredConfirm, risk, nextAction),
        humanAction,
        confidence,
        confidenceText,
        evidence: evidence.slice(0, 4),
        traceId: traceId || 'trace-idなし',
        contextId: contextId || '',
        node: context.node,
        nextAction: nextAction || '',
        risk: risk || '',
        workflowId: workflowId || '',
        status: status || '',
        promptVersion: promptVersion || '',
        promptHash: promptHash || '',
        policyVersion: policyVersion || '',
        dryRun,
        simulated,
        applied,
        isScenario2,
        tone,
    };
}

function isScenario2Event(event) {
    return buildDecisionExplanation(event).isScenario2;
}

export {
    buildDecisionExplanation,
    isScenario2Event,
    NEXT_ACTION_LABELS,
    CATEGORY_LABELS,
    RISK_LABELS,
};
