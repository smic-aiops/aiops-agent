<?php

declare(strict_types=1);

namespace App\AIOpsDemo;

final class MemorySafeReportIterator
{
    public static function chunks(iterable $rows, int $chunkSize = 100): \Generator
    {
        $chunk = [];
        foreach ($rows as $row) {
            $chunk[] = $row;
            if (count($chunk) >= $chunkSize) {
                yield $chunk;
                $chunk = [];
            }
        }
        if ($chunk !== []) {
            yield $chunk;
        }
    }
}
