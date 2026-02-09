<?php

declare(strict_types=1);

namespace App\Controller;

use App\Entity\IstmServiceRequest;
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

final class IstmServiceRequestController extends AbstractRestController
{
    private const LIST_KEY = 'itsm_service_requests';
    private const SECURITY_CONTEXT = 'app.itsm.service_requests';

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
        $listBuilder = $this->listBuilderFactory->create(IstmServiceRequest::class);
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

        /** @var IstmServiceRequest|null $requestEntity */
        $requestEntity = $this->entityManager->find(IstmServiceRequest::class, $id);
        if (!$requestEntity) {
            return $this->handleView($this->view(['message' => 'Not Found'], 404));
        }

        return $this->handleView($this->view([
            'id' => $requestEntity->getId(),
            'realmKey' => $requestEntity->getRealm()->getRealmKey(),
            'number' => $requestEntity->getNumber(),
            'serviceId' => $requestEntity->getServiceId(),
            'title' => $requestEntity->getTitle(),
            'description' => $requestEntity->getDescription(),
            'status' => $requestEntity->getStatus(),
            'priority' => $requestEntity->getPriority(),
            'requesterPrincipalId' => $requestEntity->getRequesterPrincipalId(),
            'assigneePrincipalId' => $requestEntity->getAssigneePrincipalId(),
            'openedAt' => $requestEntity->getOpenedAt()->format(DATE_ATOM),
            'fulfilledAt' => $requestEntity->getFulfilledAt()?->format(DATE_ATOM),
            'closedAt' => $requestEntity->getClosedAt()?->format(DATE_ATOM),
            'createdAt' => $requestEntity->getCreatedAt()->format(DATE_ATOM),
            'updatedAt' => $requestEntity->getUpdatedAt()->format(DATE_ATOM),
        ]));
    }
}

