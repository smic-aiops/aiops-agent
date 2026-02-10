<?php

declare(strict_types=1);

namespace App\Service;

use Doctrine\DBAL\Connection;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Security\Core\Authentication\Token\Storage\TokenStorageInterface;

final class IstmSorRlsContext
{
    public function __construct(private readonly TokenStorageInterface $tokenStorage)
    {
    }

    public function apply(Connection $connection, Request $request): void
    {
        if ($connection->getDatabasePlatform()->getName() !== 'postgresql') {
            return;
        }

        $realmKey = $this->normalizeRealmKey(getenv('SULU_REALM') ?: null);
        $principalId = $this->resolvePrincipalId($request);

        $realmId = $this->tryResolveRealmId($connection, $realmKey);
        if ($realmId !== null) {
            $connection->executeStatement(
                "SELECT set_config('app.realm_id', :realm_id, false)",
                ['realm_id' => $realmId]
            );
        }

        $connection->executeStatement(
            "SELECT set_config('app.realm_key', :realm_key, false)",
            ['realm_key' => $realmKey]
        );
        $connection->executeStatement(
            "SELECT set_config('app.principal_id', :principal_id, false)",
            ['principal_id' => $principalId]
        );
    }

    private function tryResolveRealmId(Connection $connection, string $realmKey): ?string
    {
        try {
            $realmId = $connection->fetchOne(
                'SELECT itsm.get_realm_id(:realm_key)',
                ['realm_key' => $realmKey]
            );
            if (\is_string($realmId) && trim($realmId) !== '') {
                return $realmId;
            }
        } catch (\Throwable) {
        }

        try {
            $realmId = $connection->fetchOne(
                "SELECT id::text FROM itsm.realm WHERE lower(realm_key) = lower(:realm_key) LIMIT 1",
                ['realm_key' => $realmKey]
            );
            if (\is_string($realmId) && trim($realmId) !== '') {
                return $realmId;
            }
        } catch (\Throwable) {
        }

        return null;
    }

    private function normalizeRealmKey(?string $value): string
    {
        $trimmed = $value !== null ? trim($value) : '';
        return $trimmed === '' ? 'default' : $trimmed;
    }

    private function resolvePrincipalId(Request $request): string
    {
        $token = $this->tokenStorage->getToken();
        $user = $token?->getUser();

        if (\is_object($user) && method_exists($user, 'getUserIdentifier')) {
            $identifier = (string) $user->getUserIdentifier();
            if (trim($identifier) !== '') {
                return $identifier;
            }
        }

        $fallback = $request->headers->get('x-forwarded-user')
            ?: $request->headers->get('x-remote-user')
            ?: $request->getClientIp()
            ?: 'unknown';

        return (string) $fallback;
    }
}

