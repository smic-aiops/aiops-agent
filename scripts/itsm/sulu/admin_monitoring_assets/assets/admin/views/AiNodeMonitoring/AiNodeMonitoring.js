// @flow
import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';

import Button from 'sulu-admin-bundle/components/Button';
import Input from 'sulu-admin-bundle/components/Input';
import SingleSelect from 'sulu-admin-bundle/components/SingleSelect';
import {translate} from 'sulu-admin-bundle/utils/Translator/Translator';

import {buildDecisionExplanation} from './decisionTrace.mjs';

const DEFAULT_POLL_MS = 1500;
const DEFAULT_LIMIT = 100;

const TONE_COLORS = {
    info: {border: '#52a3d9', background: '#f5fbff', accent: '#1676a7'},
    approval: {border: '#d9a441', background: '#fffaf0', accent: '#996515'},
    warning: {border: '#e08a3e', background: '#fff8f2', accent: '#a9500b'},
    danger: {border: '#d95c5c', background: '#fff5f5', accent: '#a32222'},
    success: {border: '#53a66f', background: '#f4fbf6', accent: '#24713d'},
};

function safeJson(value: mixed): string {
    try {
        return JSON.stringify(value, null, 2);
    } catch (e) {
        return String(value);
    }
}

function formatTime(value: ?string): string {
    if (!value) return '';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value);
    return date.toLocaleTimeString('ja-JP', {hour: '2-digit', minute: '2-digit', second: '2-digit'});
}

type EventRow = {|
    id: number,
    received_at: string,
    realm: ?string,
    workflow: ?string,
    node: ?string,
    execution_id: ?string,
    payload: mixed,
|};

export default function AiNodeMonitoring(): React$Node {
    const titleKey = 'app.monitoring.ai_nodes';

    const [realm, setRealm] = useState<?string>(undefined);
    const [workflow, setWorkflow] = useState<?string>(undefined);
    const [node, setNode] = useState<?string>(undefined);
    const [limit, setLimit] = useState<number>(DEFAULT_LIMIT);
    const [pollMs, setPollMs] = useState<number>(DEFAULT_POLL_MS);
    const [viewMode, setViewMode] = useState<string>('story');
    const [scenarioFilter, setScenarioFilter] = useState<string>('scenario2');

    const [events, setEvents] = useState<Array<EventRow>>([]);
    const [status, setStatus] = useState<'' | 'ok' | 'error'>('');
    const [error, setError] = useState<?string>(undefined);
    const [loading, setLoading] = useState<boolean>(false);

    const lastIdRef = useRef<?number>(null);
    const timerRef = useRef<?IntervalID>(null);

    const buildUrl = useCallback(
        (): string => {
            const url = new URL('/admin/api/n8n/observer/events', window.location.origin);
            url.searchParams.set('limit', String(limit));
            if (realm) url.searchParams.set('realm', realm);
            if (workflow) url.searchParams.set('workflow', workflow);
            if (node) url.searchParams.set('node', node);
            if (lastIdRef.current !== null && lastIdRef.current !== undefined) {
                url.searchParams.set('since_id', String(lastIdRef.current));
            }
            return url.toString();
        },
        [limit, realm, workflow, node]
    );

    const refresh = useCallback(
        async () => {
            const url = buildUrl();
            setLoading(true);
            setError(undefined);

            try {
                const response = await fetch(url, {credentials: 'same-origin'});
                const body = await response.json();
                if (!body || body.ok !== true) {
                    throw new Error((body && body.error) ? String(body.error) : 'request_failed');
                }

                const data: Array<EventRow> = Array.isArray(body.data) ? body.data : [];
                if (data.length > 0) {
                    const ordered = [...data].sort((a, b) => (a.id ?? 0) - (b.id ?? 0));
                    setEvents((prev) => [...ordered.reverse(), ...prev].slice(0, 500));

                    for (const row of ordered) {
                        if (typeof row.id === 'number') {
                            lastIdRef.current = Math.max(lastIdRef.current ?? 0, row.id);
                        }
                    }
                }

                setStatus('ok');
            } catch (e) {
                setError(String(e?.message ?? e));
                setStatus('error');
            } finally {
                setLoading(false);
            }
        },
        [buildUrl]
    );

    const stop = useCallback(() => {
        if (timerRef.current) {
            clearInterval(timerRef.current);
            timerRef.current = null;
        }
    }, []);

    const start = useCallback(() => {
        stop();
        lastIdRef.current = null;
        setEvents([]);
        refresh();
        timerRef.current = setInterval(refresh, pollMs);
    }, [pollMs, refresh, stop]);

    useEffect(() => {
        start();
        return stop;
    }, [start, stop]);

    const pollOptions = useMemo(() => ([
        {label: '0.5s', value: 500},
        {label: '1.0s', value: 1000},
        {label: '1.5s', value: 1500},
        {label: '3.0s', value: 3000},
        {label: '5.0s', value: 5000},
    ]), []);

    const limitOptions = useMemo(() => ([
        {label: '20', value: 20},
        {label: '50', value: 50},
        {label: '100', value: 100},
        {label: '200', value: 200},
    ]), []);

    const viewOptions = useMemo(() => ([
        {label: 'やさしい判断実況', value: 'story'},
        {label: '技術ログ', value: 'technical'},
    ]), []);

    const scenarioOptions = useMemo(() => ([
        {label: 'シナリオ2', value: 'scenario2'},
        {label: 'すべて', value: 'all'},
    ]), []);

    const explained = useMemo(() => events.map((event) => ({
        event,
        explanation: buildDecisionExplanation(event),
    })), [events]);

    const scenarioTraceIds = useMemo(() => {
        const ids = new Set();
        for (const item of explained) {
            if (item.explanation.isScenario2) ids.add(item.explanation.traceId);
        }
        return ids;
    }, [explained]);

    const filtered = useMemo(() => {
        if (scenarioFilter !== 'scenario2') return explained;
        return explained.filter((item) => item.explanation.isScenario2 || scenarioTraceIds.has(item.explanation.traceId));
    }, [explained, scenarioFilter, scenarioTraceIds]);

    const timeline = useMemo(() => [...filtered].reverse().slice(-120), [filtered]);
    const latest = timeline.length > 0 ? timeline[timeline.length - 1].explanation : undefined;

    return (
        <div style={{padding: 20, color: '#222'}}>
            <h1 style={{margin: '0 0 6px'}}>{translate(titleKey)}</h1>
            <div style={{marginBottom: 16, color: '#555', lineHeight: 1.6}}>
                AIの秘密の思考を表示する画面ではありません。ログに残った事実、判断結果、適用ルールを、
                人が確認できるやさしい言葉へ置き換えて表示します。
            </div>

            <div style={{display: 'flex', gap: 12, alignItems: 'center', flexWrap: 'wrap', marginBottom: 14}}>
                <div style={{minWidth: 190}}>
                    <SingleSelect onChange={(v) => setViewMode(String(v))} options={viewOptions} value={viewMode} />
                </div>
                <div style={{minWidth: 150}}>
                    <SingleSelect onChange={(v) => setScenarioFilter(String(v))} options={scenarioOptions} value={scenarioFilter} />
                </div>
                <div style={{minWidth: 180}}>
                    <Input
                        onChange={(v) => setRealm(v ? String(v).trim() || undefined : undefined)}
                        placeholder={translate('app.monitoring.filter.realm')}
                        value={realm}
                    />
                </div>
                <div style={{minWidth: 220}}>
                    <Input
                        onChange={(v) => setWorkflow(v ? String(v).trim() || undefined : undefined)}
                        placeholder={translate('app.monitoring.filter.workflow')}
                        value={workflow}
                    />
                </div>
                <div style={{minWidth: 200}}>
                    <Input
                        onChange={(v) => setNode(v ? String(v).trim() || undefined : undefined)}
                        placeholder={translate('app.monitoring.filter.node')}
                        value={node}
                    />
                </div>
                <div style={{minWidth: 105}}>
                    <SingleSelect onChange={(v) => setLimit(Number(v))} options={limitOptions} value={limit} />
                </div>
                <div style={{minWidth: 105}}>
                    <SingleSelect onChange={(v) => setPollMs(Number(v))} options={pollOptions} value={pollMs} />
                </div>
                <Button onClick={start} skin="primary">{translate('app.monitoring.apply')}</Button>
                <div style={{color: error ? '#d0021b' : '#666', fontSize: 12}}>
                    {error ? `${translate('app.monitoring.status.error')}: ${error}` : (
                        status === 'ok' ? `● ライブ監視中（${pollMs / 1000}秒間隔）` : ''
                    )}
                    {loading ? ` ${translate('app.monitoring.status.loading')}` : ''}
                </div>
            </div>

            {viewMode === 'story' ? (
                <div>
                    {latest ? (
                        <div style={{display: 'flex', gap: 12, flexWrap: 'wrap', marginBottom: 18}}>
                            <div style={{flex: '1 1 220px', padding: 14, border: '1px solid #dfe5ea', borderRadius: 8}}>
                                <div style={{fontSize: 12, color: '#666'}}>いまの段階</div>
                                <div style={{fontSize: 20, fontWeight: 600, marginTop: 4}}>{latest.stage}</div>
                            </div>
                            <div style={{flex: '2 1 360px', padding: 14, border: '1px solid #dfe5ea', borderRadius: 8}}>
                                <div style={{fontSize: 12, color: '#666'}}>AIが決めたこと</div>
                                <div style={{fontSize: 17, fontWeight: 600, marginTop: 4}}>{latest.decision}</div>
                            </div>
                            <div style={{flex: '2 1 360px', padding: 14, border: '1px solid #dfe5ea', borderRadius: 8}}>
                                <div style={{fontSize: 12, color: '#666'}}>人にお願いすること</div>
                                <div style={{fontSize: 17, fontWeight: 600, marginTop: 4}}>{latest.humanAction}</div>
                            </div>
                        </div>
                    ) : null}

                    {timeline.length === 0 ? (
                        <div style={{padding: 28, border: '1px dashed #b8c2cc', borderRadius: 8, color: '#555'}}>
                            シナリオ2の判断ログを待っています。デモを開始すると、ここへ時系列で表示されます。
                        </div>
                    ) : (
                        <div>
                            {timeline.map(({event, explanation}, index) => {
                                const palette = TONE_COLORS[explanation.tone] || TONE_COLORS.info;
                                return (
                                    <div
                                        key={event.id}
                                        style={{
                                            display: 'grid',
                                            gridTemplateColumns: '42px minmax(0, 1fr)',
                                            gap: 12,
                                            marginBottom: 12,
                                        }}
                                    >
                                        <div
                                            style={{
                                                width: 34,
                                                height: 34,
                                                borderRadius: 17,
                                                background: palette.accent,
                                                color: '#fff',
                                                display: 'flex',
                                                alignItems: 'center',
                                                justifyContent: 'center',
                                                fontWeight: 700,
                                            }}
                                        >
                                            {index + 1}
                                        </div>
                                        <div style={{border: `1px solid ${palette.border}`, background: palette.background, borderRadius: 8, padding: 14}}>
                                            <div style={{display: 'flex', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap'}}>
                                                <div>
                                                    <span style={{fontSize: 16, fontWeight: 700, color: palette.accent}}>{explanation.stage}</span>
                                                    <span style={{fontSize: 12, color: '#666', marginLeft: 10}}>{explanation.node}</span>
                                                </div>
                                                <div style={{fontSize: 12, color: '#666'}}>
                                                    {formatTime(event.received_at)}　trace: {explanation.traceId}
                                                </div>
                                            </div>
                                            <div style={{marginTop: 10, lineHeight: 1.6}}>
                                                <div><strong>AIがしたこと：</strong>{explanation.action}</div>
                                                <div><strong>わかったこと：</strong>{explanation.observed}</div>
                                                <div><strong>判断：</strong>{explanation.decision}</div>
                                                <div><strong>理由：</strong>{explanation.reason}</div>
                                                <div><strong>人にお願いすること：</strong>{explanation.humanAction}</div>
                                                <div><strong>自信の目安：</strong>{explanation.confidenceText}</div>
                                            </div>
                                            {explanation.evidence.length > 0 ? (
                                                <div style={{marginTop: 10, fontSize: 12, color: '#4d5862'}}>
                                                    <strong>参考にした証拠：</strong>
                                                    <ul style={{margin: '5px 0 0 20px', padding: 0}}>
                                                        {explanation.evidence.map((item, evidenceIndex) => (
                                                            <li key={`${event.id}-${evidenceIndex}`} style={{wordBreak: 'break-all'}}>{item}</li>
                                                        ))}
                                                    </ul>
                                                </div>
                                            ) : null}
                                            <details style={{marginTop: 10}}>
                                                <summary style={{cursor: 'pointer', color: '#52616b'}}>技術者向けの情報を見る</summary>
                                                <pre style={{fontSize: 11, whiteSpace: 'pre-wrap', wordBreak: 'break-word', background: '#fff', padding: 10, borderRadius: 5}}>
                                                    {safeJson({explanation, payload: event.payload})}
                                                </pre>
                                            </details>
                                        </div>
                                    </div>
                                );
                            })}
                        </div>
                    )}
                </div>
            ) : (
                <div style={{overflow: 'auto'}}>
                    <table style={{width: '100%', borderCollapse: 'collapse', fontSize: 12}}>
                        <thead>
                            <tr>
                                <th style={{textAlign: 'left', borderBottom: '1px solid #ddd', padding: 6}}>{translate('app.monitoring.table.id')}</th>
                                <th style={{textAlign: 'left', borderBottom: '1px solid #ddd', padding: 6}}>{translate('app.monitoring.table.received')}</th>
                                <th style={{textAlign: 'left', borderBottom: '1px solid #ddd', padding: 6}}>{translate('app.monitoring.table.realm')}</th>
                                <th style={{textAlign: 'left', borderBottom: '1px solid #ddd', padding: 6}}>{translate('app.monitoring.table.workflow')}</th>
                                <th style={{textAlign: 'left', borderBottom: '1px solid #ddd', padding: 6}}>{translate('app.monitoring.table.node')}</th>
                                <th style={{textAlign: 'left', borderBottom: '1px solid #ddd', padding: 6}}>{translate('app.monitoring.table.execution')}</th>
                                <th style={{textAlign: 'left', borderBottom: '1px solid #ddd', padding: 6}}>{translate('app.monitoring.table.summary')}</th>
                                <th style={{textAlign: 'left', borderBottom: '1px solid #ddd', padding: 6}}>{translate('app.monitoring.table.payload')}</th>
                            </tr>
                        </thead>
                        <tbody>
                            {filtered.map(({event, explanation}) => {
                                const payload = event.payload || {};
                                const input = payload && typeof payload === 'object' ? payload.input : undefined;
                                const output = payload && typeof payload === 'object' ? payload.output : undefined;
                                return (
                                    <tr key={event.id}>
                                        <td style={{borderBottom: '1px solid #f0f0f0', padding: 6, verticalAlign: 'top'}}>{event.id}</td>
                                        <td style={{borderBottom: '1px solid #f0f0f0', padding: 6, verticalAlign: 'top'}}>{event.received_at}</td>
                                        <td style={{borderBottom: '1px solid #f0f0f0', padding: 6, verticalAlign: 'top'}}>{event.realm || ''}</td>
                                        <td style={{borderBottom: '1px solid #f0f0f0', padding: 6, verticalAlign: 'top'}}>{event.workflow || ''}</td>
                                        <td style={{borderBottom: '1px solid #f0f0f0', padding: 6, verticalAlign: 'top'}}>{explanation.node}</td>
                                        <td style={{borderBottom: '1px solid #f0f0f0', padding: 6, verticalAlign: 'top'}}>{event.execution_id || ''}</td>
                                        <td style={{borderBottom: '1px solid #f0f0f0', padding: 6, verticalAlign: 'top', minWidth: 260}}>
                                            <strong>{explanation.decision}</strong><br />
                                            <span style={{color: '#666'}}>{explanation.reason}</span>
                                        </td>
                                        <td style={{borderBottom: '1px solid #f0f0f0', padding: 6, verticalAlign: 'top', whiteSpace: 'pre', maxWidth: 620, overflow: 'auto'}}>
                                            {safeJson({input, output})}
                                        </td>
                                    </tr>
                                );
                            })}
                        </tbody>
                    </table>
                </div>
            )}
        </div>
    );
}
