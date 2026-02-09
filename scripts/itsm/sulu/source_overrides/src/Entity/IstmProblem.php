<?php

declare(strict_types=1);

namespace App\Entity;

use Doctrine\DBAL\Types\Types;
use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity]
#[ORM\Table(name: 'problem', schema: 'itsm')]
class IstmProblem
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

    public function getCreatedAt(): \DateTimeImmutable
    {
        return $this->createdAt;
    }

    public function getUpdatedAt(): \DateTimeImmutable
    {
        return $this->updatedAt;
    }
}

