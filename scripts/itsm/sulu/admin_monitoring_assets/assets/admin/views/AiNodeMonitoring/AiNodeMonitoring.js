// @flow
import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';

import Button from 'sulu-admin-bundle/components/Button';
import Input from 'sulu-admin-bundle/components/Input';
import SingleSelect from 'sulu-admin-bundle/components/SingleSelect';
import {translate} from 'sulu-admin-bundle/utils/Translator/Translator';

const DEFAULT_POLL_MS = 1500;
const DEFAULT_LIMIT = 50;

function safeJson(value: mixed): string {
    try {
        return JSON.stringify(value, null, 2);
    } catch (e) {
        return String(value);
    }
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

    return (
        <div style={{padding: 20}}>
            <h1 style={{margin: '0 0 12px'}}>
                {translate(titleKey)}
            </h1>

            <div style={{display: 'flex', gap: 12, alignItems: 'center', flexWrap: 'wrap', marginBottom: 12}}>
                <div style={{minWidth: 220}}>
                    <Input
                        onChange={(v) => setRealm(v ? String(v).trim() || undefined : undefined)}
                        placeholder={translate('app.monitoring.filter.realm')}
                        value={realm}
                    />
                </div>
                <div style={{minWidth: 260}}>
                    <Input
                        onChange={(v) => setWorkflow(v ? String(v).trim() || undefined : undefined)}
                        placeholder={translate('app.monitoring.filter.workflow')}
                        value={workflow}
                    />
                </div>
                <div style={{minWidth: 240}}>
                    <Input
                        onChange={(v) => setNode(v ? String(v).trim() || undefined : undefined)}
                        placeholder={translate('app.monitoring.filter.node')}
                        value={node}
                    />
                </div>
                <div style={{minWidth: 140}}>
                    <SingleSelect
                        onChange={(v) => setLimit(Number(v))}
                        options={limitOptions}
                        value={limit}
                    />
                </div>
                <div style={{minWidth: 140}}>
                    <SingleSelect
                        onChange={(v) => setPollMs(Number(v))}
                        options={pollOptions}
                        value={pollMs}
                    />
                </div>
                <Button onClick={start} skin="primary">
                    {translate('app.monitoring.apply')}
                </Button>
                <div style={{color: error ? '#d0021b' : '#666', fontSize: 12}}>
                    {error ? `${translate('app.monitoring.status.error')}: ${error}` : (
                        status === 'ok' ? translate('app.monitoring.status.ok') : ''
                    )}
                    {(lastIdRef.current !== null && lastIdRef.current !== undefined && !error)
                        ? ` (lastId=${lastIdRef.current})`
                        : ''}
                    {loading ? ` (${translate('app.monitoring.status.loading')})` : ''}
                </div>
            </div>

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
                            <th style={{textAlign: 'left', borderBottom: '1px solid #ddd', padding: 6}}>{translate('app.monitoring.table.payload')}</th>
                        </tr>
                    </thead>
                    <tbody>
                        {events.map((event) => {
                            const payload = event.payload || {};
                            const input = payload && typeof payload === 'object' ? payload.input : undefined;
                            const output = payload && typeof payload === 'object' ? payload.output : undefined;
                            const cell = safeJson({input, output});

                            return (
                                <tr key={event.id}>
                                    <td style={{borderBottom: '1px solid #f0f0f0', padding: 6, verticalAlign: 'top'}}>
                                        {event.id}
                                    </td>
                                    <td style={{borderBottom: '1px solid #f0f0f0', padding: 6, verticalAlign: 'top'}}>
                                        {event.received_at}
                                    </td>
                                    <td style={{borderBottom: '1px solid #f0f0f0', padding: 6, verticalAlign: 'top'}}>
                                        {event.realm || ''}
                                    </td>
                                    <td style={{borderBottom: '1px solid #f0f0f0', padding: 6, verticalAlign: 'top'}}>
                                        {event.workflow || ''}
                                    </td>
                                    <td style={{borderBottom: '1px solid #f0f0f0', padding: 6, verticalAlign: 'top'}}>
                                        {event.node || ''}
                                    </td>
                                    <td style={{borderBottom: '1px solid #f0f0f0', padding: 6, verticalAlign: 'top'}}>
                                        {event.execution_id || ''}
                                    </td>
                                    <td
                                        style={{
                                            borderBottom: '1px solid #f0f0f0',
                                            padding: 6,
                                            verticalAlign: 'top',
                                            whiteSpace: 'pre',
                                            maxWidth: 720,
                                            overflow: 'auto',
                                        }}
                                    >
                                        {cell}
                                    </td>
                                </tr>
                            );
                        })}
                    </tbody>
                </table>
            </div>
        </div>
    );
}
