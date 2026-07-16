<?php

declare(strict_types=1);

namespace App\Controller;

use App\IstmSor\Entity\IstmChangeRequest;
use App\ListBuilder\IstmDoctrineListBuilderFactory;
use App\Service\IstmSorRlsContext;
use App\Service\IstmCoreWriter;
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

final class IstmChangeRequestController extends AbstractRestController
{
    use IstmWritableControllerTrait;
    private const LIST_KEY = 'itsm_change_requests';
    private const SECURITY_CONTEXT = 'app.itsm.change_requests';

    public function __construct(
        ViewHandlerInterface $viewHandler,
        TokenStorageInterface $tokenStorage,
        private readonly FieldDescriptorFactoryInterface $fieldDescriptorFactory,
        private readonly IstmDoctrineListBuilderFactory $listBuilderFactory,
        private readonly RestHelperInterface $restHelper,
        private readonly SecurityCheckerInterface $securityChecker,
        private readonly IstmSorRlsContext $rlsContext,
        private readonly IstmCoreWriter $coreWriter,
    ) {
        parent::__construct($viewHandler, $tokenStorage);
    }

    public function cgetAction(Request $request): Response
    {
        $this->securityChecker->checkPermission(self::SECURITY_CONTEXT, PermissionTypes::VIEW);
        $this->rlsContext->apply($this->listBuilderFactory->getConnection(), $request);

        $fieldDescriptors = $this->fieldDescriptorFactory->getFieldDescriptors(self::LIST_KEY);

        /** @var DoctrineListBuilder $listBuilder */
        $listBuilder = $this->listBuilderFactory->create(IstmChangeRequest::class);
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

        /** @var IstmChangeRequest|null $changeRequest */
        $changeRequest = $this->listBuilderFactory->getEntityManager()->find(IstmChangeRequest::class, $id);
        if (!$changeRequest) {
            return $this->handleView($this->view(['message' => 'Not Found'], 404));
        }

        return $this->handleView($this->view([
            'id' => $changeRequest->getId(),
            'realmKey' => $changeRequest->getRealm()->getRealmKey(),
            'number' => $changeRequest->getNumber(),
            'serviceId' => $changeRequest->getServiceId(),
            'title' => $changeRequest->getTitle(),
            'description' => $changeRequest->getDescription(),
            'status' => $changeRequest->getStatus(),
            'risk' => $changeRequest->getRisk(),
            'plannedStartAt' => $changeRequest->getPlannedStartAt()?->format(DATE_ATOM),
            'plannedEndAt' => $changeRequest->getPlannedEndAt()?->format(DATE_ATOM),
            'approvedAt' => $changeRequest->getApprovedAt()?->format(DATE_ATOM),
            'implementedAt' => $changeRequest->getImplementedAt()?->format(DATE_ATOM),
            'createdAt' => $changeRequest->getCreatedAt()->format(DATE_ATOM),
            'updatedAt' => $changeRequest->getUpdatedAt()->format(DATE_ATOM),
        ]));
    }

    public function postAction(Request $request): Response { return $this->createResource($request, 'change_request'); }
    public function putAction(Request $request, string $id): Response { return $this->updateResource($request, 'change_request', $id); }
    public function deleteAction(Request $request, string $id): Response { return $this->deleteResource($request, 'change_request', $id); }
}
