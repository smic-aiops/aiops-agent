// @flow
import React from 'react';

import IstmKpiPage from '../IstmKpi/IstmKpiPage';

export default function IstmKpiLeadTime(): React$Node {
    return (
        <IstmKpiPage
            titleKey="app.itsm.kpi.lead_time"
            endpoint="/admin/api/itsm/kpi/lead-time"
            dashboardKey="lead_time_uid"
        />
    );
}

