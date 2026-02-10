<?php

declare(strict_types=1);

namespace App\ListBuilder;

use Doctrine\DBAL\Connection;
use Doctrine\ORM\EntityManagerInterface;
use Doctrine\Persistence\ManagerRegistry;
use Sulu\Bundle\SecurityBundle\AccessControl\AccessControlQueryEnhancerInterface;
use Sulu\Component\Rest\ListBuilder\Doctrine\DoctrineListBuilder;
use Sulu\Component\Rest\ListBuilder\Doctrine\DoctrineListBuilderFactoryInterface;
use Sulu\Component\Rest\ListBuilder\Filter\FilterTypeRegistry;
use Symfony\Component\DependencyInjection\ParameterBag\ParameterBagInterface;
use Symfony\Component\EventDispatcher\EventDispatcherInterface;

final class IstmDoctrineListBuilderFactory implements DoctrineListBuilderFactoryInterface
{
    private readonly EntityManagerInterface $em;
    private readonly array $permissions;

    public function __construct(
        ManagerRegistry $doctrine,
        private readonly FilterTypeRegistry $filterTypeRegistry,
        private readonly EventDispatcherInterface $eventDispatcher,
        ParameterBagInterface $parameterBag,
        private readonly AccessControlQueryEnhancerInterface $accessControlQueryEnhancer,
    ) {
        $em = $doctrine->getManager('itsm_sor');
        if (!$em instanceof EntityManagerInterface) {
            throw new \RuntimeException('Doctrine entity manager "itsm_sor" is not configured.');
        }
        $this->em = $em;

        $permissions = $parameterBag->get('sulu_security.permissions');
        if (!\is_array($permissions)) {
            throw new \RuntimeException('Parameter "sulu_security.permissions" is not an array.');
        }
        $this->permissions = $permissions;
    }

    /**
     * @param class-string $entityName
     */
    public function create($entityName): DoctrineListBuilder
    {
        return new DoctrineListBuilder(
            $this->em,
            $entityName,
            $this->filterTypeRegistry,
            $this->eventDispatcher,
            $this->permissions,
            $this->accessControlQueryEnhancer,
        );
    }

    public function getConnection(): Connection
    {
        return $this->em->getConnection();
    }

    public function getEntityManager(): EntityManagerInterface
    {
        return $this->em;
    }
}

