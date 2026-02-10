<?php

declare(strict_types=1);

namespace App\Controller;

use App\IstmSor\Entity\IstmIncident;
use App\ListBuilder\IstmDoctrineListBuilderFactory;
use App\Service\IstmSorRlsContext;
use FOS\RestBundle\View\ViewHandlerInterface;
use Sulu\Component\Rest\AbstractRestController;
use Sulu\Component\Rest\ListBuilder\Doctrine\DoctrineListBuilder;
use Sulu\Component\Rest\ListBuilder\Metadata\FieldDescriptorFactoryInterface;
use Sulu\Component\Rest\ListBuilder\PaginatedRepresentation;
use Sulu\Component\Rest\RestHelperInterface;
use Sulu\Component\Security\Authorization\PermissionTypes;
use Sulu\Component\Security\Authorization\SecurityCheckerInterface;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Security\Core\Authentication\Token\Storage\TokenStorageInterface;

final class IstmIncidentController extends AbstractRestController
{
    private const LIST_KEY = 'itsm_incidents';
    private const SECURITY_CONTEXT = 'app.itsm.incidents';

    public function __construct(
        ViewHandlerInterface $viewHandler,
        TokenStorageInterface $tokenStorage,
        private readonly FieldDescriptorFactoryInterface $fieldDescriptorFactory,
        private readonly IstmDoctrineListBuilderFactory $listBuilderFactory,
        private readonly RestHelperInterface $restHelper,
        private readonly SecurityCheckerInterface $securityChecker,
        private readonly IstmSorRlsContext $rlsContext,
    ) {
        parent::__construct($viewHandler, $tokenStorage);
    }

    public function cgetAction(Request $request): Response
    {
        $this->securityChecker->checkPermission(self::SECURITY_CONTEXT, PermissionTypes::VIEW);
        $this->rlsContext->apply($this->listBuilderFactory->getConnection(), $request);

        $fieldDescriptors = $this->fieldDescriptorFactory->getFieldDescriptors(self::LIST_KEY);

        /** @var DoctrineListBuilder $listBuilder */
        $listBuilder = $this->listBuilderFactory->create(IstmIncident::class);
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

    public function getAction(Request $request, string $id): Response
    {
        $this->securityChecker->checkPermission(self::SECURITY_CONTEXT, PermissionTypes::VIEW);
        $this->rlsContext->apply($this->listBuilderFactory->getConnection(), $request);

        /** @var IstmIncident|null $incident */
        $incident = $this->listBuilderFactory->getEntityManager()->find(IstmIncident::class, $id);
        if (!$incident) {
            return $this->handleView($this->view(['message' => 'Not Found'], 404));
        }

        return $this->handleView($this->view([
            'id' => $incident->getId(),
            'realmKey' => $incident->getRealm()->getRealmKey(),
            'number' => $incident->getNumber(),
            'serviceId' => $incident->getServiceId(),
            'title' => $incident->getTitle(),
            'description' => $incident->getDescription(),
            'status' => $incident->getStatus(),
            'priority' => $incident->getPriority(),
            'requesterPrincipalId' => $incident->getRequesterPrincipalId(),
            'assigneePrincipalId' => $incident->getAssigneePrincipalId(),
            'openedAt' => $incident->getOpenedAt()->format(DATE_ATOM),
            'resolvedAt' => $incident->getResolvedAt()?->format(DATE_ATOM),
            'closedAt' => $incident->getClosedAt()?->format(DATE_ATOM),
            'createdAt' => $incident->getCreatedAt()->format(DATE_ATOM),
            'updatedAt' => $incident->getUpdatedAt()->format(DATE_ATOM),
        ]));
    }
}
