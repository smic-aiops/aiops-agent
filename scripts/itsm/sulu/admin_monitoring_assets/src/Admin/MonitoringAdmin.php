<?php

declare(strict_types=1);

namespace App\Admin;

use Sulu\Bundle\AdminBundle\Admin\Admin;
use Sulu\Bundle\AdminBundle\Admin\Navigation\NavigationItem;
use Sulu\Bundle\AdminBundle\Admin\Navigation\NavigationItemCollection;
use Sulu\Bundle\AdminBundle\Admin\View\ViewBuilderFactoryInterface;
use Sulu\Bundle\AdminBundle\Admin\View\ViewCollection;
use Sulu\Component\Security\Authorization\PermissionTypes;

final class MonitoringAdmin extends Admin
{
    public const NAVIGATION_MONITORING = 'app.monitoring';
    public const VIEW_AI_NODES = 'app.monitoring.ai_nodes';

    public const SECURITY_CONTEXT_AI_NODES = 'app.monitoring.ai_nodes';

    public function __construct(private readonly ViewBuilderFactoryInterface $viewBuilderFactory)
    {
    }

    public function configureNavigationItems(NavigationItemCollection $navigationItemCollection): void
    {
        $monitoring = new NavigationItem(self::NAVIGATION_MONITORING);
        $monitoring->setLabel(self::NAVIGATION_MONITORING);
        $monitoring->setIcon('su-eye');

        $aiNodes = new NavigationItem(self::VIEW_AI_NODES);
        $aiNodes->setLabel(self::VIEW_AI_NODES);
        $aiNodes->setView(self::VIEW_AI_NODES);

        $monitoring->addChild($aiNodes);
        $navigationItemCollection->add($monitoring);
    }

    public function configureViews(ViewCollection $viewCollection): void
    {
        $viewCollection->add(
            $this->viewBuilderFactory
                ->createViewBuilder(self::VIEW_AI_NODES, '/monitoring/ai-nodes', self::VIEW_AI_NODES)
                ->setOption('title', self::VIEW_AI_NODES)
                ->setOption('security_context', self::SECURITY_CONTEXT_AI_NODES)
        );

    }

    public function getSecurityContexts(): array
    {
        return [
            self::SULU_ADMIN_SECURITY_SYSTEM => [
                self::NAVIGATION_MONITORING => [
                    self::SECURITY_CONTEXT_AI_NODES => [
                        PermissionTypes::VIEW,
                    ],
                ],
            ],
        ];
    }
}
