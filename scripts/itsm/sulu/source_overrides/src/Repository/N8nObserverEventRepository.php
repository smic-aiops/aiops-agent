<?php

declare(strict_types=1);

namespace App\Repository;

use Doctrine\DBAL\Connection;

final class N8nObserverEventRepository
{
    public function __construct(private readonly Connection $connection)
    {
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    public function fetchEvents(?string $realm, ?string $workflow, ?string $node, ?int $sinceId, int $limit): array
    {
        $clauses = [];
        $params = [];

        if ($realm !== null) {
            $clauses[] = 'realm = :realm';
            $params['realm'] = $realm;
        }
        if ($workflow !== null) {
            $clauses[] = 'workflow = :workflow';
            $params['workflow'] = $workflow;
        }
        if ($node !== null) {
            $clauses[] = 'node = :node';
            $params['node'] = $node;
        }
        if ($sinceId !== null && $sinceId > 0) {
            $clauses[] = 'id > :since_id';
            $params['since_id'] = $sinceId;
        }

        $sql = 'SELECT id, received_at, realm, workflow, node, execution_id, payload FROM n8n_observer_events';
        if ($clauses) {
            $sql .= ' WHERE ' . implode(' AND ', $clauses);
        }
        $sql .= ' ORDER BY id DESC LIMIT ' . (int) $limit;

        $rows = $this->connection->fetchAllAssociative($sql, $params);

        foreach ($rows as &$row) {
            $payload = $row['payload'] ?? null;
            if (is_string($payload)) {
                $decoded = json_decode($payload, true);
                $row['payload'] = is_array($decoded) ? $decoded : $payload;
            }
        }
        unset($row);

        return $rows;
    }
}
