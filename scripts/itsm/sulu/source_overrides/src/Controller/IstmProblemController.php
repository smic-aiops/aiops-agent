<?php

declare(strict_types=1);

namespace App\Controller;

use App\Entity\IstmProblem;
use Doctrine\ORM\EntityManagerInterface;
use FOS\RestBundle\View\ViewHandlerInterface;
use Sulu\Component\Rest\AbstractRestController;
use Sulu\Component\Rest\ListBuilder\Doctrine\DoctrineListBuilder;
use Sulu\Component\Rest\ListBuilder\Doctrine\DoctrineListBuilderFactoryInterface;
use Sulu\Component\Rest\ListBuilder\Metadata\FieldDescriptorFactoryInterface;
use Sulu\Component\Rest\ListBuilder\PaginatedRepresentation;
use Sulu\Component\Rest\RestHelperInterface;
use Sulu\Component\Security\Authorization\PermissionTypes;
use Sulu\Component\Security\Authorization\SecurityCheckerInterface;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Security\Core\Authentication\Token\Storage\TokenStorageInterface;

final class IstmProblemController extends AbstractRestController
{
    private const LIST_KEY = 'itsm_problems';
    private const SECURITY_CONTEXT = 'app.itsm.problems';

    public function __construct(
        ViewHandlerInterface $viewHandler,
        TokenStorageInterface $tokenStorage,
        private readonly FieldDescriptorFactoryInterface $fieldDescriptorFactory,
        private readonly DoctrineListBuilderFactoryInterface $listBuilderFactory,
        private readonly RestHelperInterface $restHelper,
        private readonly EntityManagerInterface $entityManager,
        private readonly SecurityCheckerInterface $securityChecker,
    ) {
        parent::__construct($viewHandler, $tokenStorage);
    }

    public function cgetAction(Request $request): Response
    {
        $this->securityChecker->checkPermission(self::SECURITY_CONTEXT, PermissionTypes::VIEW);

        $fieldDescriptors = $this->fieldDescriptorFactory->getFieldDescriptors(self::LIST_KEY);

        /** @var DoctrineListBuilder $listBuilder */
        $listBuilder = $this->listBuilderFactory->create(IstmProblem::class);
        $listBuilder->sort($fieldDescriptors['updatedAt'], 'DESC');

        $this->restHelper->initializeListBuilder($listBuilder, $fieldDescriptors);

        $result = $listBuilder->execute();

        $representation = new PaginatedRepresentation(
            $result,
            self::LIST_KEY,
            (int) $listBuilder->getCurrentPage(),
            (int) $listBuilder->getLimit(),
            $listBuilder->count(),
        );

        return $this->handleView($this->view($representation));
    }

    public function getAction(string $id): Response
    {
        $this->securityChecker->checkPermission(self::SECURITY_CONTEXT, PermissionTypes::VIEW);

        /** @var IstmProblem|null $problem */
        $problem = $this->entityManager->find(IstmProblem::class, $id);
        if (!$problem) {
            return $this->handleView($this->view(['message' => 'Not Found'], 404));
        }

        return $this->handleView($this->view([
            'id' => $problem->getId(),
            'realmKey' => $problem->getRealm()->getRealmKey(),
            'number' => $problem->getNumber(),
            'serviceId' => $problem->getServiceId(),
            'title' => $problem->getTitle(),
            'description' => $problem->getDescription(),
            'status' => $problem->getStatus(),
            'priority' => $problem->getPriority(),
            'createdAt' => $problem->getCreatedAt()->format(DATE_ATOM),
            'updatedAt' => $problem->getUpdatedAt()->format(DATE_ATOM),
        ]));
    }
}

