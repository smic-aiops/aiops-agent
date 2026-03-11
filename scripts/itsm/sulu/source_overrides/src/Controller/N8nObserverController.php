<?php

declare(strict_types=1);

namespace App\Controller;

use App\Repository\N8nObserverEventRepository;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpKernel\Attribute\AsController;

#[AsController]
final class N8nObserverController
{
    public function events(Request $request, N8nObserverEventRepository $repository): JsonResponse
    {
        $limit = (int) $request->query->get('limit', 50);
        $limit = max(1, min(500, $limit));

        $sinceId = $request->query->get('since_id');
        $sinceId = $sinceId !== null ? (int) $sinceId : null;

        $realm = $this->normalizeFilter($request->query->get('realm'));
        $workflow = $this->normalizeFilter($request->query->get('workflow'));
        $node = $this->normalizeFilter($request->query->get('node'));

        $events = $repository->fetchEvents($realm, $workflow, $node, $sinceId, $limit);

        return new JsonResponse([
            'ok' => true,
            'data' => $events,
        ]);
    }

    public function ingest(Request $request, N8nObserverEventRepository $repository): JsonResponse
    {
        $expectedToken = $this->getObserverToken();
        if ($expectedToken === null) {
            return new JsonResponse([
                'ok' => false,
                'error' => 'observer_token_not_configured',
            ], 500);
        }

        $receivedToken = (string) $request->headers->get('X-Observer-Token', '');
        if ($receivedToken === '' || !hash_equals($expectedToken, $receivedToken)) {
            return new JsonResponse([
                'ok' => false,
                'error' => 'unauthorized',
            ], 401);
        }

        $raw = (string) $request->getContent();
        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) {
            return new JsonResponse([
                'ok' => false,
                'error' => 'invalid_json',
            ], 400);
        }

        $realm = $this->normalizeFilter($decoded['realm'] ?? null);
        $workflow = $this->normalizeFilter($decoded['workflow'] ?? null);
        $executionId = $this->normalizeFilter($decoded['execution_id'] ?? null);

        $event = $decoded['event'] ?? null;
        $eventObj = is_array($event) ? $event : [];
        $node = $this->normalizeFilter($eventObj['target'] ?? null)
            ?? $this->normalizeFilter($eventObj['source'] ?? null);

        $phase = $this->normalizeFilter($eventObj['phase'] ?? null);
        $items = $eventObj['items'] ?? null;
        $itemsList = is_array($items) ? $items : [];

        $normalizedPayload = [
            'kind' => $this->normalizeFilter($decoded['kind'] ?? null),
            'realm' => $realm,
            'workflow' => $workflow,
            'node' => $node,
            'execution_id' => $executionId,
            'phase' => $phase,
            'sent_at' => $this->normalizeFilter($decoded['sent_at'] ?? null),
            'input' => $phase === 'before' ? $itemsList : null,
            'output' => $phase === 'after' ? $itemsList : null,
            'raw' => $decoded,
        ];

        $id = $repository->insertEvent($realm, $workflow, $node, $executionId, $normalizedPayload);

        return new JsonResponse([
            'ok' => true,
            'id' => $id,
        ], 201);
    }

    private function normalizeFilter(mixed $value): ?string
    {
        if (!is_string($value)) {
            return null;
        }
        $trimmed = trim($value);
        return $trimmed === '' ? null : $trimmed;
    }

    private function getObserverToken(): ?string
    {
        $token = $_ENV['N8N_OBSERVER_TOKEN'] ?? null;
        if (!is_string($token)) {
            return null;
        }
        $token = trim($token);
        return $token === '' ? null : $token;
    }
}
