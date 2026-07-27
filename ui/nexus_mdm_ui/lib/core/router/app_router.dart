import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_manager.dart';
import '../../features/auth/presentation/pages/splash_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/activate_page.dart';
import '../../features/auth/presentation/pages/forgot_password_page.dart';
import '../../features/auth/presentation/pages/reset_password_page.dart';
import '../../features/shell/presentation/pages/shell_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/entities/presentation/pages/entity_explorer_page.dart';
import '../../features/entities/presentation/pages/entity_detail_page.dart';
import '../../features/match_queue/presentation/pages/match_queue_page.dart';
import '../../features/ai_prism/presentation/pages/ai_prism_page.dart';
import '../../features/governance/presentation/pages/governance_page.dart';
import '../../features/analytics/presentation/pages/analytics_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/match_queue/presentation/pages/match_review_page.dart';
import '../../features/merge/presentation/pages/merge_studio_page.dart';
import '../../features/entities/presentation/pages/entity_create_page.dart';
import '../../features/entities/presentation/pages/entity_edit_page.dart';
import '../../features/lineage/presentation/pages/lineage_page.dart';
import '../../features/data_quality/presentation/pages/data_quality_page.dart';
import '../../features/golden_records/presentation/pages/golden_records_page.dart';
import '../../features/distribution/presentation/pages/distribution_monitor_page.dart';
import '../../shared/models/entity.dart';
import '../../features/admin/presentation/pages/tenants_page.dart';
import '../../features/admin/presentation/pages/tenant_create_page.dart';
import '../../features/admin/presentation/pages/tenant_detail_page.dart';
import '../../features/admin/presentation/pages/users_page.dart';
import '../../features/admin/presentation/pages/entity_types_page.dart';
import '../../features/admin/presentation/pages/attribute_schema_page.dart';
import '../../features/admin/presentation/pages/source_systems_page.dart';
import '../../features/admin/presentation/pages/license_page.dart';
import '../../features/admin/presentation/pages/system_health_page.dart';
import '../../features/ingest/presentation/pages/ingest_data_page.dart';
import '../../features/match_queue/presentation/pages/matching_rules_page.dart';
import '../../features/admin/presentation/pages/data_governance_page.dart';
import '../../features/admin/presentation/pages/approval_queue_page.dart';
import '../../features/admin/presentation/pages/domain_policy_page.dart';
import '../../features/admin/presentation/pages/submasters_page.dart';
import '../../features/auth/presentation/pages/auth_callback_page.dart';
import '../../features/tasks/presentation/pages/tasks_page.dart';
import '../../features/entities/presentation/pages/entity_xrefs_page.dart';
import '../../features/entities/presentation/pages/entity_comments_page.dart';
import '../../features/entities/presentation/pages/entity_history_page.dart';
import '../../features/entities/presentation/pages/entity_hierarchy_page.dart';
import '../../features/entities/presentation/pages/entity_unmerge_page.dart';
import '../../features/entities/presentation/pages/bulk_operations_page.dart';
import '../../features/analytics/presentation/pages/quality_analytics_page.dart';
import '../../features/data_quality/presentation/pages/data_profiling_page.dart';
import '../../features/admin/presentation/pages/sso_config_page.dart';
import '../../features/admin/presentation/pages/scim_tokens_page.dart';
import '../../features/admin/presentation/pages/workflow_builder_page.dart';
import '../../features/admin/presentation/pages/connector_marketplace_page.dart';
import '../../features/admin/presentation/pages/enrichment_config_page.dart';

class AppRouter {
  AppRouter._();

  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    redirect: _guard,
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const SplashPage(),
        ),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const LoginPage(),
        ),
      ),
      GoRoute(
        path: '/activate',
        name: 'activate',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: ActivatePage(
            token: state.uri.queryParameters['token'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgot-password',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const ForgotPasswordPage(),
        ),
      ),
      GoRoute(
        path: '/reset-password',
        name: 'reset-password',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: ResetPasswordPage(
            token: state.uri.queryParameters['token'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/auth-callback',
        name: 'auth-callback',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: AuthCallbackPage(
            code:             state.uri.queryParameters['code'],
            error:            state.uri.queryParameters['error'],
            errorDescription: state.uri.queryParameters['error_description'],
          ),
        ),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        pageBuilder: (context, state, child) => _buildPage(
          state: state,
          child: ShellPage(child: child),
        ),
        routes: [
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const DashboardPage(),
            ),
          ),
          // /dashboard/entities/create and /dashboard/entities/ingest are
          // registered BEFORE the entities explorer so GoRouter never treats
          // "create" or "ingest" as an entity UUID via the :id wildcard.
          GoRoute(
            path: '/dashboard/entities/create',
            name: 'entity-create',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const EntityCreatePage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/entities/ingest',
            name: 'ingest-data',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const IngestDataPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/entities/bulk',
            name: 'entity-bulk',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const BulkOperationsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/entities',
            name: 'entities',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const EntityExplorerPage(),
            ),
            routes: [
              GoRoute(
                path: ':id',
                name: 'entity-detail',
                pageBuilder: (context, state) => _buildFadePage(
                  state: state,
                  child: EntityDetailPage(
                    entityId: state.pathParameters['id']!,
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    name: 'entity-edit',
                    pageBuilder: (context, state) => _buildFadePage(
                      state: state,
                      child: EntityEditPage(
                        entityId: state.pathParameters['id']!,
                        entity: state.extra as CanonicalEntity?,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'xrefs',
                    name: 'entity-xrefs',
                    pageBuilder: (context, state) => _buildFadePage(
                      state: state,
                      child: EntityXrefsPage(entityId: state.pathParameters['id']!),
                    ),
                  ),
                  GoRoute(
                    path: 'comments',
                    name: 'entity-comments',
                    pageBuilder: (context, state) => _buildFadePage(
                      state: state,
                      child: EntityCommentsPage(entityId: state.pathParameters['id']!),
                    ),
                  ),
                  GoRoute(
                    path: 'history',
                    name: 'entity-history',
                    pageBuilder: (context, state) => _buildFadePage(
                      state: state,
                      child: EntityHistoryPage(entityId: state.pathParameters['id']!),
                    ),
                  ),
                  GoRoute(
                    path: 'hierarchy',
                    name: 'entity-hierarchy',
                    pageBuilder: (context, state) => _buildFadePage(
                      state: state,
                      child: EntityHierarchyPage(
                        entityId: state.pathParameters['id']!,
                        entityName: state.uri.queryParameters['name'] ?? '',
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'unmerge',
                    name: 'entity-unmerge',
                    pageBuilder: (context, state) => _buildFadePage(
                      state: state,
                      child: EntityUnmergePage(entityId: state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/dashboard/match-queue',
            name: 'match-queue',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const MatchQueuePage(),
            ),
            routes: [
              GoRoute(
                path: 'review/:id',
                name: 'match-review',
                pageBuilder: (context, state) => _buildFadePage(
                  state: state,
                  child: MatchReviewPage(
                    matchId: state.pathParameters['id']!,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/dashboard/merge-studio',
            name: 'merge-studio',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const MatchQueuePage(mergeMode: true),
            ),
          ),
          GoRoute(
            path: '/dashboard/merge/:sourceId/:candidateId',
            name: 'merge',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: MergeStudioPage(
                sourceId:    state.pathParameters['sourceId']!,
                candidateId: state.pathParameters['candidateId']!,
              ),
            ),
          ),
          GoRoute(
            path: '/dashboard/golden-records',
            name: 'golden-records',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const GoldenRecordsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/distribution',
            name: 'distribution',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const DistributionMonitorPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/ai-prism',
            name: 'ai-prism',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const AiPrismPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/data-quality',
            name: 'data-quality',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const DataQualityPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/lineage',
            name: 'lineage',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: LineagePage(
                entityId: state.uri.queryParameters['entity_id'],
              ),
            ),
          ),
          GoRoute(
            path: '/dashboard/governance',
            name: 'governance',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: GovernancePage(
                initialTab: int.tryParse(
                    state.uri.queryParameters['tab'] ?? '') ?? 0,
              ),
            ),
          ),
          GoRoute(
            path: '/dashboard/analytics',
            name: 'analytics',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const AnalyticsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/settings',
            name: 'settings',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const SettingsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/profile',
            name: 'profile',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const ProfilePage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/admin/tenants',
            name: 'admin-tenants',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const TenantsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/admin/tenants/create',
            name: 'admin-tenants-create',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const TenantCreatePage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/admin/tenants/:id',
            name: 'admin-tenant-detail',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: TenantDetailPage(
                tenantId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: '/dashboard/admin/license',
            name: 'admin-license',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const LicenseManagementPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/admin/health',
            name: 'admin-health',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const SystemHealthPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/org/users',
            name: 'org-users',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const UsersPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/org/entity-types',
            name: 'org-entity-types',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const EntityTypesPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/org/attributes',
            name: 'org-attributes',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const AttributeSchemaPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/org/sources',
            name: 'org-sources',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const SourceSystemsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/org/data-governance',
            name: 'data-governance',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const DataGovernancePage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/pending-approvals',
            name: 'pending-approvals',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const ApprovalQueuePage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/matching-rules',
            name: 'matching-rules',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const MatchingRulesPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/org/domain-policies',
            name: 'domain-policies',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const DomainPolicyPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/org/reference-data',
            name: 'reference-data',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const SubmastersPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/tasks',
            name: 'tasks',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const TasksPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/quality-analytics',
            name: 'quality-analytics',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const QualityAnalyticsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/data-profiling',
            name: 'data-profiling',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const DataProfilingPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/org/sso',
            name: 'org-sso',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const SsoConfigPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/org/scim-tokens',
            name: 'org-scim-tokens',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const ScimTokensPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/org/workflows',
            name: 'org-workflows',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const WorkflowBuilderPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/org/connectors',
            name: 'org-connectors',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const ConnectorMarketplacePage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/org/enrichment',
            name: 'org-enrichment',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const EnrichmentConfigPage(),
            ),
          ),
        ],
      ),
    ],
    errorPageBuilder: (context, state) => _buildPage(
      state: state,
      child: _ErrorPage(error: state.error.toString()),
    ),
  );

  static Future<String?> _guard(
      BuildContext context, GoRouterState state) async {
    final loc = state.matchedLocation;

    // On Flutter Web, visiting the root URL '/' falls through here.
    // Redirect to splash so the normal boot sequence plays.
    if (loc == '/' || loc.isEmpty) return '/splash';

    final isSplash         = loc == '/splash';
    final isLogin          = loc == '/login';
    final isActivate       = loc == '/activate';
    final isForgotPassword = loc == '/forgot-password';
    final isResetPassword  = loc == '/reset-password';
    final isAuthCallback   = loc == '/auth-callback';

    if (isSplash || isLogin || isActivate || isForgotPassword || isResetPassword || isAuthCallback) return null;

    try {
      final loggedIn = await AuthManager.isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!loggedIn) return '/login';

      // Role guard — only admin and steward may write entity data
      const dataWriteRoutes = {
        '/dashboard/entities/create',
        '/dashboard/entities/ingest',
        '/dashboard/entities/bulk',
      };
      if (dataWriteRoutes.contains(loc)) {
        final role = await AuthManager.getUserRole() ?? '';
        if (!{'admin', 'steward', 'super_admin'}.contains(role)) {
          return '/dashboard';
        }
      }

      // Steward cannot access Settings; redirect to their Profile page instead
      if (loc == '/dashboard/settings') {
        final role = await AuthManager.getUserRole() ?? '';
        if (role == 'steward') return '/dashboard/profile';
      }

      return null;
    } catch (e) {
      debugPrint('AZILE GUARD ERROR: $e');
      return '/login';
    }
  }

  static Page<dynamic> _buildPage({
    required GoRouterState state,
    required Widget child,
  }) {
    return MaterialPage(
      key: state.pageKey,
      child: child,
    );
  }

  static Page<dynamic> _buildFadePage({
    required GoRouterState state,
    required Widget child,
  }) {
    return CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (context, animation, _, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          ),
          child: child,
        );
      },
    );
  }
}

class _ErrorPage extends StatelessWidget {
  final String error;
  const _ErrorPage({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Page not found', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(error, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
