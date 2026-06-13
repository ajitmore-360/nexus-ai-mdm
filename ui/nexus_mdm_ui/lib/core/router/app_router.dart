import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_manager.dart';
import '../../features/auth/presentation/pages/splash_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/shell/presentation/pages/shell_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/entities/presentation/pages/entity_explorer_page.dart';
import '../../features/entities/presentation/pages/entity_detail_page.dart';
import '../../features/match_queue/presentation/pages/match_queue_page.dart';
import '../../features/ai_copilot/presentation/pages/ai_copilot_page.dart';
import '../../features/governance/presentation/pages/governance_page.dart';
import '../../features/analytics/presentation/pages/analytics_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/match_queue/presentation/pages/match_review_page.dart';
import '../../features/merge/presentation/pages/merge_studio_page.dart';
import '../../features/entities/presentation/pages/entity_create_page.dart';
import '../../features/entities/presentation/pages/entity_edit_page.dart';
import '../../features/lineage/presentation/pages/lineage_page.dart';
import '../../features/data_quality/presentation/pages/data_quality_page.dart';
import '../../shared/models/entity.dart';

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
                ],
              ),
              GoRoute(
                path: 'create',
                name: 'entity-create',
                pageBuilder: (context, state) => _buildFadePage(
                  state: state,
                  child: const EntityCreatePage(),
                ),
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
              child: const DashboardPage(section: 'golden'),
            ),
          ),
          GoRoute(
            path: '/dashboard/ai-copilot',
            name: 'ai-copilot',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const AiCopilotPage(),
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
              child: const LineagePage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/governance',
            name: 'governance',
            pageBuilder: (context, state) => _buildFadePage(
              state: state,
              child: const GovernancePage(),
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
    final isSplash = state.matchedLocation == '/splash';
    final isLogin = state.matchedLocation == '/login';

    if (isSplash || isLogin) return null;

    try {
      final loggedIn = await AuthManager.isLoggedIn();
      if (!loggedIn) return '/login';
      return null;
    } catch (e) {
      debugPrint('NEXUS GUARD ERROR: $e');
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
