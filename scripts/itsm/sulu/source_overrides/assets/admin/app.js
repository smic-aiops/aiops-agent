// Add project specific javascript code and import of additional bundles here:

import viewRegistry from 'sulu-admin-bundle/containers/ViewRenderer/registries/viewRegistry';

import AiNodeMonitoring from './views/AiNodeMonitoring';
import IstmKpiMttr from './views/IstmKpiMttr';
import IstmKpiTriage from './views/IstmKpiTriage';
import IstmKpiLeadTime from './views/IstmKpiLeadTime';

viewRegistry.add('app.monitoring.ai_nodes', AiNodeMonitoring);
viewRegistry.add('app.itsm.kpi.mttr', IstmKpiMttr);
viewRegistry.add('app.itsm.kpi.triage', IstmKpiTriage);
viewRegistry.add('app.itsm.kpi.lead_time', IstmKpiLeadTime);

