// @flow
import React, {useCallback, useEffect, useMemo, useState} from 'react';

import Button from 'sulu-admin-bundle/components/Button';
import Input from 'sulu-admin-bundle/components/Input';
import {translate} from 'sulu-admin-bundle/utils/Translator/Translator';

type KpiConfig = {|
    grafana_url: ?string,
    dashboards: {|
        mttr_uid: ?string,
        triage_uid: ?string,
        lead_time_uid: ?string,
    |},
|};

type Props = {|
    titleKey: string,
    endpoint: string,
    dashboardKey: 'mttr_uid' | 'triage_uid' | 'lead_time_uid',
|};

function defaultDateRange(): {|from: string, to: string|} {
    const to = new Date();
    const from = new Date(to.getTime() - 30 * 24 * 60 * 60 * 1000);

    const toKey = to.toISOString().slice(0, 10);
    const fromKey = from.toISOString().slice(0, 10);
    return {from: fromKey, to: toKey};
}

function toEpochMs(dateKey: string, endOfDay: boolean): ?number {
    const raw = String(dateKey || '').trim();
    if (!raw) return undefined;
    const iso = endOfDay ? `${raw}T23:59:59.999Z` : `${raw}T00:00:00.000Z`;
    const dt = new Date(iso);
    if (Number.isNaN(dt.getTime())) return undefined;
    return dt.getTime();
}

function formatNumber(value: mixed, digits: number = 2): string {
    const num = Number(value);
    if (!Number.isFinite(num)) return '';
    return num.toFixed(digits);
}

export default function IstmKpiPage(props: Props): React$Node {
    const {titleKey, endpoint, dashboardKey} = props;

    const initialRange = useMemo(() => defaultDateRange(), []);
    const [from, setFrom] = useState<string>(initialRange.from);
    const [to, setTo] = useState<string>(initialRange.to);
    const [customerId, setCustomerId] = useState<string>('');

    const [config, setConfig] = useState<?KpiConfig>(undefined);
    const [result, setResult] = useState<mixed>(undefined);
    const [loading, setLoading] = useState<boolean>(false);
    const [error, setError] = useState<?string>(undefined);

    const grafanaLink = useMemo(() => {
        const base = (config && config.grafana_url)
            ? String(config.grafana_url).replace(/\/+$/, '')
            : '';
        const dashboards = config && config.dashboards ? config.dashboards : undefined;
        const rawUid = dashboards ? dashboards[dashboardKey] : undefined;
        const uid = rawUid ? String(rawUid) : '';
        if (!base || !uid) return undefined;

        const url = new URL(`${base}/d/${uid}/kpi`);
        const fromMs = toEpochMs(from, false);
        const toMs = toEpochMs(to, true);
        if (fromMs !== undefined) url.searchParams.set('from', String(fromMs));
        if (toMs !== undefined) url.searchParams.set('to', String(toMs));
        if (customerId.trim()) url.searchParams.set('var-customer_id', customerId.trim());
        return url.toString();
    }, [config, dashboardKey, from, to, customerId]);

    const buildApiUrl = useCallback((): string => {
        const url = new URL(endpoint, window.location.origin);
        if (from.trim()) url.searchParams.set('from', from.trim());
        if (to.trim()) url.searchParams.set('to', to.trim());
        if (customerId.trim()) url.searchParams.set('customer_id', customerId.trim());
        return url.toString();
    }, [endpoint, from, to, customerId]);

    const refresh = useCallback(async () => {
        setLoading(true);
        setError(undefined);

        try {
            if (!config) {
                const cfgRes = await fetch('/admin/api/itsm/kpi/config', {credentials: 'same-origin'});
                const cfgBody = await cfgRes.json();
                if (!cfgBody || cfgBody.ok !== true) {
                    throw new Error((cfgBody && cfgBody.error) ? String(cfgBody.error) : 'config_request_failed');
                }
                setConfig(cfgBody.data);
            }

            const url = buildApiUrl();
            const res = await fetch(url, {credentials: 'same-origin'});
            const body = await res.json();
            if (!body || body.ok !== true) {
                throw new Error((body && body.error) ? String(body.error) : 'request_failed');
            }
            setResult(body.data);
        } catch (e) {
            const msg = (e && typeof e === 'object' && e.message) ? String(e.message) : String(e);
            setError(msg);
        } finally {
            setLoading(false);
        }
    }, [buildApiUrl, config]);

    useEffect(() => {
        refresh();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    const summary = result && typeof result === 'object' ? result.summary : undefined;

    return (
        <div style={{padding: 20}}>
            <h1 style={{margin: '0 0 12px'}}>{translate(titleKey)}</h1>

            <div style={{display: 'flex', gap: 12, alignItems: 'center', flexWrap: 'wrap', marginBottom: 12}}>
                <div style={{minWidth: 160}}>
                    <Input
                        onChange={(v) => setFrom(v ? String(v).trim() : '')}
                        placeholder={translate('app.itsm.kpi.filter.from')}
                        value={from}
                    />
                </div>
                <div style={{minWidth: 160}}>
                    <Input
                        onChange={(v) => setTo(v ? String(v).trim() : '')}
                        placeholder={translate('app.itsm.kpi.filter.to')}
                        value={to}
                    />
                </div>
                <div style={{minWidth: 220}}>
                    <Input
                        onChange={(v) => setCustomerId(v ? String(v).trim() : '')}
                        placeholder={translate('app.itsm.kpi.filter.customer_id')}
                        value={customerId}
                    />
                </div>
                <Button onClick={refresh} skin="primary" disabled={loading}>
                    {translate('sulu_admin.apply')}
                </Button>
                <div style={{color: error ? '#d0021b' : '#666', fontSize: 12}}>
                    {loading ? translate('app.itsm.kpi.status.loading') : ''}
                    {error ? `${translate('app.itsm.kpi.status.error')}: ${error}` : ''}
                </div>
            </div>

            {grafanaLink ? (
                <div style={{marginBottom: 16}}>
                    <a href={grafanaLink} target="_blank" rel="noreferrer">
                        {translate('app.itsm.kpi.grafana.open')}
                    </a>
                    <div style={{marginTop: 8}}>
                        <iframe
                            src={grafanaLink}
                            title="grafana"
                            style={{width: '100%', height: 520, border: '1px solid #eee', borderRadius: 6}}
                        />
                    </div>
                </div>
            ) : (
                <div style={{marginBottom: 16, color: '#666', fontSize: 12}}>
                    {translate('app.itsm.kpi.grafana.not_configured')}
                </div>
            )}

            {summary && typeof summary === 'object' ? (
                <div style={{marginBottom: 16}}>
                    <h2 style={{margin: '0 0 8px', fontSize: 16}}>{translate('app.itsm.kpi.summary')}</h2>
                    <div style={{display: 'flex', gap: 16, flexWrap: 'wrap'}}>
                        <div style={{padding: 12, border: '1px solid #eee', borderRadius: 6, minWidth: 180}}>
                            <div style={{color: '#666', fontSize: 12}}>{translate('app.itsm.kpi.summary.count')}</div>
                            <div style={{fontSize: 20}}>
                                {String((summary.count !== undefined && summary.count !== null) ? summary.count : '')}
                            </div>
                        </div>
                        <div style={{padding: 12, border: '1px solid #eee', borderRadius: 6, minWidth: 180}}>
                            <div style={{color: '#666', fontSize: 12}}>{translate('app.itsm.kpi.summary.p50_minutes')}</div>
                            <div style={{fontSize: 20}}>{formatNumber(summary.p50_minutes)}</div>
                        </div>
                        <div style={{padding: 12, border: '1px solid #eee', borderRadius: 6, minWidth: 180}}>
                            <div style={{color: '#666', fontSize: 12}}>{translate('app.itsm.kpi.summary.p95_minutes')}</div>
                            <div style={{fontSize: 20}}>{formatNumber(summary.p95_minutes)}</div>
                        </div>
                    </div>
                </div>
            ) : null}

            <div style={{overflow: 'auto'}}>
                <h2 style={{margin: '0 0 8px', fontSize: 16}}>{translate('app.itsm.kpi.data')}</h2>
                <pre
                    style={{
                        fontSize: 12,
                        background: '#fafafa',
                        border: '1px solid #eee',
                        borderRadius: 6,
                        padding: 12,
                        whiteSpace: 'pre-wrap',
                        wordBreak: 'break-word',
                    }}
                >
                    {result ? JSON.stringify(result, null, 2) : ''}
                </pre>
            </div>
        </div>
    );
}
