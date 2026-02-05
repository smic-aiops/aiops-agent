// Add project specific javascript code and import of additional bundles here:

import viewRegistry from 'sulu-admin-bundle/containers/ViewRenderer/registries/viewRegistry';

import AiNodeMonitoring from './views/AiNodeMonitoring';

viewRegistry.add('app.monitoring.ai_nodes', AiNodeMonitoring);
