<?php

declare(strict_types=1);

namespace App\IstmSor\Entity;

use Doctrine\DBAL\Types\Types;
use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity]
#[ORM\Table(name: 'audit_event', schema: 'itsm')]
class IstmAuditEvent
{
    #[ORM\Id]
    #[ORM\Column(type: 'guid')]
    private string $id;

    #[ORM\ManyToOne(targetEntity: IstmRealm::class)]
    #[ORM\JoinColumn(name: 'realm_id', referencedColumnName: 'id', nullable: false)]
    private IstmRealm $realm;

    #[ORM\Column(type: Types::DATETIMETZ_IMMUTABLE, name: 'occurred_at')]
    private \DateTimeImmutable $occurredAt;

    #[ORM\Column(type: Types::JSON)]
    private array $actor = [];

    #[ORM\Column(type: Types::STRING, name: 'actor_type')]
    private string $actorType;

    #[ORM\Column(type: Types::STRING)]
    private string $action;

    #[ORM\Column(type: Types::STRING)]
    private string $source;

    #[ORM\Column(type: Types::STRING, name: 'resource_type', nullable: true)]
    private ?string $resourceType = null;

    #[ORM\Column(type: 'guid', name: 'resource_id', nullable: true)]
    private ?string $resourceId = null;

    #[ORM\Column(type: Types::STRING, name: 'correlation_id', nullable: true)]
    private ?string $correlationId = null;

    #[ORM\Column(type: Types::JSON, name: 'reply_target', nullable: true)]
    private ?array $replyTarget = null;

    #[ORM\Column(type: Types::TEXT, nullable: true)]
    private ?string $summary = null;

    #[ORM\Column(type: Types::TEXT, nullable: true)]
    private ?string $message = null;

    #[ORM\Column(type: Types::JSON, nullable: true)]
    private ?array $before = null;

    #[ORM\Column(type: Types::JSON, nullable: true)]
    private ?array $after = null;

    #[ORM\Column(type: Types::JSON, nullable: true)]
    private ?array $integrity = null;

    public function getId(): string
    {
        return $this->id;
    }

    public function getRealm(): IstmRealm
    {
        return $this->realm;
    }

    public function getOccurredAt(): \DateTimeImmutable
    {
        return $this->occurredAt;
    }

    public function getActor(): array
    {
        return $this->actor;
    }

    public function getActorType(): string
    {
        return $this->actorType;
    }

    public function getAction(): string
    {
        return $this->action;
    }

    public function getSource(): string
    {
        return $this->source;
    }

    public function getResourceType(): ?string
    {
        return $this->resourceType;
    }

    public function getResourceId(): ?string
    {
        return $this->resourceId;
    }

    public function getCorrelationId(): ?string
    {
        return $this->correlationId;
    }

    public function getReplyTarget(): ?array
    {
        return $this->replyTarget;
    }

    public function getSummary(): ?string
    {
        return $this->summary;
    }

    public function getMessage(): ?string
    {
        return $this->message;
    }

    public function getBefore(): ?array
    {
        return $this->before;
    }

    public function getAfter(): ?array
    {
        return $this->after;
    }

    public function getIntegrity(): ?array
    {
        return $this->integrity;
    }
}

