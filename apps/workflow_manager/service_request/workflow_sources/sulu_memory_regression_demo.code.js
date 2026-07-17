const request = $json ?? {};
const headers = request.headers && typeof request.headers === 'object' ? request.headers : {};
const payload = request.body && typeof request.body === 'object' ? request.body : request;
const env = $env ?? {};

function clean(value) {
  return value === null || value === undefined ? '' : String(value).trim();
}

function truthy(value) {
  return ['1', 'true', 'yes', 'y', 'on', 'enabled'].includes(clean(value).toLowerCase());
}

function header(name) {
  const lower = name.toLowerCase();
  const key = Object.keys(headers).find((item) => String(item).toLowerCase() === lower);
  return key ? headers[key] : undefined;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function fail(statusCode, error, details = {}) {
  return [{ json: { ok: false, status_code: statusCode, error, ...details } }];
}

function iso(value) {
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

function eventKind(event) {
  const raw = clean(event.kind ?? event.event_type ?? event.type ?? event.detail?.event_type ?? event.detail?.kind).toLowerCase();
  const hay = `${raw} ${clean(event.alarm_name ?? event.alarmName ?? event.detail?.alarmName)} ${clean(event.message ?? event.detail?.message)}`.toLowerCase();
  if (hay.includes('outofmemory') || hay.includes('out_of_memory') || hay.includes('oom')) return 'oom';
  if (hay.includes('memory') || hay.includes('mem')) return 'memory_high';
  return raw || 'unknown';
}

function eventMetric(event) {
  const value = event.metric_value ?? event.value ?? event.detail?.metric_value ?? event.detail?.value ?? event.detail?.state?.value_number;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function eventTag(event) {
  return clean(event.image_tag ?? event.imageTag ?? event.detail?.image_tag ?? event.detail?.imageTag);
}

function eventService(event) {
  return clean(event.service ?? event.detail?.service ?? 'sulu').toLowerCase();
}

function eventRealm(event) {
  return clean(event.realm ?? event.tenant ?? event.detail?.realm ?? payload.realm ?? env.N8N_REALM ?? env.N8N_ENV_REALM);
}

const expectedToken = clean(env.N8N_WORKFLOWS_TOKEN);
const providedToken = clean(header('authorization') ?? header('x-aiops-workflows-token')).replace(/^bearer\s+/i, '').trim();
if (expectedToken && providedToken !== expectedToken) {
  return fail(401, 'invalid workflows token');
}

const dryRun = payload.dry_run === undefined && payload.dryRun === undefined
  ? true
  : truthy(payload.dry_run ?? payload.dryRun);
const realm = clean(payload.realm ?? payload.tenant ?? env.N8N_REALM ?? env.N8N_ENV_REALM);
const traceId = clean(payload.trace_id ?? payload.traceId ?? payload.correlation_id ?? payload.correlationId);
const service = clean(payload.service ?? 'sulu').toLowerCase();
const deployment = payload.deployment && typeof payload.deployment === 'object' ? payload.deployment : {};
const previousVersion = clean(deployment.previous_version ?? deployment.previousVersion ?? payload.previous_version ?? payload.previousVersion);
const latestVersion = clean(deployment.current_version ?? deployment.currentVersion ?? deployment.target_version ?? deployment.targetVersion ?? payload.latest_version ?? payload.latestVersion);
const fixedVersion = clean(payload.fixed_version ?? payload.fixedVersion ?? deployment.fixed_version ?? deployment.fixedVersion);
const deployedAt = iso(deployment.deployed_at ?? deployment.deployedAt);
const events = Array.isArray(payload.events) ? payload.events : [];

const missing = [];
if (!realm) missing.push('realm');
if (!traceId) missing.push('trace_id');
if (!previousVersion) missing.push('deployment.previous_version');
if (!latestVersion) missing.push('deployment.current_version');
if (!fixedVersion) missing.push('fixed_version');
if (!deployedAt) missing.push('deployment.deployed_at');
if (events.length < 3) missing.push('events[3+]');
if (missing.length) return fail(422, 'missing required input', { missing });

const normalizedEvents = events.map((event, index) => ({
  event_id: clean(event.event_id ?? event.id ?? `event-${index + 1}`),
  kind: eventKind(event),
  occurred_at: iso(event.occurred_at ?? event.time ?? event.timestamp),
  metric_value: eventMetric(event),
  service: eventService(event),
  realm: eventRealm(event),
  image_tag: eventTag(event) || latestVersion,
  raw: event
}));

const deploymentTime = Date.parse(deployedAt);
const windowMinutes = Number(payload.correlation_window_minutes ?? payload.correlationWindowMinutes ?? 30);
const windowMs = Math.max(1, windowMinutes) * 60 * 1000;
const relevantEvents = normalizedEvents.filter((event) => {
  const eventTime = Date.parse(event.occurred_at || '');
  return Number.isFinite(eventTime)
    && eventTime >= deploymentTime
    && eventTime <= deploymentTime + windowMs
    && event.realm === realm
    && event.service === service
    && event.image_tag === latestVersion;
});
const memoryEvents = relevantEvents
  .filter((event) => event.kind === 'memory_high' && Number(event.metric_value) >= 90)
  .sort((left, right) => Date.parse(left.occurred_at || 0) - Date.parse(right.occurred_at || 0));
const oomEvents = relevantEvents
  .filter((event) => event.kind === 'oom')
  .sort((left, right) => Date.parse(left.occurred_at || 0) - Date.parse(right.occurred_at || 0));

const distinctMemoryIds = new Set(memoryEvents.map((event) => event.event_id));
const evidenceChecks = {
  recent_deployment: Boolean(deployedAt && latestVersion && previousVersion),
  two_distinct_memory_events: distinctMemoryIds.size >= 2,
  memory_threshold_met: memoryEvents.length >= 2
    && memoryEvents.slice(0, 2).every((event) => Number(event.metric_value) >= 90),
  oom_detected: oomEvents.length >= 1,
  same_realm_service_image: memoryEvents.length >= 2 && oomEvents.length >= 1,
  within_correlation_window: memoryEvents.length >= 2 && oomEvents.length >= 1
};
const correlationPassed = Object.values(evidenceChecks).every(Boolean);
if (!correlationPassed) {
  return fail(422, 'events did not satisfy memory-regression correlation', {
    trace_id: traceId,
    checks: evidenceChecks,
    normalized_events: normalizedEvents
  });
}

const confidence = clamp(0.55
  + (evidenceChecks.two_distinct_memory_events ? 0.1 : 0)
  + (evidenceChecks.oom_detected ? 0.15 : 0)
  + (evidenceChecks.same_realm_service_image ? 0.1 : 0)
  + (evidenceChecks.recent_deployment ? 0.08 : 0), 0, 0.99);

const evidence = [
  {
    type: 'deployment',
    summary: `${previousVersion} から ${latestVersion} への承認済みデプロイ後に発生`,
    occurred_at: deployedAt,
    ref: clean(deployment.change_url ?? deployment.changeUrl ?? deployment.change_id ?? deployment.changeId) || null
  },
  ...memoryEvents.slice(0, 2).map((event) => ({
    type: 'metric',
    summary: `メモリ利用率 ${event.metric_value}%`,
    occurred_at: event.occurred_at,
    ref: event.event_id
  })),
  {
    type: 'oom',
    summary: `${latestVersion} のSulu taskでOutOfMemoryを検知`,
    occurred_at: oomEvents[0].occurred_at,
    ref: oomEvents[0].event_id
  }
];

const recoveryCandidates = [
  {
    rank: 1,
    id: 'rollback_previous_version',
    title: `${previousVersion}へロールバック`,
    rationale: '直近デプロイ後に同一image tagでメモリ高騰とOOMが連続しており、既知正常版への切戻しが最短の復旧策です。',
    risk_level: 'medium',
    risk_reasons: ['ECSローリング更新を伴う', '一時的な性能変動があり得る'],
    reversible: true,
    expected_minutes: 5,
    requires_approval: true,
    workflow_id: 'wf.sulu_version_deploy',
    params: { realm, image_tag: previousVersion, dry_run: dryRun, allow_service_change: !dryRun },
    evidence_refs: evidence.map((item) => item.ref).filter(Boolean)
  },
  {
    rank: 2,
    id: 'restart_latest_version',
    title: `${latestVersion}のtaskを再起動`,
    rationale: '短時間のサービス復帰は期待できますが、メモリ回帰が残るため再発可能性が高い暫定策です。',
    risk_level: 'low',
    risk_reasons: ['原因が残存し再発する可能性'],
    reversible: true,
    expected_minutes: 3,
    requires_approval: false,
    workflow_id: 'wf.sulu_service_control',
    params: { realm, action: 'restart' },
    evidence_refs: [oomEvents[0].event_id]
  },
  {
    rank: 3,
    id: 'manual_diagnostic_hold',
    title: '変更を停止して手動診断へエスカレーション',
    rationale: 'ロールバック不可または承認者不在の場合に、追加変更を止めてオンコールへ移管します。',
    risk_level: 'high',
    risk_reasons: ['ユーザー影響が継続', '復旧時間が長期化'],
    reversible: true,
    expected_minutes: null,
    requires_approval: false,
    workflow_id: null,
    params: { escalation: 'oncall' },
    evidence_refs: evidence.map((item) => item.ref).filter(Boolean)
  }
];

const defaultFixContent = `<?php\n\ndeclare(strict_types=1);\n\nnamespace App\\AIOpsDemo;\n\nfinal class MemorySafeReportIterator\n{\n    public static function chunks(iterable $rows, int $chunkSize = 100): \\Generator\n    {\n        $chunk = [];\n        foreach ($rows as $row) {\n            $chunk[] = $row;\n            if (count($chunk) >= $chunkSize) {\n                yield $chunk;\n                $chunk = [];\n            }\n        }\n        if ($chunk !== []) {\n            yield $chunk;\n        }\n    }\n}\n`;
const fixInput = payload.fix && typeof payload.fix === 'object' ? payload.fix : {};
const fixFiles = Array.isArray(fixInput.files) && fixInput.files.length
  ? fixInput.files
  : [{
      action: 'create',
      file_path: 'scripts/itsm/sulu/source_overrides/src/AIOpsDemo/MemorySafeReportIterator.php',
      content: defaultFixContent
    }];
for (const file of fixFiles) {
  const path = clean(file.file_path ?? file.path);
  if (!path || path.startsWith('/') || path.includes('..')) {
    return fail(422, 'unsafe fix file path', { file_path: path || null });
  }
  if (clean(file.content).length > 200000) {
    return fail(422, 'fix file content is too large', { file_path: path });
  }
}

const testIds = new Set(['composer_validate', 'phpunit', 'memory_regression', 'http_smoke']);
for (const file of fixFiles) {
  const path = clean(file.file_path ?? file.path).toLowerCase();
  if (path.includes('composer.')) testIds.add('dependency_audit');
  if (path.includes('config/') || path.endsWith('.yaml') || path.endsWith('.yml')) testIds.add('configuration_lint');
  if (path.includes('security') || path.includes('auth')) testIds.add('security_regression');
}
const testCatalog = {
  composer_validate: { name: 'Composer validation', command: 'composer validate --strict', category: 'static' },
  phpunit: { name: 'PHP unit tests', command: 'vendor/bin/phpunit', category: 'unit' },
  memory_regression: { name: 'Memory regression', command: 'vendor/bin/phpunit --testsuite memory-regression', category: 'performance' },
  http_smoke: { name: 'Sulu HTTP smoke', command: 'curl -fsS "$SULU_URL/health"', category: 'smoke' },
  dependency_audit: { name: 'Dependency audit', command: 'composer audit', category: 'security' },
  configuration_lint: { name: 'Configuration lint', command: 'bin/adminconsole lint:yaml config', category: 'static' },
  security_regression: { name: 'Security regression', command: 'vendor/bin/phpunit --testsuite security', category: 'security' }
};
const selectedTests = Array.from(testIds).map((id) => ({ id, ...testCatalog[id] }));

const approval = payload.approval && typeof payload.approval === 'object' ? payload.approval : {};
const approved = truthy(approval.approved);
const decisionId = clean(approval.decision_id ?? approval.decisionId);
const allowGitLabWrite = truthy(payload.allow_gitlab_write ?? payload.allowGitlabWrite);
const allowCi = truthy(payload.allow_ci ?? payload.allowCi);
const allowEcrPush = truthy(payload.allow_ecr_push ?? payload.allowEcrPush);
const allowServiceChange = truthy(payload.allow_service_change ?? payload.allowServiceChange);
const allowStateChange = truthy(payload.allow_state_change ?? payload.allowStateChange);
const executeRollback = truthy(payload.execute_rollback ?? payload.executeRollback);
const executeFixedDeploy = truthy(payload.execute_fixed_deploy ?? payload.executeFixedDeploy);
const createTicketChain = payload.create_ticket_chain === undefined && payload.createTicketChain === undefined
  ? true
  : truthy(payload.create_ticket_chain ?? payload.createTicketChain);
const postDeployVerified = truthy(payload.post_deploy_verified ?? payload.postDeployVerified);
const verificationId = clean(payload.verification_id ?? payload.verificationId);
if (allowStateChange && !executeFixedDeploy && !postDeployVerified) {
  return fail(422, 'state changes require execute_fixed_deploy=true or post_deploy_verified=true');
}
if (allowStateChange && postDeployVerified && !verificationId) {
  return fail(422, 'verification_id is required when post_deploy_verified=true');
}

const artifact = {
  dry_run: dryRun,
  project_id: null,
  service_project_id: null,
  code_project_path: clean(
    payload.gitlab?.code_project_path
      ?? payload.gitlab?.codeProjectPath
      ?? payload.gitlab?.project_path
      ?? payload.gitlab?.projectPath
  ),
  service_project_path: clean(
    payload.gitlab?.service_project_path
      ?? payload.gitlab?.serviceProjectPath
      ?? env.N8N_GITLAB_PROJECT_PATH
      ?? env.GITLAB_PROJECT_PATH
  ),
  fix_branch: clean(payload.gitlab?.fix_branch ?? payload.gitlab?.fixBranch) || `fix/sulu-memory-${traceId.slice(0, 12)}`,
  base_branch: clean(payload.gitlab?.base_branch ?? payload.gitlab?.baseBranch ?? 'main'),
  service_base_branch: clean(payload.gitlab?.service_base_branch ?? payload.gitlab?.serviceBaseBranch ?? 'main'),
  commit_id: dryRun ? `dry-run-${traceId.slice(0, 8)}` : null,
  mr: dryRun ? { iid: 101, web_url: 'https://gitlab.example/demo/sulu/-/merge_requests/101', state: 'opened' } : null,
  rfc: dryRun ? { iid: 204, web_url: 'https://gitlab.example/demo/service-management/-/issues/204', state: 'opened', assessment_recorded: true, approval_recorded: false } : null,
  pipeline: dryRun ? { id: 303, status: 'success', web_url: 'https://gitlab.example/demo/sulu/-/pipelines/303' } : null,
  source_mirror: {
    status: dryRun ? 'planned' : 'not_checked',
    source_ref: null,
    expected_commit_sha: null,
    resolved_commit_sha: null,
    ref_api_url: null
  },
  cmdb: { status: dryRun ? 'planned' : 'not_started', version: fixedVersion },
  tickets: {
    status: dryRun ? 'planned' : 'not_started',
    closed_iids: [],
    records: dryRun ? {
      incident: { iid: 201, web_url: 'https://gitlab.example/demo/service-management/-/issues/201', state: 'opened' },
      emergency_change: { iid: 202, web_url: 'https://gitlab.example/demo/service-management/-/issues/202', state: 'opened' },
      problem: { iid: 203, web_url: 'https://gitlab.example/demo/service-management/-/issues/203', state: 'opened' },
      permanent_change: { iid: 204, web_url: 'https://gitlab.example/demo/service-management/-/issues/204', state: 'opened' }
    } : {}
  },
  kedb: dryRun ? { status: 'planned', issue_iid: 404, qdrant_sync: 'planned', sor_sync: 'planned' } : { status: 'not_started' },
  workflow_dispatch: {}
};

const configuredResults = Array.isArray(payload.test_results) ? payload.test_results : [];
let testResults = configuredResults.length
  ? configuredResults
  : selectedTests.map((test) => ({ id: test.id, status: dryRun ? 'passed' : 'pending', duration_seconds: dryRun ? 3 : null }));

const gitlabBase = clean(payload.gitlab?.api_base_url ?? payload.gitlab?.apiBaseUrl ?? env.GITLAB_API_BASE_URL).replace(/\/+$/, '');
const gitlabToken = clean(header('x-aiops-gitlab-token') ?? env.GITLAB_ADMIN_TOKEN ?? env.GITLAB_TOKEN);
const buildSource = payload.build_source && typeof payload.build_source === 'object' ? payload.build_source : {};
const buildSourceRef = clean(buildSource.source_ref ?? buildSource.sourceRef) || artifact.fix_branch;
const buildSourceApiBase = clean(
  buildSource.api_base_url
    ?? buildSource.apiBaseUrl
    ?? env.SULU_IMAGE_BUILDER_SOURCE_API_BASE_URL
    ?? 'https://api.github.com/repos/smic-aiops/aiops-agent'
).replace(/\/+$/, '');
const encodedBuildSourceRefPath = buildSourceRef
  .split('/')
  .map((segment) => encodeURIComponent(segment))
  .join('/');
const buildSourceRefApiUrl = clean(buildSource.ref_api_url ?? buildSource.refApiUrl)
  || `${buildSourceApiBase}/git/ref/heads/${encodedBuildSourceRefPath}`;
const buildSourceToken = clean(header('x-aiops-source-token') ?? env.SULU_IMAGE_BUILDER_SOURCE_TOKEN ?? env.GITHUB_TOKEN);
artifact.source_mirror.source_ref = buildSourceRef;
artifact.source_mirror.expected_commit_sha = artifact.commit_id;
artifact.source_mirror.ref_api_url = buildSourceRefApiUrl;
const webhookOrigin = clean(
  payload.webhook_base_url
    ?? payload.webhookBaseUrl
    ?? env.N8N_WEBHOOK_BASE_URL
    ?? env.N8N_PUBLIC_API_BASE_URL
)
  .replace(/\/+$/, '')
  .replace(/\/api\/v1$/, '');
const webhookBase = webhookOrigin
  ? (webhookOrigin.endsWith('/webhook') ? webhookOrigin : `${webhookOrigin}/webhook`)
  : '';

async function httpRequest(method, url, body = undefined, extra = {}) {
  const options = { method, url, json: true, timeout: extra.timeout ?? 60000 };
  if (body !== undefined) options.body = body;
  if (extra.qs) options.qs = extra.qs;
  if (extra.headers) options.headers = extra.headers;
  return await this.helpers.httpRequest(options);
}

async function gitlabRequest(method, suffix, body = undefined, qs = undefined) {
  const attempts = method === 'GET' ? 4 : 1;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      return await httpRequest.call(this, method, `${gitlabBase}${suffix}`, body, {
        qs,
        headers: { 'PRIVATE-TOKEN': gitlabToken, 'Content-Type': 'application/json' }
      });
    } catch (error) {
      const status = Number(error?.statusCode ?? error?.response?.statusCode ?? error?.response?.status);
      if (![429, 502, 503, 504].includes(status) || attempt + 1 >= attempts) throw error;
      await new Promise((resolve) => setTimeout(resolve, 1000 * (attempt + 1)));
    }
  }
  throw new Error(`GitLab request failed after retries: ${method} ${suffix}`);
}

async function ignoreAlreadyExists(promise) {
  try {
    return await promise;
  } catch (error) {
    const status = error?.statusCode ?? error?.response?.statusCode ?? error?.response?.status;
    if (Number(status) === 400 || Number(status) === 409) return null;
    throw error;
  }
}

if (!dryRun) {
  const liveMissing = [];
  if (!allowGitLabWrite) liveMissing.push('allow_gitlab_write=true');
  if (!gitlabBase) liveMissing.push('GITLAB_API_BASE_URL');
  if (!gitlabToken) liveMissing.push('GITLAB_ADMIN_TOKEN/GITLAB_TOKEN');
  if (!artifact.code_project_path) liveMissing.push('gitlab.code_project_path');
  if (!artifact.service_project_path) liveMissing.push('gitlab.service_project_path/N8N_GITLAB_PROJECT_PATH');
  if (liveMissing.length) return fail(424, 'live GitLab automation is not enabled', { missing: liveMissing, trace_id: traceId });

  const projectEncoded = encodeURIComponent(artifact.code_project_path);
  const serviceProjectEncoded = encodeURIComponent(artifact.service_project_path);
  const project = await gitlabRequest.call(this, 'GET', `/projects/${projectEncoded}`);
  const serviceProject = artifact.service_project_path === artifact.code_project_path
    ? project
    : await gitlabRequest.call(this, 'GET', `/projects/${serviceProjectEncoded}`);
  artifact.project_id = project.id;
  artifact.service_project_id = serviceProject.id;

  await ignoreAlreadyExists(gitlabRequest.call(this, 'POST', `/projects/${projectEncoded}/repository/branches`, {
    branch: artifact.fix_branch,
    ref: artifact.base_branch
  }));

  const actions = fixFiles.map((file) => ({
    action: clean(file.action || 'create'),
    file_path: clean(file.file_path ?? file.path),
    content: String(file.content ?? ''),
    encoding: 'text'
  }));
  const commit = await gitlabRequest.call(this, 'POST', `/projects/${projectEncoded}/repository/commits`, {
    branch: artifact.fix_branch,
    commit_message: clean(fixInput.commit_message) || `Fix Sulu memory regression (${traceId})`,
    actions
  });
  artifact.commit_id = commit.id ?? commit.short_id ?? null;
  artifact.source_mirror.expected_commit_sha = artifact.commit_id;

  let mr = await ignoreAlreadyExists(gitlabRequest.call(this, 'POST', `/projects/${projectEncoded}/merge_requests`, {
    source_branch: artifact.fix_branch,
    target_branch: artifact.base_branch,
    title: `[AIOps] Fix Sulu memory regression ${latestVersion}`,
    description: `trace_id: ${traceId}\n\nGenerated from correlated memory and OOM events.`,
    remove_source_branch: true
  }));
  if (!mr) {
    const existing = await gitlabRequest.call(this, 'GET', `/projects/${projectEncoded}/merge_requests`, undefined, {
      state: 'opened', source_branch: artifact.fix_branch, target_branch: artifact.base_branch
    });
    mr = Array.isArray(existing) ? existing[0] : null;
  }
  artifact.mr = mr ? { iid: mr.iid, web_url: mr.web_url, state: mr.state } : null;

  if (createTicketChain) {
    const incident = await gitlabRequest.call(this, 'POST', `/projects/${serviceProjectEncoded}/issues`, {
      title: `[INC] Sulu ${latestVersion} memory exhaustion`,
      description: [
        '## 事象', 'メモリ高騰2件の後にOutOfMemoryを検知。', '',
        '## 相関', `${previousVersion}から${latestVersion}への直近デプロイ後${windowMinutes}分以内。`, '',
        `trace_id: ${traceId}`
      ].join('\n'),
      labels: 'ITSM/インシデント管理,種別：インシデント,状態/In Progress,サービス：sulu'
    });
    artifact.tickets.records.incident = { iid: incident.iid, web_url: incident.web_url, state: incident.state };

    const emergencyChange = await gitlabRequest.call(this, 'POST', `/projects/${serviceProjectEncoded}/issues`, {
      title: `[Emergency Change] Sulu rollback to ${previousVersion}`,
      description: [
        '## 目的', `${latestVersion}から既知正常版${previousVersion}へロールバックする。`, '',
        '## 関連Incident', incident.web_url || `#${incident.iid}`, '',
        '## ロールバック', `再適用先: ${latestVersion}`, '',
        `trace_id: ${traceId}`
      ].join('\n'),
      labels: 'ITSM/変更管理,種別：変更,緊急変更,状態/New,サービス：sulu'
    });
    artifact.tickets.records.emergency_change = { iid: emergencyChange.iid, web_url: emergencyChange.web_url, state: emergencyChange.state };

    const problem = await gitlabRequest.call(this, 'POST', `/projects/${serviceProjectEncoded}/issues`, {
      title: `[PRB] Sulu ${latestVersion} memory regression`,
      description: [
        '## 関連Incident', incident.web_url || `#${incident.iid}`, '',
        '## 関連Emergency Change', emergencyChange.web_url || `#${emergencyChange.iid}`, '',
        '## 原因仮説', `${latestVersion}への更新に起因するメモリ回帰。`, '',
        '## 暫定回避策', `${previousVersion}を維持する。`, '',
        `trace_id: ${traceId}`
      ].join('\n'),
      labels: 'ITSM/問題管理,種別：問題,状態/In Progress,サービス：sulu'
    });
    artifact.tickets.records.problem = { iid: problem.iid, web_url: problem.web_url, state: problem.state };
    artifact.tickets.status = 'opened';
  }

  const rfcDescription = [
    '## 対象サービス', 'Sulu', '',
    '## 現行バージョン', previousVersion, '',
    '## 修正対象バージョン', latestVersion, '',
    '## 修正イメージタグ', fixedVersion, '',
    '## 修正ソースref', artifact.fix_branch, '',
    '## 原因仮説', `${latestVersion}の更新に起因するメモリ回帰`, '',
    '## 影響・テスト・リスク',
    `- 影響CI: Sulu ECS Service / ALB target`,
    `- 選択テスト: ${selectedTests.map((test) => test.name).join(', ')}`,
    `- ロールバック先: ${previousVersion}`,
    `- 関連Incident: ${artifact.tickets.records.incident?.web_url || 'external'}`,
    `- 関連Emergency Change: ${artifact.tickets.records.emergency_change?.web_url || 'external'}`,
    `- 関連Problem: ${artifact.tickets.records.problem?.web_url || 'external'}`,
    `- code MR: ${artifact.mr?.web_url || 'not-created'}`,
    `- trace_id: ${traceId}`
  ].join('\n');
  const rfc = await gitlabRequest.call(this, 'POST', `/projects/${serviceProjectEncoded}/issues`, {
    title: `[RFC] Sulu ${fixedVersion} memory regression fix`,
    description: rfcDescription,
    labels: 'ITSM/変更管理,種別：変更,状態/New'
  });
  artifact.rfc = {
    iid: rfc.iid,
    web_url: rfc.web_url,
    state: rfc.state,
    assessment_recorded: false,
    approval_recorded: false
  };
  artifact.tickets.records.permanent_change = { ...artifact.rfc };
  if (artifact.mr?.iid) {
    await gitlabRequest.call(this, 'POST', `/projects/${projectEncoded}/merge_requests/${artifact.mr.iid}/notes`, {
      body: `Service-management RFC: ${artifact.rfc.web_url}\ntrace_id: ${traceId}`
    });
    artifact.mr.rfc_link_recorded = true;
  }

  if (allowCi) {
    const pipeline = await gitlabRequest.call(this, 'POST', `/projects/${projectEncoded}/pipeline`, {
      ref: artifact.fix_branch,
      variables: [
        { key: 'AIOPS_TRACE_ID', value: traceId },
        { key: 'AIOPS_SELECTED_TESTS', value: selectedTests.map((test) => test.id).join(',') }
      ]
    });
    artifact.pipeline = { id: pipeline.id, status: pipeline.status, web_url: pipeline.web_url };
    if (truthy(payload.wait_for_ci ?? payload.waitForCi)) {
      const attempts = clamp(Number(payload.ci_poll_attempts ?? 40), 1, 100);
      const intervalMs = clamp(Number(payload.ci_poll_interval_ms ?? 3000), 500, 15000);
      const terminal = new Set(['success', 'failed', 'canceled', 'skipped', 'manual']);
      let current = pipeline;
      for (let attempt = 0; attempt < attempts && !terminal.has(clean(current.status).toLowerCase()); attempt += 1) {
        await new Promise((resolve) => setTimeout(resolve, intervalMs));
        current = await gitlabRequest.call(this, 'GET', `/projects/${projectEncoded}/pipelines/${pipeline.id}`);
      }
      artifact.pipeline = { id: current.id, status: current.status, web_url: current.web_url };
    }
    const pipelinePassed = clean(artifact.pipeline.status).toLowerCase() === 'success';
    testResults = selectedTests.map((test) => ({
      id: test.id,
      status: pipelinePassed ? 'passed' : (['failed', 'canceled'].includes(clean(artifact.pipeline.status).toLowerCase()) ? 'failed' : 'pending'),
      duration_seconds: null
    }));
  }
}

const failedTests = testResults.filter((test) => test.status === 'failed');
const pendingTests = testResults.filter((test) => !['passed', 'failed', 'skipped'].includes(test.status));
const allRequiredTestsPassed = failedTests.length === 0 && pendingTests.length === 0 && testResults.length >= selectedTests.length;
const riskFactors = [
  { id: 'base_change_risk', score_delta: 42, rationale: 'Suluのコード変更とローリングデプロイを伴う基礎リスク' },
  { id: 'changed_files', score_delta: Math.min(12, fixFiles.length * 3), rationale: `${fixFiles.length}ファイルの変更` },
  { id: 'correlation_confidence', score_delta: confidence < 0.9 ? 5 : 0, rationale: `相関confidence=${confidence}` },
  { id: 'failed_tests', score_delta: failedTests.length * 25, rationale: `${failedTests.length}件のテスト失敗` },
  { id: 'pending_tests', score_delta: pendingTests.length ? 15 : 0, rationale: `${pendingTests.length}件のテスト未完了` },
  { id: 'all_tests_passed', score_delta: allRequiredTestsPassed ? -12 : 0, rationale: allRequiredTestsPassed ? '全必須テスト合格' : '必須テスト未完了' }
];
let riskScore = 42;
riskScore += Math.min(12, fixFiles.length * 3);
riskScore += confidence < 0.9 ? 5 : 0;
riskScore += failedTests.length * 25;
riskScore += pendingTests.length ? 15 : 0;
riskScore -= allRequiredTestsPassed ? 12 : 0;
riskScore = clamp(Math.round(riskScore), 0, 100);
const riskLevel = riskScore <= 30 ? 'low' : (riskScore <= 60 ? 'medium' : 'high');
const executionReady = approved && Boolean(decisionId) && allRequiredTestsPassed && riskLevel !== 'high';

if (!dryRun && artifact.rfc?.iid) {
  const serviceProjectEncoded = encodeURIComponent(artifact.service_project_path);
  const assessmentNote = [
    '## AIOps CI・リスク評価',
    '',
    `- trace_id: ${traceId}`,
    `- code project: ${artifact.code_project_path}`,
    `- merge request: ${artifact.mr?.web_url || 'not-created'}`,
    `- pipeline: ${artifact.pipeline?.web_url || 'not-started'}`,
    `- pipeline status: ${artifact.pipeline?.status || 'not-started'}`,
    `- selected tests: ${selectedTests.map((test) => test.id).join(', ')}`,
    `- required tests passed: ${allRequiredTestsPassed}`,
    `- risk score: ${riskScore}`,
    `- risk level: ${riskLevel}`,
    `- risk factors: ${riskFactors.filter((factor) => factor.score_delta !== 0).map((factor) => `${factor.id}(${factor.score_delta >= 0 ? '+' : ''}${factor.score_delta})`).join(', ')}`,
    `- source ref: ${buildSourceRef}`
  ].join('\n');
  await gitlabRequest.call(this, 'POST', `/projects/${serviceProjectEncoded}/issues/${artifact.rfc.iid}/notes`, {
    body: assessmentNote
  });
  artifact.rfc.assessment_recorded = true;

  if (executionReady) {
    await gitlabRequest.call(this, 'POST', `/projects/${serviceProjectEncoded}/issues/${artifact.rfc.iid}/notes`, {
      body: `/approve\n\nCAB approved\nAIOps CAB decision_id: ${decisionId}\ntrace_id: ${traceId}\nrisk_score: ${riskScore}\npipeline: ${artifact.pipeline?.web_url || 'not-started'}`
    });
    const approvedIssue = await gitlabRequest.call(this, 'PUT', `/projects/${serviceProjectEncoded}/issues/${artifact.rfc.iid}`, {
      add_labels: '状態/Approved,CAB/Approved'
    });
    artifact.rfc.state = approvedIssue.state ?? artifact.rfc.state;
    artifact.rfc.approval_recorded = true;
  }
}

if (!dryRun && executionReady) {
  const authHeaders = expectedToken ? { Authorization: `Bearer ${expectedToken}` } : {};
  if ((allowEcrPush || executeRollback || executeFixedDeploy || allowStateChange) && !webhookBase) {
    return fail(424, 'N8N_WEBHOOK_BASE_URL is required for approved execution', { trace_id: traceId });
  }
  if (executeRollback) {
    if (!allowServiceChange) return fail(403, 'allow_service_change=true is required for rollback');
    artifact.workflow_dispatch.rollback = await httpRequest.call(this, 'POST', `${webhookBase}/sulu/version-deploy`, {
      realm,
      image_tag: previousVersion,
      rfc_issue_url: artifact.rfc?.web_url,
      dry_run: false,
      allow_service_change: true,
      correlation_id: traceId
    }, { headers: authHeaders, timeout: 180000 });
    if (!artifact.workflow_dispatch.rollback || artifact.workflow_dispatch.rollback.ok !== true || artifact.workflow_dispatch.rollback.applied !== true) {
      return fail(502, 'rollback dispatch did not confirm an applied deployment', {
        trace_id: traceId,
        dispatch_response: artifact.workflow_dispatch.rollback || null
      });
    }
  }
  if (allowEcrPush) {
    if (!artifact.commit_id) return fail(409, 'source mirror check requires the generated commit id', { trace_id: traceId });
    const sourceHeaders = { Accept: 'application/vnd.github+json', 'User-Agent': 'smic-aiops-sulu-source-mirror-check' };
    if (buildSourceToken) sourceHeaders.Authorization = `Bearer ${buildSourceToken}`;
    const sourceMirrorAttempts = clamp(Number(payload.source_mirror_poll_attempts ?? 60), 1, 150);
    const sourceMirrorIntervalMs = clamp(Number(payload.source_mirror_poll_interval_ms ?? 2000), 250, 10000);
    let sourceRefResponse = null;
    for (let attempt = 0; attempt < sourceMirrorAttempts; attempt += 1) {
      try {
        sourceRefResponse = await httpRequest.call(this, 'GET', buildSourceRefApiUrl, undefined, {
          headers: sourceHeaders,
          timeout: 30000
        });
        break;
      } catch (error) {
        const status = Number(error?.statusCode ?? error?.response?.statusCode ?? error?.response?.status);
        if (status !== 404) throw error;
        if (attempt + 1 < sourceMirrorAttempts) {
          await new Promise((resolve) => setTimeout(resolve, sourceMirrorIntervalMs));
        }
      }
    }
    if (!sourceRefResponse) {
      artifact.source_mirror.status = 'unresolved';
      return fail(409, 'source mirror ref did not resolve before timeout', {
        trace_id: traceId,
        source_ref: buildSourceRef,
        ref_api_url: buildSourceRefApiUrl,
        attempts: sourceMirrorAttempts
      });
    }
    const resolvedCommitSha = clean(
      sourceRefResponse?.commit?.sha
        ?? sourceRefResponse?.object?.sha
        ?? sourceRefResponse?.commit?.id
        ?? sourceRefResponse?.id
    );
    artifact.source_mirror.resolved_commit_sha = resolvedCommitSha || null;
    if (!resolvedCommitSha) {
      artifact.source_mirror.status = 'unresolved';
      return fail(409, 'source mirror ref did not resolve to a commit', {
        trace_id: traceId,
        source_ref: buildSourceRef,
        ref_api_url: buildSourceRefApiUrl
      });
    }
    if (resolvedCommitSha.toLowerCase() !== clean(artifact.commit_id).toLowerCase()) {
      artifact.source_mirror.status = 'sha_mismatch';
      return fail(409, 'source mirror commit does not match the generated GitLab commit', {
        trace_id: traceId,
        source_ref: buildSourceRef,
        expected_commit_sha: artifact.commit_id,
        resolved_commit_sha: resolvedCommitSha
      });
    }
    artifact.source_mirror.status = 'verified';
    artifact.workflow_dispatch.rfc_analysis = await httpRequest.call(this, 'POST', `${webhookBase}/sulu/rfc-source-analysis`, {
      realm,
      rfc_project_path: artifact.service_project_path,
      rfc_issue_iid: artifact.rfc?.iid,
      rfc: {
        iid: artifact.rfc?.iid,
        web_url: artifact.rfc?.web_url,
        title: `[RFC] Sulu ${fixedVersion} memory regression fix`,
        labels: ['RFC', '種別：変更', '状態/Approved'],
        description: `対象サービス: Sulu\n現行バージョン: ${previousVersion}\n修正対象バージョン: ${latestVersion}\n修正イメージタグ: ${fixedVersion}\n修正ソースref: ${artifact.fix_branch}`
      },
      base_version: previousVersion,
      target_version: latestVersion,
      image_tag: fixedVersion,
      source_ref: buildSourceRef,
      source_commit_sha: artifact.commit_id,
      push_images: true,
      allow_ecr_push: true,
      correlation_id: traceId
    }, { headers: authHeaders, timeout: 600000 });
    if (!artifact.workflow_dispatch.rfc_analysis || artifact.workflow_dispatch.rfc_analysis.ok !== true || artifact.workflow_dispatch.rfc_analysis.status !== 'built_and_pushed') {
      return fail(502, 'RFC analysis dispatch did not confirm an ECR build', {
        trace_id: traceId,
        dispatch_response: artifact.workflow_dispatch.rfc_analysis || null
      });
    }
  }
  if (executeFixedDeploy) {
    if (!allowServiceChange) return fail(403, 'allow_service_change=true is required for fixed deployment');
    artifact.workflow_dispatch.fixed_deploy = await httpRequest.call(this, 'POST', `${webhookBase}/sulu/version-deploy`, {
      realm,
      image_tag: fixedVersion,
      rfc_issue_url: artifact.rfc?.web_url,
      dry_run: false,
      allow_service_change: true,
      correlation_id: traceId
    }, { headers: authHeaders, timeout: 180000 });
    if (!artifact.workflow_dispatch.fixed_deploy || artifact.workflow_dispatch.fixed_deploy.ok !== true || artifact.workflow_dispatch.fixed_deploy.applied !== true) {
      return fail(502, 'fixed deployment dispatch did not confirm an applied deployment', {
        trace_id: traceId,
        dispatch_response: artifact.workflow_dispatch.fixed_deploy || null
      });
    }
  }
  if (allowStateChange) {
    const projectEncoded = encodeURIComponent(artifact.service_project_path);
    const suppliedTicketIids = Object.values(payload.tickets ?? {})
      .map((value) => Number(typeof value === 'object' ? value.iid : value))
      .filter((value) => Number.isFinite(value));
    const generatedTicketIids = Object.values(artifact.tickets.records ?? {})
      .map((value) => Number(value?.iid))
      .filter((value) => Number.isFinite(value));
    const ticketIids = [...new Set([...suppliedTicketIids, ...generatedTicketIids])];
    for (const iid of ticketIids) {
      await gitlabRequest.call(this, 'PUT', `/projects/${projectEncoded}/issues/${iid}`, { state_event: 'close' });
      artifact.tickets.closed_iids.push(iid);
    }
    artifact.tickets.status = 'closed';

    const cmdbPath = clean(payload.cmdb?.file_path ?? payload.cmdb?.filePath ?? 'cmdb/sulu.md');
    let cmdbContent = '';
    let cmdbAction = 'create';
    try {
      const file = await gitlabRequest.call(this, 'GET', `/projects/${projectEncoded}/repository/files/${encodeURIComponent(cmdbPath)}`, undefined, { ref: artifact.service_base_branch });
      cmdbContent = file?.content ? Buffer.from(file.content, 'base64').toString('utf8') : '';
      cmdbAction = 'update';
    } catch (error) {
      const status = error?.statusCode ?? error?.response?.statusCode ?? error?.response?.status;
      if (Number(status) !== 404) throw error;
    }
    const versionPattern = /(^|\n)(current_version|現行バージョン)\s*[:：]\s*[^\n]*/i;
    cmdbContent = versionPattern.test(cmdbContent)
      ? cmdbContent.replace(versionPattern, `$1$2: ${fixedVersion}`)
      : `${cmdbContent.trim()}\n\ncurrent_version: ${fixedVersion}\nlast_change_trace_id: ${traceId}\n`;
    const cmdbMetadata = {
      last_change_trace_id: traceId,
      last_change_rfc: artifact.rfc?.web_url || '',
      last_verification_id: verificationId || `workflow/sulu-version-deploy/${traceId}`,
      last_verified_at: new Date().toISOString()
    };
    for (const [key, value] of Object.entries(cmdbMetadata)) {
      const pattern = new RegExp(`(^|\\n)${key}\\s*[:：]\\s*[^\\n]*`, 'i');
      cmdbContent = pattern.test(cmdbContent)
        ? cmdbContent.replace(pattern, `$1${key}: ${value}`)
        : `${cmdbContent.trim()}\n${key}: ${value}\n`;
    }
    const cmdbCommit = await gitlabRequest.call(this, 'POST', `/projects/${projectEncoded}/repository/commits`, {
      branch: artifact.service_base_branch,
      commit_message: `Sync Sulu CMDB after ${fixedVersion} deployment (${traceId})`,
      actions: [{ action: cmdbAction, file_path: cmdbPath, content: cmdbContent, encoding: 'text' }]
    });
    artifact.cmdb = {
      status: 'synced',
      version: fixedVersion,
      file_path: cmdbPath,
      commit_id: cmdbCommit.id ?? cmdbCommit.short_id ?? null,
      trace_id: traceId,
      verification_id: cmdbMetadata.last_verification_id,
      rfc_url: artifact.rfc?.web_url || null
    };

    const kedb = await gitlabRequest.call(this, 'POST', `/projects/${projectEncoded}/issues`, {
      title: `[Known Error] Sulu ${latestVersion} memory regression`,
      description: [
        '## Symptoms', 'Continuous memory utilization above 90% followed by OutOfMemory.', '',
        '## Cause', `Memory regression introduced after ${previousVersion} -> ${latestVersion}.`, '',
        '## Workaround', `Rollback to ${previousVersion}.`, '',
        '## Resolution', `Deploy ${fixedVersion} and verify memory regression tests.`, '',
        '## Related records',
        `- Incident: ${artifact.tickets.records.incident?.web_url || 'external'}`,
        `- Problem: ${artifact.tickets.records.problem?.web_url || 'external'}`,
        `- RFC: ${artifact.rfc?.web_url || 'external'}`,
        `- MR: ${artifact.mr?.web_url || 'external'}`, '',
        `trace_id: ${traceId}`
      ].join('\n'),
      labels: 'ITSM/問題管理,種別：問題,既知エラー,状態/Closed,サービス：sulu'
    });
    artifact.kedb = { status: 'registered', issue_iid: kedb.iid, issue_url: kedb.web_url, qdrant_sync: 'requested', sor_sync: 'requested' };

    if (artifact.service_project_id) {
      const sorSync = await httpRequest.call(this, 'POST', `${webhookBase}/gitlab/issue/backfill/sor`, {
        realm, project_ids: String(artifact.service_project_id), state: 'all', dry_run: false
      }, { headers: authHeaders, timeout: 180000 });
      if (sorSync?.ok === false) throw new Error(`SoR backfill failed: ${clean(sorSync.error) || 'unknown error'}`);
      const qdrantSync = await httpRequest.call(this, 'POST', `${webhookBase}/gitlab/issue/rag/sync/oq`, {
        project_paths: { service: artifact.service_project_path },
        env: { N8N_GITLAB_ISSUE_RAG_FORCE_FULL_SYNC: 'true', N8N_GITLAB_ISSUE_RAG_DRY_RUN: 'false' }
      }, { headers: authHeaders, timeout: 60000 });
      if (qdrantSync?.ok === false) throw new Error(`KEDB/Qdrant sync failed: ${clean(qdrantSync.error) || 'unknown error'}`);
      artifact.kedb.sor_sync = 'completed';
      artifact.kedb.qdrant_sync = 'completed';
    }
  }
}

const output = {
  ok: true,
  status_code: 200,
  workflow_id: 'wf.sulu_memory_regression_demo',
  schema_version: 'aiops.sulu_memory_regression_demo.v1',
  trace_id: traceId,
  dry_run: dryRun,
  correlation: {
    status: 'correlated',
    confidence,
    window_minutes: windowMinutes,
    hypothesis: `${latestVersion}への直近デプロイに起因するメモリ回帰`,
    checks: evidenceChecks,
    evidence,
    event_ids: relevantEvents.map((event) => event.event_id)
  },
  recovery: {
    schema_version: 'aiops.recovery_candidates.v1',
    selected_rank: 1,
    candidates: recoveryCandidates
  },
  change_automation: {
    fix_files: fixFiles.map((file) => ({ action: clean(file.action || 'create'), file_path: clean(file.file_path ?? file.path) })),
    branch: artifact.fix_branch,
    commit_id: artifact.commit_id,
    mr: artifact.mr,
    rfc: artifact.rfc
  },
  test_and_risk: {
    selected_tests: selectedTests,
    results: testResults,
    all_required_tests_passed: allRequiredTestsPassed,
    score: riskScore,
    level: riskLevel,
    factors: riskFactors,
    recommendation: riskLevel === 'high' ? 'reject_or_rework' : 'conditional_approval'
  },
  approval: {
    required: true,
    approved,
    decision_id: decisionId || null,
    execution_ready: executionReady,
    post_deploy_verified: postDeployVerified || Boolean(artifact.workflow_dispatch.fixed_deploy),
    verification_id: verificationId || null
  },
  artifacts: artifact,
  demo_screens: {
    video_1_correlation: {
      title: '複数情報の相関分析',
      status: 'ready',
      fields: ['deployment', 'memory_events', 'oom', 'confidence', 'evidence']
    },
    video_2_recovery: {
      title: '復旧策を優先順位付きで提示',
      status: 'ready',
      fields: ['rank', 'rationale', 'risk_level', 'reversible', 'requires_approval']
    },
    video_3_change: {
      title: '変更要求の自動生成と影響分析',
      status: 'ready',
      fields: ['fix_branch', 'merge_request', 'pipeline_url', 'rfc', 'selected_tests', 'risk_score', 'source_mirror']
    },
    video_4_closure: {
      title: 'CMDB・KEDB・プロセス連携',
      status: dryRun || artifact.cmdb.status === 'synced' ? 'ready' : 'pending',
      fields: ['cmdb', 'closed_tickets', 'kedb', 'sor_sync', 'qdrant_sync']
    }
  }
};

return [{ json: output }];
