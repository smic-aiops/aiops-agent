<?php

declare(strict_types=1);

namespace App\Entity;

use Doctrine\DBAL\Types\Types;
use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity]
#[ORM\Table(name: 'incident', schema: 'itsm')]
class IstmIncident
{
    #[ORM\Id]
    #[ORM\Column(type: 'guid')]
    private string $id;

    #[ORM\ManyToOne(targetEntity: IstmRealm::class)]
    #[ORM\JoinColumn(name: 'realm_id', referencedColumnName: 'id', nullable: false)]
    private IstmRealm $realm;

    #[ORM\Column(type: Types::STRING)]
    private string $number;

    #[ORM\Column(type: 'guid', name: 'service_id', nullable: true)]
    private ?string $serviceId = null;

    #[ORM\Column(type: Types::STRING)]
    private string $title;

    #[ORM\Column(type: Types::TEXT, nullable: true)]
    private ?string $description = null;

    #[ORM\Column(type: Types::STRING)]
    private string $status;

    #[ORM\Column(type: Types::STRING, nullable: true)]
    private ?string $priority = null;

    #[ORM\Column(type: Types::STRING, name: 'requester_principal_id', nullable: true)]
    private ?string $requesterPrincipalId = null;

    #[ORM\Column(type: Types::STRING, name: 'assignee_principal_id', nullable: true)]
    private ?string $assigneePrincipalId = null;

    #[ORM\Column(type: Types::DATETIMETZ_IMMUTABLE, name: 'opened_at')]
    private \DateTimeImmutable $openedAt;

    #[ORM\Column(type: Types::DATETIMETZ_IMMUTABLE, name: 'resolved_at', nullable: true)]
    private ?\DateTimeImmutable $resolvedAt = null;

    #[ORM\Column(type: Types::DATETIMETZ_IMMUTABLE, name: 'closed_at', nullable: true)]
    private ?\DateTimeImmutable $closedAt = null;

    #[ORM\Column(type: Types::DATETIMETZ_IMMUTABLE, name: 'created_at')]
    private \DateTimeImmutable $createdAt;

    #[ORM\Column(type: Types::DATETIMETZ_IMMUTABLE, name: 'updated_at')]
    private \DateTimeImmutable $updatedAt;

    public function getId(): string
    {
        return $this->id;
    }

    public function getRealm(): IstmRealm
    {
        return $this->realm;
    }

    public function getNumber(): string
    {
        return $this->number;
    }

    public function getServiceId(): ?string
    {
        return $this->serviceId;
    }

    public function getTitle(): string
    {
        return $this->title;
    }

    public function getDescription(): ?string
    {
        return $this->description;
    }

    public function getStatus(): string
    {
        return $this->status;
    }

    public function getPriority(): ?string
    {
        return $this->priority;
    }

    public function getRequesterPrincipalId(): ?string
    {
        return $this->requesterPrincipalId;
    }

    public function getAssigneePrincipalId(): ?string
    {
        return $this->assigneePrincipalId;
    }

    public function getOpenedAt(): \DateTimeImmutable
    {
        return $this->openedAt;
    }

    public function getResolvedAt(): ?\DateTimeImmutable
    {
        return $this->resolvedAt;
    }

    public function getClosedAt(): ?\DateTimeImmutable
    {
        return $this->closedAt;
    }

    public function getCreatedAt(): \DateTimeImmutable
    {
        return $this->createdAt;
    }

    public function getUpdatedAt(): \DateTimeImmutable
    {
        return $this->updatedAt;
    }
}

