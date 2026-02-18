<?php

declare(strict_types=1);

namespace App\Controller;

use App\Admin\IstmAdmin;
use App\ListBuilder\IstmDoctrineListBuilderFactory;
use App\Service\IstmSorRlsContext;
use Doctrine\DBAL\Connection;
use Sulu\Component\Security\Authorization\PermissionTypes;
use Sulu\Component\Security\Authorization\SecurityCheckerInterface;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpKernel\Attribute\AsController;

#[AsController]
final class IstmKpiController
{
    /**
     * @var array<string, bool>
     */
    private array $columnExistsCache = [];

    public function __construct(
        private readonly IstmDoctrineListBuilderFactory $listBuilderFactory,
        private readonly IstmSorRlsContext $rlsContext,
        private readonly SecurityCheckerInterface $securityChecker,
    ) {
    }

    public function config(Request $request): JsonResponse
    {
        $this->securityChecker->checkPermission(IstmAdmin::SECURITY_CONTEXT_KPI_MTTR, PermissionTypes::VIEW);

        $grafanaUrl = (string) (getenv('GRAFANA_PUBLIC_URL') ?: getenv('GRAFANA_URL') ?: getenv('SERVICE_URL_GRAFANA') ?: '');
        $grafanaUrl = rtrim($grafanaUrl, '/');

        return new JsonResponse([
            'ok' => true,
            'data' => [
                'grafana_url' => $grafanaUrl !== '' ? $grafanaUrl : null,
                'dashboards' => [
                    'mttr_uid' => (string) (getenv('GRAFANA_DASHBOARD_UID_MTTR') ?: 'tm-automation-effect'),
                    'triage_uid' => (string) (getenv('GRAFANA_DASHBOARD_UID_TRIAGE') ?: 'sm-incident-monitoring'),
                    'lead_time_uid' => (string) (getenv('GRAFANA_DASHBOARD_UID_LEAD_TIME') ?: 'tm-deployment'),
                ],
            ],
        ]);
    }

    public function mttr(Request $request): JsonResponse
    {
        $this->securityChecker->checkPermission(IstmAdmin::SECURITY_CONTEXT_KPI_MTTR, PermissionTypes::VIEW);
        $connection = $this->listBuilderFactory->getConnection();
        $this->rlsContext->apply($connection, $request);

        $range = $this->resolveRange($request);
        $customerId = $this->normalizeCustomerId($request->query->get('customer_id'));

        $warnings = [];

        $openedCol = $this->resolveColumn($connection, 'itsm', 'incident', ['opened_at', 'started_at', 'created_at']);
        $resolvedCol = $this->resolveColumn($connection, 'itsm', 'incident', ['resolved_at']);
        if (!$openedCol || !$resolvedCol) {
            return $this->error('incident_columns_missing');
        }

        $serviceCustomerCol = $this->resolveColumn($connection, 'itsm', 'service', ['customer_id']);
        if ($customerId && !$serviceCustomerCol) {
            $warnings[] = 'customer_id_column_missing';
        }

        $deletedAtCol = $this->resolveColumn($connection, 'itsm', 'incident', ['deleted_at']);

        $where = [];
        $params = [
            'from' => $range['from']->format(DATE_ATOM),
            'to' => $range['to']->format(DATE_ATOM),
        ];
        $where[] = "i.{$openedCol} >= :from AND i.{$openedCol} < :to";
        $where[] = "i.{$resolvedCol} IS NOT NULL";
        if ($deletedAtCol) {
            $where[] = "i.{$deletedAtCol} IS NULL";
        }

        $serviceJoin = 'LEFT JOIN itsm.service s ON s.id = i.service_id';
        if ($customerId && $serviceCustomerCol) {
            $where[] = "s.{$serviceCustomerCol} = :customer_id";
            $params['customer_id'] = $customerId;
        }

        $whereSql = implode(' AND ', $where);

        $summarySql = <<<SQL
WITH rows AS (
  SELECT
    EXTRACT(EPOCH FROM (i.{$resolvedCol} - i.{$openedCol})) / 60.0 AS minutes
  FROM itsm.incident i
  {$serviceJoin}
  WHERE {$whereSql}
)
SELECT
  COUNT(*)::int AS count,
  AVG(minutes) AS avg_minutes,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY minutes) AS p50_minutes,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY minutes) AS p95_minutes
FROM rows
SQL;

        $summary = $connection->fetchAssociative($summarySql, $params) ?: [];

        $slowestSql = <<<SQL
SELECT
  i.number,
  i.priority,
  i.service_id,
  i.{$openedCol} AS opened_at,
  i.{$resolvedCol} AS resolved_at,
  (EXTRACT(EPOCH FROM (i.{$resolvedCol} - i.{$openedCol})) / 60.0) AS minutes
FROM itsm.incident i
{$serviceJoin}
WHERE {$whereSql}
ORDER BY minutes DESC NULLS LAST
LIMIT 50
SQL;

        $slowest = $connection->fetchAllAssociative($slowestSql, $params);

        $byPrioritySql = <<<SQL
WITH rows AS (
  SELECT
    i.priority AS priority,
    EXTRACT(EPOCH FROM (i.{$resolvedCol} - i.{$openedCol})) / 60.0 AS minutes
  FROM itsm.incident i
  {$serviceJoin}
  WHERE {$whereSql}
)
SELECT
  COALESCE(priority, '(none)') AS priority,
  COUNT(*)::int AS count,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY minutes) AS p50_minutes,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY minutes) AS p95_minutes
FROM rows
GROUP BY priority
ORDER BY priority NULLS LAST
SQL;

        $byPriority = $connection->fetchAllAssociative($byPrioritySql, $params);

        return new JsonResponse([
            'ok' => true,
            'data' => [
                'range' => [
                    'from' => $range['from']->format(DATE_ATOM),
                    'to' => $range['to']->format(DATE_ATOM),
                ],
                'customer_id' => $customerId,
                'warnings' => $warnings,
                'summary' => $this->normalizeSummary($summary),
                'by_priority' => $byPriority,
                'slowest' => $slowest,
            ],
        ]);
    }

    public function triage(Request $request): JsonResponse
    {
        $this->securityChecker->checkPermission(IstmAdmin::SECURITY_CONTEXT_KPI_TRIAGE, PermissionTypes::VIEW);
        $connection = $this->listBuilderFactory->getConnection();
        $this->rlsContext->apply($connection, $request);

        $range = $this->resolveRange($request);
        $customerId = $this->normalizeCustomerId($request->query->get('customer_id'));

        $warnings = [];

        $openedCol = $this->resolveColumn($connection, 'itsm', 'incident', ['opened_at', 'started_at', 'created_at']);
        $ackCol = $this->resolveColumn($connection, 'itsm', 'incident', ['acknowledged_at']);
        $firstResponseCol = $this->resolveColumn($connection, 'itsm', 'incident', ['first_response_at']);
        if (!$openedCol || (!$ackCol && !$firstResponseCol)) {
            return $this->error('triage_columns_missing');
        }

        $serviceCustomerCol = $this->resolveColumn($connection, 'itsm', 'service', ['customer_id']);
        if ($customerId && !$serviceCustomerCol) {
            $warnings[] = 'customer_id_column_missing';
        }

        $deletedAtCol = $this->resolveColumn($connection, 'itsm', 'incident', ['deleted_at']);

        $where = [];
        $params = [
            'from' => $range['from']->format(DATE_ATOM),
            'to' => $range['to']->format(DATE_ATOM),
        ];
        $where[] = "i.{$openedCol} >= :from AND i.{$openedCol} < :to";
        if ($deletedAtCol) {
            $where[] = "i.{$deletedAtCol} IS NULL";
        }

        $serviceJoin = 'LEFT JOIN itsm.service s ON s.id = i.service_id';
        if ($customerId && $serviceCustomerCol) {
            $where[] = "s.{$serviceCustomerCol} = :customer_id";
            $params['customer_id'] = $customerId;
        }

        $whereSql = implode(' AND ', $where);

        $triageExpr = null;
        if ($firstResponseCol) {
            $triageExpr = "EXTRACT(EPOCH FROM (i.{$firstResponseCol} - i.{$openedCol})) / 60.0";
        } elseif ($ackCol) {
            $triageExpr = "EXTRACT(EPOCH FROM (i.{$ackCol} - i.{$openedCol})) / 60.0";
        }
        if (!$triageExpr) {
            return $this->error('triage_expr_missing');
        }

        $summarySql = <<<SQL
WITH rows AS (
  SELECT
    {$triageExpr} AS minutes
  FROM itsm.incident i
  {$serviceJoin}
  WHERE {$whereSql}
)
SELECT
  COUNT(*) FILTER (WHERE minutes IS NOT NULL)::int AS count,
  AVG(minutes) AS avg_minutes,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY minutes) FILTER (WHERE minutes IS NOT NULL) AS p50_minutes,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY minutes) FILTER (WHERE minutes IS NOT NULL) AS p95_minutes,
  COUNT(*) FILTER (WHERE minutes IS NULL)::int AS missing_count
FROM rows
SQL;

        $summary = $connection->fetchAssociative($summarySql, $params) ?: [];

        $slowestSql = <<<SQL
SELECT
  i.number,
  i.priority,
  i.service_id,
  i.{$openedCol} AS opened_at,
  {$firstResponseCol ? "i.{$firstResponseCol} AS first_response_at," : "NULL::timestamptz AS first_response_at,"}
  {$ackCol ? "i.{$ackCol} AS acknowledged_at," : "NULL::timestamptz AS acknowledged_at,"}
  ({$triageExpr}) AS minutes
FROM itsm.incident i
{$serviceJoin}
WHERE {$whereSql}
ORDER BY minutes DESC NULLS LAST
LIMIT 50
SQL;

        $slowest = $connection->fetchAllAssociative($slowestSql, $params);

        $byPrioritySql = <<<SQL
WITH rows AS (
  SELECT
    i.priority AS priority,
    {$triageExpr} AS minutes
  FROM itsm.incident i
  {$serviceJoin}
  WHERE {$whereSql}
)
SELECT
  COALESCE(priority, '(none)') AS priority,
  COUNT(*) FILTER (WHERE minutes IS NOT NULL)::int AS count,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY minutes) FILTER (WHERE minutes IS NOT NULL) AS p50_minutes,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY minutes) FILTER (WHERE minutes IS NOT NULL) AS p95_minutes,
  COUNT(*) FILTER (WHERE minutes IS NULL)::int AS missing_count
FROM rows
GROUP BY priority
ORDER BY priority NULLS LAST
SQL;

        $byPriority = $connection->fetchAllAssociative($byPrioritySql, $params);

        return new JsonResponse([
            'ok' => true,
            'data' => [
                'range' => [
                    'from' => $range['from']->format(DATE_ATOM),
                    'to' => $range['to']->format(DATE_ATOM),
                ],
                'customer_id' => $customerId,
                'warnings' => $warnings,
                'summary' => $this->normalizeSummary($summary),
                'by_priority' => $byPriority,
                'slowest' => $slowest,
            ],
        ]);
    }

    public function leadTime(Request $request): JsonResponse
    {
        $this->securityChecker->checkPermission(IstmAdmin::SECURITY_CONTEXT_KPI_LEAD_TIME, PermissionTypes::VIEW);
        $connection = $this->listBuilderFactory->getConnection();
        $this->rlsContext->apply($connection, $request);

        $range = $this->resolveRange($request);
        $customerId = $this->normalizeCustomerId($request->query->get('customer_id'));

        $warnings = [];

        $createdCol = $this->resolveColumn($connection, 'itsm', 'change_request', ['created_at']);
        $implementedCol = $this->resolveColumn($connection, 'itsm', 'change_request', ['implemented_at']);
        if (!$createdCol || !$implementedCol) {
            return $this->error('change_request_columns_missing');
        }

        $serviceCustomerCol = $this->resolveColumn($connection, 'itsm', 'service', ['customer_id']);
        if ($customerId && !$serviceCustomerCol) {
            $warnings[] = 'customer_id_column_missing';
        }

        $deletedAtCol = $this->resolveColumn($connection, 'itsm', 'change_request', ['deleted_at']);

        $where = [];
        $params = [
            'from' => $range['from']->format(DATE_ATOM),
            'to' => $range['to']->format(DATE_ATOM),
        ];
        $where[] = "c.{$createdCol} >= :from AND c.{$createdCol} < :to";
        $where[] = "c.{$implementedCol} IS NOT NULL";
        if ($deletedAtCol) {
            $where[] = "c.{$deletedAtCol} IS NULL";
        }

        $serviceJoin = 'LEFT JOIN itsm.service s ON s.id = c.service_id';
        if ($customerId && $serviceCustomerCol) {
            $where[] = "s.{$serviceCustomerCol} = :customer_id";
            $params['customer_id'] = $customerId;
        }

        $whereSql = implode(' AND ', $where);

        $summarySql = <<<SQL
WITH rows AS (
  SELECT
    EXTRACT(EPOCH FROM (c.{$implementedCol} - c.{$createdCol})) / 60.0 AS minutes
  FROM itsm.change_request c
  {$serviceJoin}
  WHERE {$whereSql}
)
SELECT
  COUNT(*)::int AS count,
  AVG(minutes) AS avg_minutes,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY minutes) AS p50_minutes,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY minutes) AS p95_minutes
FROM rows
SQL;

        $summary = $connection->fetchAssociative($summarySql, $params) ?: [];

        $slowestSql = <<<SQL
SELECT
  c.number,
  c.status,
  c.service_id,
  c.{$createdCol} AS created_at,
  c.{$implementedCol} AS implemented_at,
  (EXTRACT(EPOCH FROM (c.{$implementedCol} - c.{$createdCol})) / 60.0) AS minutes
FROM itsm.change_request c
{$serviceJoin}
WHERE {$whereSql}
ORDER BY minutes DESC NULLS LAST
LIMIT 50
SQL;

        $slowest = $connection->fetchAllAssociative($slowestSql, $params);

        $byStatusSql = <<<SQL
WITH rows AS (
  SELECT
    c.status AS status,
    EXTRACT(EPOCH FROM (c.{$implementedCol} - c.{$createdCol})) / 60.0 AS minutes
  FROM itsm.change_request c
  {$serviceJoin}
  WHERE {$whereSql}
)
SELECT
  COALESCE(status, '(none)') AS status,
  COUNT(*)::int AS count,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY minutes) AS p50_minutes,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY minutes) AS p95_minutes
FROM rows
GROUP BY status
ORDER BY status NULLS LAST
SQL;

        $byStatus = $connection->fetchAllAssociative($byStatusSql, $params);

        return new JsonResponse([
            'ok' => true,
            'data' => [
                'range' => [
                    'from' => $range['from']->format(DATE_ATOM),
                    'to' => $range['to']->format(DATE_ATOM),
                ],
                'customer_id' => $customerId,
                'warnings' => $warnings,
                'summary' => $this->normalizeSummary($summary),
                'by_status' => $byStatus,
                'slowest' => $slowest,
            ],
        ]);
    }

    private function resolveRange(Request $request): array
    {
        $fromRaw = $request->query->get('from');
        $toRaw = $request->query->get('to');

        $now = new \DateTimeImmutable('now', new \DateTimeZone('UTC'));
        $defaultFrom = $now->sub(new \DateInterval('P30D'));

        $from = $this->parseDateParam($fromRaw, $defaultFrom, false);
        $to = $this->parseDateParam($toRaw, $now, true);

        if ($to <= $from) {
            $to = $from->add(new \DateInterval('P1D'));
        }

        return ['from' => $from, 'to' => $to];
    }

    private function parseDateParam(mixed $value, \DateTimeImmutable $fallback, bool $endExclusive): \DateTimeImmutable
    {
        if (!\is_string($value) || trim($value) === '') {
            return $fallback;
        }

        $trimmed = trim($value);
        if (preg_match('/^\\d{4}-\\d{2}-\\d{2}$/', $trimmed)) {
            $dt = new \DateTimeImmutable($trimmed . 'T00:00:00+00:00');
            if ($endExclusive) {
                return $dt->add(new \DateInterval('P1D'));
            }
            return $dt;
        }

        try {
            $dt = new \DateTimeImmutable($trimmed);
        } catch (\Throwable) {
            return $fallback;
        }

        if ($endExclusive && $dt->format('H:i:s') === '00:00:00') {
            return $dt->add(new \DateInterval('P1D'));
        }

        return $dt->setTimezone(new \DateTimeZone('UTC'));
    }

    private function normalizeCustomerId(mixed $value): ?string
    {
        if (!\is_string($value)) {
            return null;
        }
        $trimmed = trim($value);
        return $trimmed === '' ? null : $trimmed;
    }

    private function columnExists(Connection $connection, string $schema, string $table, string $column): bool
    {
        $key = "{$schema}.{$table}.{$column}";
        if (array_key_exists($key, $this->columnExistsCache)) {
            return $this->columnExistsCache[$key];
        }

        try {
            $found = $connection->fetchOne(
                'SELECT 1 FROM information_schema.columns WHERE table_schema = :schema AND table_name = :table AND column_name = :column',
                ['schema' => $schema, 'table' => $table, 'column' => $column],
            );
            $this->columnExistsCache[$key] = $found !== false && $found !== null;
        } catch (\Throwable) {
            $this->columnExistsCache[$key] = false;
        }

        return $this->columnExistsCache[$key];
    }

    /**
     * @param array<int, string> $candidates
     */
    private function resolveColumn(Connection $connection, string $schema, string $table, array $candidates): ?string
    {
        foreach ($candidates as $candidate) {
            if ($this->columnExists($connection, $schema, $table, $candidate)) {
                return $candidate;
            }
        }
        return null;
    }

    /**
     * @param array<string, mixed> $row
     */
    private function normalizeSummary(array $row): array
    {
        return [
            'count' => isset($row['count']) ? (int) $row['count'] : 0,
            'avg_minutes' => $row['avg_minutes'] !== null ? (float) $row['avg_minutes'] : null,
            'p50_minutes' => $row['p50_minutes'] !== null ? (float) $row['p50_minutes'] : null,
            'p95_minutes' => $row['p95_minutes'] !== null ? (float) $row['p95_minutes'] : null,
            'missing_count' => array_key_exists('missing_count', $row) && $row['missing_count'] !== null ? (int) $row['missing_count'] : null,
        ];
    }

    private function error(string $code, int $status = 400): JsonResponse
    {
        return new JsonResponse(['ok' => false, 'error' => $code], $status);
    }
}
