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

    private function normalizeFilter(mixed $value): ?string
    {
        if (!is_string($value)) {
            return null;
        }
        $trimmed = trim($value);
        return $trimmed === '' ? null : $trimmed;
    }
}
