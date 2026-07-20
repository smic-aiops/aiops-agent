<?php

declare(strict_types=1);

namespace App\Controller;

use Sulu\Component\Security\Authorization\PermissionTypes;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;

trait IstmWritableControllerTrait
{
    protected function createResource(Request $request, string $resourceType): Response
    {
        $this->securityChecker->checkPermission(self::SECURITY_CONTEXT, PermissionTypes::ADD);
        $result = $this->coreWriter->dispatch($request, 'create', $resourceType);

        return $this->handleView($this->view($result['data'] ?? $result, ($result['ok'] ?? false) ? 201 : 422));
    }

    protected function updateResource(Request $request, string $resourceType, string $id): Response
    {
        $this->securityChecker->checkPermission(self::SECURITY_CONTEXT, PermissionTypes::EDIT);
        $result = $this->coreWriter->dispatch($request, 'update', $resourceType, $id);

        return $this->handleView($this->view($result['data'] ?? $result, ($result['ok'] ?? false) ? 200 : 422));
    }

    protected function deleteResource(Request $request, string $resourceType, string $id): Response
    {
        $this->securityChecker->checkPermission(self::SECURITY_CONTEXT, PermissionTypes::DELETE);
        $result = $this->coreWriter->dispatch($request, 'delete', $resourceType, $id);

        return $this->handleView($this->view($result, ($result['ok'] ?? false) ? 200 : 422));
    }
}
