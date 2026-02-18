// @flow
import React from 'react';

import IstmKpiPage from '../IstmKpi/IstmKpiPage';

export default function IstmKpiTriage(): React$Node {
    return (
        <IstmKpiPage
            titleKey="app.itsm.kpi.triage"
            endpoint="/admin/api/itsm/kpi/triage"
            dashboardKey="triage_uid"
        />
    );
}

