<?php
$url = getenv('DATABASE_URL');
if (!$url) {
    fwrite(STDERR, "[init-db] DATABASE_URL is missing; cannot ensure database exists.\n");
    exit(1);
}

$parts = parse_url($url);
if (!$parts || empty($parts['path'])) {
    fwrite(STDERR, "[init-db] Invalid DATABASE_URL format\n");
    exit(1);
}

$dbName = ltrim($parts['path'], '/');
$host   = $parts['host'] ?? '127.0.0.1';
$port   = $parts['port'] ?? 5432;
$user   = isset($parts['user']) ? urldecode($parts['user']) : null;
$pass   = isset($parts['pass']) ? urldecode($parts['pass']) : null;

$dsn = sprintf('pgsql:host=%s;port=%s;dbname=postgres', $host, $port);
try {
    $pdo = new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    $stmt = $pdo->prepare('SELECT 1 FROM pg_database WHERE datname = :db');
    $stmt->execute(['db' => $dbName]);
    if ($stmt->fetchColumn()) {
        echo "[init-db] database {$dbName} already exists.\n";
        exit(0);
    }
    $safeName = str_replace('"', '""', $dbName);
    $pdo->exec('CREATE DATABASE "' . $safeName . '"');
    echo "[init-db] created database {$dbName}.\n";
} catch (Throwable $e) {
    fwrite(STDERR, "[init-db] failed to ensure database: " . $e->getMessage() . "\n");
    exit(1);
}
