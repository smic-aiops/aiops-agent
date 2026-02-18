// @flow
import React from 'react';

import IstmKpiPage from '../IstmKpi/IstmKpiPage';

export default function IstmKpiMttr(): React$Node {
    return (
        <IstmKpiPage
            titleKey="app.itsm.kpi.mttr"
            endpoint="/admin/api/itsm/kpi/mttr"
            dashboardKey="mttr_uid"
        />
    );
}

