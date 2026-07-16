<?php

declare(strict_types=1);

namespace App\Service;

use App\ListBuilder\IstmDoctrineListBuilderFactory;
use Symfony\Component\HttpFoundation\Request;

final class IstmCoreWriter
{
    public function __construct(
        private readonly IstmDoctrineListBuilderFactory $listBuilderFactory,
        private readonly IstmSorRlsContext $rlsContext,
    ) {
    }

    /** @return array<string, mixed> */
    public function dispatch(Request $request, string $action, string $resourceType, ?string $resourceId = null): array
    {
        $connection = $this->listBuilderFactory->getConnection();
        $this->rlsContext->apply($connection, $request);
        $realmKey = trim((string) (getenv('SULU_REALM') ?: 'default')) ?: 'default';
        $payload = $request->getContent() !== '' ? $request->toArray() : [];

        $encoded = $connection->fetchOne(
            'SELECT itsm.core_api_dispatch_v2(:realm, :action, :resource_type, CAST(:payload AS jsonb), CAST(:resource_id AS uuid), NULL, 50)::text',
            [
                'realm' => $realmKey,
                'action' => $action,
                'resource_type' => $resourceType,
                'payload' => json_encode($payload, JSON_THROW_ON_ERROR),
                'resource_id' => $resourceId,
            ]
        );
        $result = json_decode((string) $encoded, true, 512, JSON_THROW_ON_ERROR);

        return is_array($result) ? $result : ['ok' => false, 'error' => 'invalid SoR response'];
    }
}
