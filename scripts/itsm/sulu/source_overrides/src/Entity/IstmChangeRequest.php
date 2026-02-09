<?php

declare(strict_types=1);

namespace App\Entity;

use Doctrine\DBAL\Types\Types;
use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity]
#[ORM\Table(name: 'change_request', schema: 'itsm')]
class IstmChangeRequest
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
    private ?string $risk = null;

    #[ORM\Column(type: Types::DATETIMETZ_IMMUTABLE, name: 'planned_start_at', nullable: true)]
    private ?\DateTimeImmutable $plannedStartAt = null;

    #[ORM\Column(type: Types::DATETIMETZ_IMMUTABLE, name: 'planned_end_at', nullable: true)]
    private ?\DateTimeImmutable $plannedEndAt = null;

    #[ORM\Column(type: Types::DATETIMETZ_IMMUTABLE, name: 'approved_at', nullable: true)]
    private ?\DateTimeImmutable $approvedAt = null;

    #[ORM\Column(type: Types::DATETIMETZ_IMMUTABLE, name: 'implemented_at', nullable: true)]
    private ?\DateTimeImmutable $implementedAt = null;

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

    public function getRisk(): ?string
    {
        return $this->risk;
    }

    public function getPlannedStartAt(): ?\DateTimeImmutable
    {
        return $this->plannedStartAt;
    }

    public function getPlannedEndAt(): ?\DateTimeImmutable
    {
        return $this->plannedEndAt;
    }

    public function getApprovedAt(): ?\DateTimeImmutable
    {
        return $this->approvedAt;
    }

    public function getImplementedAt(): ?\DateTimeImmutable
    {
        return $this->implementedAt;
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

