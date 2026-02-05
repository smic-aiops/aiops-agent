<?php

declare(strict_types=1);

namespace App\Entity;

use App\Repository\N8nObserverEventRepository;
use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity(repositoryClass: N8nObserverEventRepository::class)]
#[ORM\Table(name: 'n8n_observer_events')]
class N8nObserverEvent
{
    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column(type: 'integer')]
    private ?int $id = null;

    #[ORM\Column(type: 'datetime_immutable', name: 'received_at')]
    private \DateTimeImmutable $receivedAt;

    #[ORM\Column(type: 'string', length: 64, nullable: true)]
    private ?string $realm = null;

    #[ORM\Column(type: 'string', length: 255, nullable: true)]
    private ?string $workflow = null;

    #[ORM\Column(type: 'string', length: 255, nullable: true)]
    private ?string $node = null;

    #[ORM\Column(type: 'string', length: 128, nullable: true, name: 'execution_id')]
    private ?string $executionId = null;

    #[ORM\Column(type: 'json')]
    private array $payload = [];

    public function getId(): ?int
    {
        return $this->id;
    }

    public function getReceivedAt(): \DateTimeImmutable
    {
        return $this->receivedAt;
    }

    public function getRealm(): ?string
    {
        return $this->realm;
    }

    public function getWorkflow(): ?string
    {
        return $this->workflow;
    }

    public function getNode(): ?string
    {
        return $this->node;
    }

    public function getExecutionId(): ?string
    {
        return $this->executionId;
    }

    public function getPayload(): array
    {
        return $this->payload;
    }
}
