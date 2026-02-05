#!/usr/bin/env php
<?php

declare(strict_types=1);

use Doctrine\ORM\EntityManagerInterface;
use Sulu\Content\Domain\Model\WorkflowInterface;
use Sulu\Messenger\Infrastructure\Symfony\Messenger\FlushMiddleware\EnableFlushStamp;
use Sulu\Page\Application\Message\ApplyWorkflowTransitionPageMessage;
use Sulu\Page\Application\Message\CopyLocalePageMessage;
use Sulu\Page\Application\Message\CreatePageMessage;
use Sulu\Page\Application\Message\ModifyPageMessage;
use Sulu\Page\Domain\Model\PageInterface;
use Sulu\Page\Application\MessageHandler\CreatePageMessageHandler;
use Sulu\Route\Domain\Model\Route;
use Sulu\Route\Domain\Repository\RouteRepositoryInterface;
use Symfony\Component\DependencyInjection\ContainerInterface;
use Symfony\Component\Dotenv\Dotenv;
use Symfony\Component\Messenger\Envelope;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Messenger\Stamp\HandledStamp;

function stderr(string $message): void
{
    fwrite(STDERR, $message . PHP_EOL);
}

function requireFile(string $path): void
{
    if (!is_file($path)) {
        stderr("ERROR: File not found: {$path}");
        exit(2);
    }
}

function loadContainer(string $projectDir): ContainerInterface
{
    $autoload = $projectDir . '/vendor/autoload.php';
    requireFile($autoload);
    require $autoload;

    $env = $_SERVER['APP_ENV'] ?? getenv('APP_ENV') ?: 'prod';
    $debug = ($_SERVER['APP_DEBUG'] ?? getenv('APP_DEBUG') ?: '0') === '1';

    if (is_file($projectDir . '/.env')) {
        $dotenv = new Dotenv();
        $dotenv->bootEnv($projectDir . '/.env');
    }

    $kernelClass = 'App\\Kernel';
    if (!class_exists($kernelClass)) {
        stderr('ERROR: App\\Kernel not found (is this a Symfony app?)');
        exit(2);
    }

    /** @var \Symfony\Component\HttpKernel\KernelInterface $kernel */
    $contextRaw = $_SERVER['SULU_CONTEXT'] ?? getenv('SULU_CONTEXT') ?? '';
    $contextRaw = is_string($contextRaw) ? strtolower(trim($contextRaw)) : '';
    $defaultContext = defined($kernelClass . '::CONTEXT_ADMIN') ? constant($kernelClass . '::CONTEXT_ADMIN') : null;
    $websiteContext = defined($kernelClass . '::CONTEXT_WEBSITE') ? constant($kernelClass . '::CONTEXT_WEBSITE') : null;
    $context = $defaultContext;
    if ($contextRaw === 'website' && $websiteContext !== null) {
        $context = $websiteContext;
    }

    try {
        $ref = new \ReflectionClass($kernelClass);
        $ctor = $ref->getConstructor();
        if ($ctor && $ctor->getNumberOfParameters() >= 3 && $context !== null) {
            $kernel = $ref->newInstanceArgs([$env, $debug, $context]);
        } else {
            $kernel = $ref->newInstanceArgs([$env, $debug]);
        }
    } catch (\Throwable $e) {
        stderr('ERROR: Failed to construct Kernel: ' . $e->getMessage());
        exit(2);
    }
    $kernel->boot();

    /** @var ContainerInterface $container */
    $container = $kernel->getContainer();
    return $container;
}

function getMessageBus(ContainerInterface $container): MessageBusInterface
{
    $candidates = [
        MessageBusInterface::class,
        'messenger.bus.sulu_message_bus',
        'sulu_message_bus',
        'messenger.bus.default',
        'messenger.default_bus',
    ];

    foreach ($candidates as $id) {
        if ($container->has($id)) {
            $service = $container->get($id);
            if ($service instanceof MessageBusInterface) {
                return $service;
            }
        }
    }

    stderr('ERROR: Could not resolve Symfony MessageBus from container.');
    exit(2);
}

function dispatchWithFlush(MessageBusInterface $bus, object $message): mixed
{
    $envelope = new Envelope($message, [new EnableFlushStamp()]);
    $envelope = $bus->dispatch($envelope);
    $handled = $envelope->last(HandledStamp::class);
    return $handled ? $handled->getResult() : null;
}

function getRouteRepository(ContainerInterface $container): RouteRepositoryInterface
{
    $candidates = [
        RouteRepositoryInterface::class,
        'sulu_route.route_repository',
    ];

    foreach ($candidates as $id) {
        if ($container->has($id)) {
            $service = $container->get($id);
            if ($service instanceof RouteRepositoryInterface) {
                return $service;
            }
        }
    }

    stderr('ERROR: Could not resolve Sulu RouteRepository service from container.');
    exit(2);
}

function getEntityManager(ContainerInterface $container): EntityManagerInterface
{
    $candidates = [
        EntityManagerInterface::class,
        'doctrine.orm.entity_manager',
    ];
    foreach ($candidates as $id) {
        if ($container->has($id)) {
            $service = $container->get($id);
            if ($service instanceof EntityManagerInterface) {
                return $service;
            }
        }
    }

    stderr('ERROR: Could not resolve Doctrine EntityManager from container.');
    exit(2);
}

function readJsonFile(string $path): array
{
    requireFile($path);
    $raw = file_get_contents($path);
    if ($raw === false) {
        stderr("ERROR: Failed to read file: {$path}");
        exit(2);
    }
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        stderr("ERROR: Invalid JSON: {$path}");
        exit(2);
    }
    return $data;
}

function normalizePath(string $path): string
{
    $p = trim($path);
    if ($p === '') {
        return '/';
    }
    if ($p[0] !== '/') {
        $p = '/' . $p;
    }
    return $p;
}

function normalizeResourceSegment(string $segment, string $path): string
{
    $s = trim($segment);
    if ($s !== '') {
        if ($s[0] !== '/') {
            $s = '/' . $s;
        }
        return $s;
    }
    return normalizePath($path);
}

function findRouteOrNull(RouteRepositoryInterface $routeRepository, string $path, string $locale, ?string $webspace): ?Route
{
    $filters = [
        'slug' => $path,
        'locale' => $locale,
        'resourceKey' => PageInterface::RESOURCE_KEY,
    ];
    if ($webspace !== null && $webspace !== '') {
        $filters['webspace'] = $webspace;
    }

    return $routeRepository->findOneBy($filters);
}

function extractResourceId(Route $route): string
{
    $id = $route->getResourceId();
    if ($id !== '') {
        return $id;
    }

    stderr('ERROR: Could not extract resourceId from Route entity.');
    exit(2);
}

function buildPageData(array $page, string $locale, string $resourceSegment, array $navigationContexts, string $templateKey): array
{
    $data = [
        'locale' => $locale,
        'url' => $resourceSegment,
    ];

    if ($templateKey !== '') {
        $data['template'] = $templateKey;
    }

    if ($navigationContexts !== []) {
        $data['navigationContexts'] = $navigationContexts;
    }

    if (array_key_exists('title', $page) && is_string($page['title']) && $page['title'] !== '') {
        $data['title'] = $page['title'];
    }

    if (array_key_exists('lead', $page)) {
        $data['lead'] = $page['lead'];
    }

    if (array_key_exists('article', $page)) {
        $data['article'] = $page['article'];
    }

    return $data;
}

function updateAvailableLocales(EntityManagerInterface $entityManager, array $localesByEntityId): void
{
    if ($localesByEntityId === []) {
        return;
    }

    $connection = $entityManager->getConnection();
    foreach ($localesByEntityId as $entityId => $locales) {
        $unique = array_values(array_unique(array_filter(array_map('strval', $locales))));
        if ($unique === []) {
            continue;
        }
        sort($unique);
        $payload = json_encode($unique, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if ($payload === false) {
            stderr('ERROR: Failed to encode availablelocales for entity_id=' . $entityId);
            continue;
        }
        $connection->executeStatement(
            "update pa_page_dimension_contents set availablelocales = :locales::jsonb where pageuuid = :uuid and locale is null",
            ['locales' => $payload, 'uuid' => $entityId]
        );
    }
}

function main(array $argv): int
{
    $projectDir = getcwd();
    $dryRun = false;
    $jsonPath = '';
    foreach (array_slice($argv, 1) as $arg) {
        if ($arg === '--dry-run' || $arg === '-n') {
            $dryRun = true;
            continue;
        }
        if ($arg === '--help' || $arg === '-h') {
            stderr('Usage: replace_sulu_pages.php [--dry-run] <pages.json>');
            return 0;
        }
        if ($jsonPath === '') {
            $jsonPath = $arg;
        }
    }
    if ($jsonPath === '') {
        stderr('Usage: replace_sulu_pages.php [--dry-run] <pages.json>');
        return 2;
    }

    $input = readJsonFile($jsonPath);
    $pages = $input['pages'] ?? $input;
    if (!is_array($pages)) {
        stderr('ERROR: JSON must be an array or an object with "pages" array.');
        return 2;
    }

    if ($dryRun) {
        $plan = [];
        foreach ($pages as $page) {
            if (!is_array($page)) {
                continue;
            }
            $path = normalizePath((string) ($page['path'] ?? ''));
            $locale = (string) ($page['locale'] ?? ($_SERVER['SULU_LOCALE'] ?? 'en'));
            $webspace = isset($page['webspace']) ? (string) $page['webspace'] : ($_SERVER['SULU_WEBSPACE'] ?? 'website');
            $publish = array_key_exists('publish', $page) ? (bool) $page['publish'] : true;
            $createIfMissing = array_key_exists('create_if_missing', $page) ? (bool) $page['create_if_missing'] : false;
            $templateKey = (string) ($page['template'] ?? '');
            $plan[] = [
                'path' => $path,
                'locale' => $locale,
                'webspace' => $webspace,
                'publish' => $publish,
                'create_if_missing' => $createIfMissing,
                'template' => $templateKey,
            ];
        }
        echo json_encode(['ok' => true, 'dry_run' => true, 'project_dir' => $projectDir, 'pages' => $plan], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . PHP_EOL;
        return 0;
    }

    $container = loadContainer($projectDir);
    $messageBus = getMessageBus($container);
    $routeRepository = getRouteRepository($container);
    $entityManager = getEntityManager($container);

    $results = [];
    $localesByEntityId = [];
    foreach ($pages as $page) {
        if (!is_array($page)) {
            continue;
        }

        $path = normalizePath((string) ($page['path'] ?? ''));
        $locale = (string) ($page['locale'] ?? ($_SERVER['SULU_LOCALE'] ?? 'en'));
        $webspace = isset($page['webspace']) ? (string) $page['webspace'] : ($_SERVER['SULU_WEBSPACE'] ?? 'website');
        $publish = array_key_exists('publish', $page) ? (bool) $page['publish'] : true;
        $createIfMissing = array_key_exists('create_if_missing', $page) ? (bool) $page['create_if_missing'] : false;
        $fallbackLocale = '';
        if (isset($page['fallback_locale'])) {
            $fallbackLocale = (string) $page['fallback_locale'];
        } elseif (isset($page['source_locale'])) {
            $fallbackLocale = (string) $page['source_locale'];
        }
        $fallbackLocale = trim($fallbackLocale);
        $templateKey = (string) ($page['template'] ?? '');
        $resourceSegment = normalizeResourceSegment((string) ($page['resource_segment'] ?? ''), $path);
        $parentPath = normalizePath((string) ($page['parent_path'] ?? '/'));
        $navigationContexts = is_array($page['navigation_contexts'] ?? null) ? $page['navigation_contexts'] : ['main'];

        $data = buildPageData($page, $locale, $resourceSegment, $navigationContexts, $templateKey);

        if (count($data) <= 2 && !$createIfMissing) {
            $results[] = ['path' => $path, 'ok' => true, 'skipped' => true, 'reason' => 'no_fields'];
            continue;
        }

        $route = findRouteOrNull($routeRepository, $path, $locale, $webspace);
        $entityId = null;
        $created = false;
        $usedFallback = false;

        if (!$route && $fallbackLocale !== '' && $fallbackLocale !== $locale) {
            $fallbackRoute = findRouteOrNull($routeRepository, $path, $fallbackLocale, $webspace);
            if ($fallbackRoute) {
                $entityId = extractResourceId($fallbackRoute);
                dispatchWithFlush($messageBus, new CopyLocalePageMessage(['uuid' => $entityId], $fallbackLocale, $locale));
                $usedFallback = true;
                $route = findRouteOrNull($routeRepository, $path, $locale, $webspace);
            }
        }

        if (!$route && $createIfMissing) {
            $parentRoute = null;
            if ($parentPath !== '/') {
                $parentRoute = findRouteOrNull($routeRepository, $parentPath, $locale, $webspace);
                if (!$parentRoute && $fallbackLocale !== '' && $fallbackLocale !== $locale) {
                    $parentRoute = findRouteOrNull($routeRepository, $parentPath, $fallbackLocale, $webspace);
                }
                if (!$parentRoute) {
                    stderr("ERROR: Parent route not found for parent_path={$parentPath}, locale={$locale}, webspace=" . ($webspace ?: '(any)'));
                    exit(2);
                }
            }

            if (trim($templateKey) === '') {
                stderr("ERROR: template is required when create_if_missing=true (path={$path})");
                exit(2);
            }

            $parentId = $parentRoute ? extractResourceId($parentRoute) : CreatePageMessageHandler::HOMEPAGE_PARENT_ID;
            $createResult = dispatchWithFlush($messageBus, new CreatePageMessage($webspace, $parentId, $data));
            if (is_object($createResult) && method_exists($createResult, 'getUuid')) {
                $entityId = (string) $createResult->getUuid();
            }
            $created = true;
            $route = findRouteOrNull($routeRepository, $path, $locale, $webspace);
        }

        if (!$route) {
            stderr("ERROR: Route not found for path={$path}, locale={$locale}, webspace=" . ($webspace ?? '(any)'));
            exit(2);
        }

        $resolvedEntityId = extractResourceId($route);
        if ($entityId === null) {
            $entityId = $resolvedEntityId;
        }

        if (!$created) {
            dispatchWithFlush($messageBus, new ModifyPageMessage(['uuid' => $entityId], $data));
        }

        if ($publish) {
            dispatchWithFlush(
                $messageBus,
                new ApplyWorkflowTransitionPageMessage(['uuid' => $entityId], $locale, WorkflowInterface::WORKFLOW_TRANSITION_PUBLISH)
            );
        }

        $localesByEntityId[$resolvedEntityId][] = $locale;
        $results[] = [
            'path' => $path,
            'ok' => true,
            'created' => $created,
            'used_fallback' => $usedFallback,
            'entity_id' => $entityId,
            'locale' => $locale,
            'webspace' => $webspace,
            'published' => $publish,
        ];
    }

    updateAvailableLocales($entityManager, $localesByEntityId);

    echo json_encode(['ok' => true, 'results' => $results], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . PHP_EOL;
    return 0;
}

exit(main($argv));
