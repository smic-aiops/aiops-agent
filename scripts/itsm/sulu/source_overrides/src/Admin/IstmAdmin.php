<?php

declare(strict_types=1);

namespace App\Admin;

use Sulu\Bundle\AdminBundle\Admin\Admin;
use Sulu\Bundle\AdminBundle\Admin\Navigation\NavigationItem;
use Sulu\Bundle\AdminBundle\Admin\Navigation\NavigationItemCollection;
use Sulu\Bundle\AdminBundle\Admin\View\ViewBuilderFactoryInterface;
use Sulu\Bundle\AdminBundle\Admin\View\ViewCollection;
use Sulu\Component\Security\Authorization\PermissionTypes;

final class IstmAdmin extends Admin
{
    public const NAVIGATION_ITSM = 'app.itsm';

    public const VIEW_INCIDENTS = 'app.itsm.incidents';
    public const VIEW_INCIDENTS_DETAIL = 'app.itsm.incidents.detail';
    public const VIEW_INCIDENTS_DETAIL_FORM = 'app.itsm.incidents.detail.details';

    public const VIEW_SERVICE_REQUESTS = 'app.itsm.service_requests';
    public const VIEW_SERVICE_REQUESTS_DETAIL = 'app.itsm.service_requests.detail';
    public const VIEW_SERVICE_REQUESTS_DETAIL_FORM = 'app.itsm.service_requests.detail.details';

    public const VIEW_PROBLEMS = 'app.itsm.problems';
    public const VIEW_PROBLEMS_DETAIL = 'app.itsm.problems.detail';
    public const VIEW_PROBLEMS_DETAIL_FORM = 'app.itsm.problems.detail.details';

    public const VIEW_CHANGE_REQUESTS = 'app.itsm.change_requests';
    public const VIEW_CHANGE_REQUESTS_DETAIL = 'app.itsm.change_requests.detail';
    public const VIEW_CHANGE_REQUESTS_DETAIL_FORM = 'app.itsm.change_requests.detail.details';

    public const RESOURCE_KEY_INCIDENTS = 'itsm_incidents';
    public const LIST_KEY_INCIDENTS = 'itsm_incidents';
    public const FORM_KEY_INCIDENT_DETAILS = 'itsm_incident_details';

    public const RESOURCE_KEY_SERVICE_REQUESTS = 'itsm_service_requests';
    public const LIST_KEY_SERVICE_REQUESTS = 'itsm_service_requests';
    public const FORM_KEY_SERVICE_REQUEST_DETAILS = 'itsm_service_request_details';

    public const RESOURCE_KEY_PROBLEMS = 'itsm_problems';
    public const LIST_KEY_PROBLEMS = 'itsm_problems';
    public const FORM_KEY_PROBLEM_DETAILS = 'itsm_problem_details';

    public const RESOURCE_KEY_CHANGE_REQUESTS = 'itsm_change_requests';
    public const LIST_KEY_CHANGE_REQUESTS = 'itsm_change_requests';
    public const FORM_KEY_CHANGE_REQUEST_DETAILS = 'itsm_change_request_details';

    public const SECURITY_CONTEXT_INCIDENTS = 'app.itsm.incidents';
    public const SECURITY_CONTEXT_SERVICE_REQUESTS = 'app.itsm.service_requests';
    public const SECURITY_CONTEXT_PROBLEMS = 'app.itsm.problems';
    public const SECURITY_CONTEXT_CHANGE_REQUESTS = 'app.itsm.change_requests';

    public function __construct(private readonly ViewBuilderFactoryInterface $viewBuilderFactory)
    {
    }

    public function configureNavigationItems(NavigationItemCollection $navigationItemCollection): void
    {
        $itsm = new NavigationItem(self::NAVIGATION_ITSM);
        $itsm->setLabel(self::NAVIGATION_ITSM);
        $itsm->setIcon('su-list-check');

        $incidents = new NavigationItem(self::VIEW_INCIDENTS);
        $incidents->setLabel(self::VIEW_INCIDENTS);
        $incidents->setView(self::VIEW_INCIDENTS);

        $serviceRequests = new NavigationItem(self::VIEW_SERVICE_REQUESTS);
        $serviceRequests->setLabel(self::VIEW_SERVICE_REQUESTS);
        $serviceRequests->setView(self::VIEW_SERVICE_REQUESTS);

        $problems = new NavigationItem(self::VIEW_PROBLEMS);
        $problems->setLabel(self::VIEW_PROBLEMS);
        $problems->setView(self::VIEW_PROBLEMS);

        $changeRequests = new NavigationItem(self::VIEW_CHANGE_REQUESTS);
        $changeRequests->setLabel(self::VIEW_CHANGE_REQUESTS);
        $changeRequests->setView(self::VIEW_CHANGE_REQUESTS);

        $itsm->addChild($incidents);
        $itsm->addChild($serviceRequests);
        $itsm->addChild($problems);
        $itsm->addChild($changeRequests);
        $navigationItemCollection->add($itsm);
    }

    public function configureViews(ViewCollection $viewCollection): void
    {
        $readOnlyToolbarActions = [];

        $viewCollection->add(
            $this->viewBuilderFactory
                ->createListViewBuilder(self::VIEW_INCIDENTS, '/itsm/incidents')
                ->setResourceKey(self::RESOURCE_KEY_INCIDENTS)
                ->setListKey(self::LIST_KEY_INCIDENTS)
                ->setTitle(self::VIEW_INCIDENTS)
                ->addListAdapters(['table'])
                ->setEditView(self::VIEW_INCIDENTS_DETAIL)
                ->enableSearching()
                ->enableFiltering()
                ->setOption('security_context', self::SECURITY_CONTEXT_INCIDENTS)
        );
        $viewCollection->add(
            $this->viewBuilderFactory
                ->createResourceTabViewBuilder(self::VIEW_INCIDENTS_DETAIL, '/itsm/incidents/:id')
                ->setResourceKey(self::RESOURCE_KEY_INCIDENTS)
                ->setBackView(self::VIEW_INCIDENTS)
                ->setTitleProperty('number')
        );
        $viewCollection->add(
            $this->viewBuilderFactory
                ->createFormViewBuilder(self::VIEW_INCIDENTS_DETAIL_FORM, '/details')
                ->setResourceKey(self::RESOURCE_KEY_INCIDENTS)
                ->setFormKey(self::FORM_KEY_INCIDENT_DETAILS)
                ->setTabTitle('sulu_admin.details')
                ->addToolbarActions($readOnlyToolbarActions)
                ->setParent(self::VIEW_INCIDENTS_DETAIL)
                ->setOption('security_context', self::SECURITY_CONTEXT_INCIDENTS)
        );

        $viewCollection->add(
            $this->viewBuilderFactory
                ->createListViewBuilder(self::VIEW_SERVICE_REQUESTS, '/itsm/service-requests')
                ->setResourceKey(self::RESOURCE_KEY_SERVICE_REQUESTS)
                ->setListKey(self::LIST_KEY_SERVICE_REQUESTS)
                ->setTitle(self::VIEW_SERVICE_REQUESTS)
                ->addListAdapters(['table'])
                ->setEditView(self::VIEW_SERVICE_REQUESTS_DETAIL)
                ->enableSearching()
                ->enableFiltering()
                ->setOption('security_context', self::SECURITY_CONTEXT_SERVICE_REQUESTS)
        );
        $viewCollection->add(
            $this->viewBuilderFactory
                ->createResourceTabViewBuilder(self::VIEW_SERVICE_REQUESTS_DETAIL, '/itsm/service-requests/:id')
                ->setResourceKey(self::RESOURCE_KEY_SERVICE_REQUESTS)
                ->setBackView(self::VIEW_SERVICE_REQUESTS)
                ->setTitleProperty('number')
        );
        $viewCollection->add(
            $this->viewBuilderFactory
                ->createFormViewBuilder(self::VIEW_SERVICE_REQUESTS_DETAIL_FORM, '/details')
                ->setResourceKey(self::RESOURCE_KEY_SERVICE_REQUESTS)
                ->setFormKey(self::FORM_KEY_SERVICE_REQUEST_DETAILS)
                ->setTabTitle('sulu_admin.details')
                ->addToolbarActions($readOnlyToolbarActions)
                ->setParent(self::VIEW_SERVICE_REQUESTS_DETAIL)
                ->setOption('security_context', self::SECURITY_CONTEXT_SERVICE_REQUESTS)
        );

        $viewCollection->add(
            $this->viewBuilderFactory
                ->createListViewBuilder(self::VIEW_PROBLEMS, '/itsm/problems')
                ->setResourceKey(self::RESOURCE_KEY_PROBLEMS)
                ->setListKey(self::LIST_KEY_PROBLEMS)
                ->setTitle(self::VIEW_PROBLEMS)
                ->addListAdapters(['table'])
                ->setEditView(self::VIEW_PROBLEMS_DETAIL)
                ->enableSearching()
                ->enableFiltering()
                ->setOption('security_context', self::SECURITY_CONTEXT_PROBLEMS)
        );
        $viewCollection->add(
            $this->viewBuilderFactory
                ->createResourceTabViewBuilder(self::VIEW_PROBLEMS_DETAIL, '/itsm/problems/:id')
                ->setResourceKey(self::RESOURCE_KEY_PROBLEMS)
                ->setBackView(self::VIEW_PROBLEMS)
                ->setTitleProperty('number')
        );
        $viewCollection->add(
            $this->viewBuilderFactory
                ->createFormViewBuilder(self::VIEW_PROBLEMS_DETAIL_FORM, '/details')
                ->setResourceKey(self::RESOURCE_KEY_PROBLEMS)
                ->setFormKey(self::FORM_KEY_PROBLEM_DETAILS)
                ->setTabTitle('sulu_admin.details')
                ->addToolbarActions($readOnlyToolbarActions)
                ->setParent(self::VIEW_PROBLEMS_DETAIL)
                ->setOption('security_context', self::SECURITY_CONTEXT_PROBLEMS)
        );

        $viewCollection->add(
            $this->viewBuilderFactory
                ->createListViewBuilder(self::VIEW_CHANGE_REQUESTS, '/itsm/change-requests')
                ->setResourceKey(self::RESOURCE_KEY_CHANGE_REQUESTS)
                ->setListKey(self::LIST_KEY_CHANGE_REQUESTS)
                ->setTitle(self::VIEW_CHANGE_REQUESTS)
                ->addListAdapters(['table'])
                ->setEditView(self::VIEW_CHANGE_REQUESTS_DETAIL)
                ->enableSearching()
                ->enableFiltering()
                ->setOption('security_context', self::SECURITY_CONTEXT_CHANGE_REQUESTS)
        );
        $viewCollection->add(
            $this->viewBuilderFactory
                ->createResourceTabViewBuilder(self::VIEW_CHANGE_REQUESTS_DETAIL, '/itsm/change-requests/:id')
                ->setResourceKey(self::RESOURCE_KEY_CHANGE_REQUESTS)
                ->setBackView(self::VIEW_CHANGE_REQUESTS)
                ->setTitleProperty('number')
        );
        $viewCollection->add(
            $this->viewBuilderFactory
                ->createFormViewBuilder(self::VIEW_CHANGE_REQUESTS_DETAIL_FORM, '/details')
                ->setResourceKey(self::RESOURCE_KEY_CHANGE_REQUESTS)
                ->setFormKey(self::FORM_KEY_CHANGE_REQUEST_DETAILS)
                ->setTabTitle('sulu_admin.details')
                ->addToolbarActions($readOnlyToolbarActions)
                ->setParent(self::VIEW_CHANGE_REQUESTS_DETAIL)
                ->setOption('security_context', self::SECURITY_CONTEXT_CHANGE_REQUESTS)
        );
    }

    public function getSecurityContexts(): array
    {
        return [
            self::SULU_ADMIN_SECURITY_SYSTEM => [
                self::NAVIGATION_ITSM => [
                    self::SECURITY_CONTEXT_INCIDENTS => [
                        PermissionTypes::VIEW,
                    ],
                    self::SECURITY_CONTEXT_SERVICE_REQUESTS => [
                        PermissionTypes::VIEW,
                    ],
                    self::SECURITY_CONTEXT_PROBLEMS => [
                        PermissionTypes::VIEW,
                    ],
                    self::SECURITY_CONTEXT_CHANGE_REQUESTS => [
                        PermissionTypes::VIEW,
                    ],
                ],
            ],
        ];
    }
}

