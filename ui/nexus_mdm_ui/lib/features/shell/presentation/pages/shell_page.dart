import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/license/license_manager.dart';
import '../../../../core/license/licensed_module.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/branding/branding_manager.dart';
import '../../../../shared/widgets/azile_logo.dart';
import '../../../../shared/widgets/command_palette.dart';
import '../../../../shared/models/user.dart';
import '../../../notifications/presentation/pages/notification_center_page.dart';

User _userFromAuth({
  required String name,
  required String email,
  required String role,
  required String tenantId,
  String id = '',
  String tenantName = '',
}) {
  final userRole = role == 'super_admin'
      ? UserRole.productAdmin
      : UserRole.values.firstWhere(
          (r) => r.name == role,
          orElse: () => UserRole.viewer,
        );
  return User(
    id: id,
    email: email,
    name: name.isNotEmpty ? name : email.split('@').first,
    role: userRole,
    tenantId: tenantId,
    tenantName: tenantName,
    createdAt: DateTime(2024),
  );
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Data models for grouped nav
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _NavItem {
  final IconData icon;
  final String label;
  final String route;
  final bool isAi;
  /// If set, the item is hidden when the module is not licensed
  /// (Product Admins always see every item regardless).
  final LicensedModule? module;
  /// Item-level role restriction (independent of the parent group's visibleTo).
  final List<UserRole>? visibleTo;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
    this.isAi = false,
    this.module,
    this.visibleTo,
  });
}

class _NavGroup {
  final String label;
  final List<_NavItem> items;
  /// If non-null, the group is only shown for these roles.
  final List<UserRole>? visibleTo;

  const _NavGroup({
    required this.label,
    required this.items,
    this.visibleTo,
  });
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Shell page
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class ShellPage extends StatefulWidget {
  final Widget child;

  const ShellPage({super.key, required this.child});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  bool _isSidebarExpanded = true;
  int _notificationCount = 0;
  int _matchQueueCount = 0;
  User _currentUser = User(
    id: '', email: '', name: 'Loadingâ€¦', role: UserRole.viewer,
    tenantId: '', tenantName: '', createdAt: DateTime(2024),
  );
  bool _paletteOpen = false;
  Set<LicensedModule> _activeModules = {};

  // â”€â”€ Grouped nav definition â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static const _navGroups = [
    // -- Platform Admin (productAdmin only) -------------------------------------------
    _NavGroup(
      label: 'PLATFORM ADMIN',
      visibleTo: [UserRole.productAdmin],
      items: [
        _NavItem(icon: Icons.admin_panel_settings_outlined, label: 'Tenants',        route: '/dashboard/admin/tenants'),
        _NavItem(icon: Icons.vpn_key_outlined,              label: 'License Manager', route: '/dashboard/admin/license'),
        _NavItem(icon: Icons.monitor_heart_outlined,        label: 'System Health',   route: '/dashboard/admin/health'),
      ],
    ),

    // -- Overview ---------------------------------------------------------------------
    _NavGroup(
      label: 'OVERVIEW',
      visibleTo: [UserRole.productAdmin, UserRole.admin, UserRole.businessAdmin, UserRole.steward, UserRole.viewer],
      items: [
        _NavItem(icon: Icons.home_outlined, label: 'Dashboard', route: '/dashboard'),
      ],
    ),

    // -- 1. Setup (configure once) ----------------------------------------------------
    _NavGroup(
      label: 'SETUP',
      visibleTo: [UserRole.productAdmin, UserRole.admin, UserRole.businessAdmin],
      items: [
        _NavItem(icon: Icons.people_outlined,               label: 'Users & Roles',   route: '/dashboard/org/users'),
        _NavItem(icon: Icons.category_outlined,             label: 'Entity Types',    route: '/dashboard/org/entity-types',
            visibleTo: [UserRole.admin, UserRole.businessAdmin]),
        _NavItem(icon: Icons.filter_alt_outlined, label: 'Blocking Rules', route: '/dashboard/org/blocking-rules',
            visibleTo: [UserRole.admin, UserRole.businessAdmin]),
        _NavItem(icon: Icons.tune_outlined,                 label: 'Attributes',      route: '/dashboard/org/attributes',
            visibleTo: [UserRole.admin, UserRole.businessAdmin]),
        _NavItem(icon: Icons.electrical_services_outlined,  label: 'Source Systems',  route: '/dashboard/org/sources',
            visibleTo: [UserRole.admin, UserRole.businessAdmin]),
        _NavItem(icon: Icons.list_alt_outlined,             label: 'Reference Data',  route: '/dashboard/org/reference-data',
            visibleTo: [UserRole.admin, UserRole.businessAdmin]),
        _NavItem(icon: Icons.policy_outlined,               label: 'Domain Policies', route: '/dashboard/org/domain-policies',
            visibleTo: [UserRole.admin, UserRole.businessAdmin]),
        _NavItem(icon: Icons.security_outlined,             label: 'Enterprise SSO',  route: '/dashboard/org/sso',
            visibleTo: [UserRole.admin, UserRole.businessAdmin]),
        _NavItem(icon: Icons.token_outlined,                label: 'SCIM Tokens',     route: '/dashboard/org/scim-tokens',
            visibleTo: [UserRole.admin, UserRole.businessAdmin]),
        _NavItem(icon: Icons.account_tree_outlined,        label: 'Workflows',        route: '/dashboard/org/workflows',
            visibleTo: [UserRole.admin, UserRole.businessAdmin]),
        _NavItem(icon: Icons.extension_outlined,           label: 'Connectors',       route: '/dashboard/org/connectors',
            visibleTo: [UserRole.admin, UserRole.businessAdmin]),
        _NavItem(icon: Icons.auto_awesome_outlined,        label: 'Enrichment',       route: '/dashboard/org/enrichment',
            visibleTo: [UserRole.admin, UserRole.businessAdmin]),
      ],
    ),

    // -- 2. Data In -------------------------------------------------------------------
    _NavGroup(
      label: 'DATA IN',
      visibleTo: [UserRole.admin, UserRole.steward, UserRole.viewer],
      items: [
        _NavItem(icon: Icons.search_outlined,    label: 'Browse Entities',  route: '/dashboard/entities'),
        _NavItem(icon: Icons.add_circle_outline, label: 'Create Entity',    route: '/dashboard/entities/create',
            visibleTo: [UserRole.admin, UserRole.steward]),
        _NavItem(icon: Icons.upload_outlined,    label: 'Ingest Data',      route: '/dashboard/entities/ingest',
            visibleTo: [UserRole.admin, UserRole.steward]),
        _NavItem(icon: Icons.layers_outlined,    label: 'Bulk Operations',  route: '/dashboard/entities/bulk',
            visibleTo: [UserRole.admin, UserRole.steward]),
      ],
    ),

    // -- 3. Review & Quality ----------------------------------------------------------
    _NavGroup(
      label: 'REVIEW & QUALITY',
      visibleTo: [UserRole.admin, UserRole.steward, UserRole.viewer],
      items: [
        _NavItem(icon: Icons.verified_outlined,     label: 'Data Quality',    route: '/dashboard/data-quality',
            module: LicensedModule.dataQuality),
        _NavItem(icon: Icons.bar_chart_outlined,    label: 'Data Profiling',  route: '/dashboard/data-profiling',
            module: LicensedModule.dataQuality),
        _NavItem(icon: Icons.admin_panel_settings_outlined, label: 'Data Governance', route: '/dashboard/org/data-governance',
            visibleTo: [UserRole.admin, UserRole.businessAdmin]),
      ],
    ),

    // -- 4. Match & Merge -------------------------------------------------------------
    _NavGroup(
      label: 'MATCH & MERGE',
      visibleTo: [UserRole.admin, UserRole.steward],
      items: [
        _NavItem(icon: Icons.gps_fixed_outlined,   label: 'Match Queue',     route: '/dashboard/match-queue'),
        _NavItem(icon: Icons.merge_outlined,        label: 'Merge Studio',    route: '/dashboard/merge-studio'),
        _NavItem(icon: Icons.star_outline,          label: 'Golden Records',  route: '/dashboard/golden-records'),
        _NavItem(icon: Icons.tune_outlined,         label: 'Matching Rules',  route: '/dashboard/matching-rules',
            visibleTo: [UserRole.admin]),
      ],
    ),

    // -- 5. Govern & Approve ----------------------------------------------------------
    _NavGroup(
      label: 'GOVERN & APPROVE',
      visibleTo: [UserRole.admin, UserRole.steward],
      items: [
        _NavItem(icon: Icons.pending_actions_outlined, label: 'Pending Approvals', route: '/dashboard/pending-approvals'),
        _NavItem(icon: Icons.task_alt_outlined,        label: 'Tasks',             route: '/dashboard/tasks'),
        _NavItem(icon: Icons.shield_outlined,          label: 'Policy Rules',      route: '/dashboard/governance?tab=0',
            module: LicensedModule.governance,
            visibleTo: [UserRole.admin]),
        _NavItem(icon: Icons.merge_type_outlined,      label: 'Survivorship',      route: '/dashboard/governance?tab=1',
            module: LicensedModule.governance,
            visibleTo: [UserRole.admin]),
        _NavItem(icon: Icons.gpp_good_outlined,        label: 'GDPR / Consent',    route: '/dashboard/governance?tab=3',
            module: LicensedModule.governance,
            visibleTo: [UserRole.admin]),
        _NavItem(icon: Icons.notifications_outlined,   label: 'Notifications',     route: '/dashboard/notifications'),
      ],
    ),

    // -- 6. Data Out ------------------------------------------------------------------
    _NavGroup(
      label: 'DATA OUT',
      visibleTo: [UserRole.admin, UserRole.steward, UserRole.viewer],
      items: [
        _NavItem(icon: Icons.satellite_alt_outlined,  label: 'Distribution',    route: '/dashboard/distribution',
            module: LicensedModule.distribution,
            visibleTo: [UserRole.admin]),
        _NavItem(icon: Icons.account_tree_outlined,   label: 'Lineage',         route: '/dashboard/lineage',
            module: LicensedModule.lineage),
      ],
    ),

    // -- 7. Measure -------------------------------------------------------------------
    _NavGroup(
      label: 'MEASURE',
      visibleTo: [UserRole.admin, UserRole.steward, UserRole.viewer],
      items: [
        _NavItem(icon: Icons.analytics_outlined,    label: 'Analytics',         route: '/dashboard/analytics',
            module: LicensedModule.analytics),
        _NavItem(icon: Icons.score_outlined,        label: 'Quality Analytics', route: '/dashboard/quality-analytics',
            module: LicensedModule.analytics),
        _NavItem(icon: Icons.auto_awesome_outlined, label: 'AI Prism',          route: '/dashboard/ai-prism', isAi: true,
            module: LicensedModule.aiPrism),
      ],
    ),
  ];
  List<_NavItem> get _bottomNavItems => [
    const _NavItem(icon: Icons.home_outlined, label: 'Dashboard', route: '/dashboard'),
    const _NavItem(icon: Icons.search_outlined, label: 'Explorer', route: '/dashboard/entities'),
    const _NavItem(icon: Icons.gps_fixed_outlined, label: 'Queue', route: '/dashboard/match-queue'),
    const _NavItem(icon: Icons.auto_awesome_outlined, label: 'AI', route: '/dashboard/ai-prism', isAi: true),
    if (_currentUser.canManageSettings)
      const _NavItem(icon: Icons.settings_outlined, label: 'Settings', route: '/dashboard/settings')
    else
      const _NavItem(icon: Icons.person_outline, label: 'Profile', route: '/dashboard/profile'),
  ];

  // â”€â”€ Lifecycle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadUnreadCount();
    _loadMatchQueueCount();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  Future<void> _loadUnreadCount() async {
    try {
      final resp = await ApiClient().get<Map<String, dynamic>>(
        '${AppConstants.notificationsPath}/unread-count',
      );
      final count = resp.data?['unread_count'] as int? ?? 0;
      if (mounted) setState(() => _notificationCount = count);
    } catch (_) {}
  }

  Future<void> _loadMatchQueueCount() async {
    try {
      final resp = await ApiClient().get<Map<String, dynamic>>(
        '${AppConstants.matchQueuePath}/queue-metrics',
      );
      final data = resp.data?['data'] as Map<String, dynamic>?;
      final count = data?['pending_total'] as int? ?? 0;
      if (mounted) setState(() => _matchQueueCount = count);
    } catch (_) {}
  }

  /// Returns a live badge string for routes backed by real counts,
  /// null if there is nothing to show.
  String? _liveBadge(_NavItem item) {
    if (item.route == '/dashboard/match-queue' && _matchQueueCount > 0) {
      return _matchQueueCount > 99 ? '99+' : '$_matchQueueCount';
    }
    if (item.route == '/dashboard/notifications' && _notificationCount > 0) {
      return _notificationCount > 9 ? '9+' : '$_notificationCount';
    }
    return null;
  }

  Future<void> _loadCurrentUser() async {
    final results = await Future.wait([
      AuthManager.getUserName(),
      AuthManager.getUserEmail(),
      AuthManager.getUserRole(),
      AuthManager.getTenantId(),
      AuthManager.getUserId(),
      AuthManager.getTenantName(),
    ]);
    final name       = results[0] ?? '';
    final email      = results[1] ?? '';
    final role       = results[2] ?? 'viewer';
    final tenantId   = results[3] ?? '';
    final userId     = results[4] ?? '';
    final tenantName = results[5] ?? '';
    final modules    = await LicenseManager.getActiveModules();
    if (!mounted) return;
    setState(() {
      _currentUser = _userFromAuth(
        name: name, email: email, role: role, tenantId: tenantId,
        id: userId, tenantName: tenantName,
      );
      _activeModules = modules;
    });
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    if ((ctrl || meta) && event.logicalKey == LogicalKeyboardKey.keyK) {
      if (!_paletteOpen && mounted) {
        _paletteOpen = true;
        showCommandPalette(context).then((_) {
          if (mounted) setState(() => _paletteOpen = false);
        });
      }
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    super.dispose();
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < AppConstants.mobileBreakpoint;
    final isTablet = screenWidth < AppConstants.tabletBreakpoint;

    if (isMobile) return _buildMobileLayout(context);
    return _buildDesktopLayout(context, isTablet);
  }

  Widget _buildDesktopLayout(BuildContext context, bool isTablet) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Row(
        children: [
          AnimatedContainer(
            duration: AppConstants.animNormal,
            curve: Curves.easeInOut,
            width: _isSidebarExpanded
                ? AppConstants.sidebarWidth
                : AppConstants.sidebarCollapsedWidth,
            child: _buildSidebar(context),
          ),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: _buildMobileAppBar(context),
      body: widget.child,
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  PreferredSizeWidget _buildMobileAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.cardSurface,
      leading: const Padding(
        padding: EdgeInsets.all(12),
        child: AzileLogo(size: 28, showText: false),
      ),
      title: Text(BrandingManager.productName, style: AppTextStyles.titleMedium),
      actions: [
        _buildNotificationButton(),
        _buildUserAvatar(compact: true),
        const SizedBox(width: 8),
      ],
    );
  }

  // â”€â”€ Sidebar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildSidebar(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.sidebarBackground,
        border: Border(
          right: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Logo area
          Container(
            height: AppConstants.topBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.divider, width: 1),
              ),
            ),
            child: Row(
              children: [
                AzileLogo(
                  size: 32,
                  showText: _isSidebarExpanded,
                ),
                if (_isSidebarExpanded) const Spacer(),
                IconButton(
                  onPressed: () =>
                      setState(() => _isSidebarExpanded = !_isSidebarExpanded),
                  icon: Icon(
                    _isSidebarExpanded
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: AppColors.secondaryText,
                  ),
                  tooltip: _isSidebarExpanded ? 'Collapse' : 'Expand',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),

          // Nav groups
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: _buildNavGroups(context, location),
            ),
          ),

          // Bottom section
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.divider, width: 1),
              ),
            ),
            child: Column(
              children: [
                if (_currentUser.canManageSettings)
                  _buildNavItemWidget(
                    context,
                    const _NavItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      route: '/dashboard/settings',
                    ),
                    location.startsWith('/dashboard/settings'),
                  ),
                const SizedBox(height: 8),
                _buildUserTile(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildNavGroups(BuildContext context, String location) {
    final isProductAdmin = _currentUser.isProductAdmin;
    final widgets = <Widget>[];

    for (final group in _navGroups) {
      // Group-level role check
      if (group.visibleTo != null &&
          !group.visibleTo!.contains(_currentUser.role)) {
        continue;
      }

      // Filter items by item-level role and license
      final visibleItems = group.items.where((item) {
        if (item.visibleTo != null &&
            !item.visibleTo!.contains(_currentUser.role)) {
          return false;
        }
        if (item.module != null &&
            !isProductAdmin &&
            !_activeModules.contains(item.module)) {
          return false;
        }
        return true;
      }).toList();

      if (visibleItems.isEmpty) continue;

      widgets.add(_buildGroupHeader(group.label));
      for (final item in visibleItems) {
        final isActive = _isRouteActive(location, item.route);
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: _buildNavItemWidget(context, item, isActive),
          ),
        );
      }
      widgets.add(const SizedBox(height: 4));
    }
    return widgets;
  }

  Widget _buildGroupHeader(String label) {
    if (!_isSidebarExpanded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Divider(color: AppColors.divider, height: 1),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          fontSize: 10,
          color: AppColors.mutedText,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  bool _isRouteActive(String location, String route) {
    if (route == '/dashboard') return location == '/dashboard';
    // Strip query parameters from the nav route before matching
    final routePath = route.contains('?') ? route.split('?').first : route;
    return location.startsWith(routePath);
  }

  Widget _buildNavItemWidget(
      BuildContext context, _NavItem item, bool isActive) {
    return Tooltip(
      message: _isSidebarExpanded ? '' : item.label,
      preferBelow: false,
      child: InkWell(
        onTap: () {
          if (item.route == '/dashboard/notifications') {
            _showNotificationsPanel();
          } else {
            // Parse query parameters from the route definition and pass them through
            final routeParts = item.route.split('?');
            if (routeParts.length > 1) {
              final queryString = routeParts[1];
              final params = Map.fromEntries(
                queryString.split('&').map((kv) {
                  final parts = kv.split('=');
                  return MapEntry(parts[0], parts.length > 1 ? parts[1] : '');
                }),
              );
              context.go(routeParts[0], extra: params);
            } else {
              context.go(item.route);
            }
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: isActive
                    ? AppColors.primary
                    : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              // Emoji icon
              SizedBox(
                width: 20,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      item.icon,
                      size: 18,
                      color: isActive ? AppColors.primary : AppColors.secondaryText,
                    ),
                    if (_liveBadge(item) != null && !_isSidebarExpanded)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          constraints: const BoxConstraints(
                              minWidth: 14, minHeight: 14),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            _liveBadge(item)!,
                            style: AppTextStyles.badgeLabel.copyWith(
                              color: Colors.white,
                              fontSize: 8,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    if (item.isAi && !_isSidebarExpanded)
                      const Positioned(
                        right: -4,
                        bottom: -4,
                        child: _AiPulseDot(),
                      ),
                  ],
                ),
              ),

              if (_isSidebarExpanded) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: AppTextStyles.sidebarItem.copyWith(
                      color: isActive
                          ? AppColors.primaryText
                          : AppColors.secondaryText,
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.isAi) const _AiPulseDot(),
                if (_liveBadge(item) != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _liveBadge(item)!,
                      style: AppTextStyles.badgeLabel.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserTile() {
    if (!_isSidebarExpanded) {
      return Tooltip(
        message: _currentUser.name,
        child: CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.primary.withValues(alpha: 0.2),
          child: Text(
            _currentUser.initials,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.sidebarSelected,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withValues(alpha: 0.2),
            child: Text(
              _currentUser.initials,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentUser.name,
                  style: AppTextStyles.labelMedium.copyWith(
                    overflow: TextOverflow.ellipsis,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _currentUser.roleDisplayName,
                  style: AppTextStyles.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined,
                size: 16, color: AppColors.secondaryText),
            onPressed: _handleLogout,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 24, minHeight: 24),
            tooltip: 'Sign out',
          ),
        ],
      ),
    );
  }

  // â”€â”€ Top bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildTopBar(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final title = _getPageTitle(location);

    return Container(
      height: AppConstants.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          Text(title, style: AppTextStyles.titleMedium),
          const SizedBox(width: 24),

          // Global search
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: GestureDetector(
                onTap: () {
                  if (!_paletteOpen) {
                    _paletteOpen = true;
                    showCommandPalette(context).then((_) {
                      if (mounted) setState(() => _paletteOpen = false);
                    });
                  }
                },
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.navyBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded,
                          size: 16, color: AppColors.mutedText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Search pages, actions, recordsâ€¦',
                          style: AppTextStyles.inputHint.copyWith(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const _KeyboardShortcutHint(text: 'âŒ˜K'),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const Spacer(),
          _buildNotificationButton(),
          const SizedBox(width: 8),
          _buildUserAvatar(),
        ],
      ),
    );
  }

  Widget _buildNotificationButton() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: _showNotificationsPanel,
          tooltip: 'Notifications',
          style: IconButton.styleFrom(
            foregroundColor: AppColors.secondaryText,
          ),
        ),
        if (_notificationCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(3),
              constraints:
                  const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.cardSurface, width: 1.5),
              ),
              child: Text(
                _notificationCount > 9 ? '9+' : '$_notificationCount',
                style: AppTextStyles.badgeLabel.copyWith(
                  color: Colors.white,
                  fontSize: 9,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUserAvatar({bool compact = false}) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      tooltip: '',
      child: Container(
        padding: compact
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.elevatedCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
              child: Text(
                _currentUser.initials,
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              Text(_currentUser.name.split(' ').first,
                  style: AppTextStyles.labelMedium),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 16, color: AppColors.secondaryText),
            ],
          ],
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_currentUser.name, style: AppTextStyles.titleSmall),
              Text(_currentUser.email, style: AppTextStyles.bodySmall),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _currentUser.roleDisplayName,
                  style: AppTextStyles.badgeLabel
                      .copyWith(color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'profile',
          child: Row(children: [
            Icon(Icons.person_outline, size: 16),
            SizedBox(width: 8),
            Text('Profile'),
          ]),
        ),
        if (_currentUser.canManageSettings)
          const PopupMenuItem(
            value: 'settings',
            child: Row(children: [
              Icon(Icons.settings_outlined, size: 16),
              SizedBox(width: 8),
              Text('Settings'),
            ]),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: Row(children: [
            Icon(Icons.logout_outlined,
                size: 16, color: AppColors.error),
            SizedBox(width: 8),
            Text('Sign out',
                style: TextStyle(color: AppColors.error)),
          ]),
        ),
      ],
      onSelected: (value) {
        if (value == 'logout') _handleLogout();
        if (value == 'profile') context.go('/dashboard/profile');
        if (value == 'settings') context.go('/dashboard/settings');
      },
    );
  }

  // â”€â”€ Mobile bottom nav â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildBottomNav(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    int currentIndex = 0;
    for (int i = 0; i < _bottomNavItems.length; i++) {
      if (_isRouteActive(location, _bottomNavItems[i].route)) {
        currentIndex = i;
        break;
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (i) => context.go(_bottomNavItems[i].route),
        backgroundColor: Colors.transparent,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.secondaryText,
        type: BottomNavigationBarType.fixed,
        items: _bottomNavItems
            .map((item) => BottomNavigationBarItem(
                  icon: Icon(item.icon),
                  label: item.label,
                ))
            .toList(),
      ),
    );
  }

  // â”€â”€ Page title map â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String _getPageTitle(String location) {
    if (location == '/dashboard') return 'Dashboard';
    if (location.startsWith('/dashboard/admin/health')) return 'System Health';
    if (location.startsWith('/dashboard/admin/tenants')) return 'Tenants';
    if (location.startsWith('/dashboard/org/users')) return 'Users & Roles';
    if (location.startsWith('/dashboard/org/entity-types')) return 'Entity Types';
    if (location.startsWith('/dashboard/org/blocking-rules')) return 'Blocking Rules';
    if (location.startsWith('/dashboard/org/attributes')) return 'Attribute Schema';
    if (location.startsWith('/dashboard/org/sources')) return 'Source Systems';
    if (location.startsWith('/dashboard/org/domain-policies')) return 'Domain Policies';
    if (location.startsWith('/dashboard/org/data-governance')) return 'Data Governance';
    if (location.startsWith('/dashboard/org/reference-data')) return 'Reference Data';
    if (location.startsWith('/dashboard/entities/create')) return 'Create Entity';
    if (location.startsWith('/dashboard/entities/ingest')) return 'Ingest Data';
    if (location.startsWith('/dashboard/entities')) return 'Entity Explorer';
    if (location.startsWith('/dashboard/match-queue')) return 'Match Queue';
    if (location.startsWith('/dashboard/merge-studio')) return 'Merge Studio';
    if (location.startsWith('/dashboard/matching-rules')) return 'Matching Rules';
    if (location.startsWith('/dashboard/merge')) return 'Merge Studio';
    if (location.startsWith('/dashboard/golden-records')) return 'Golden Records';
    if (location.startsWith('/dashboard/ai-prism')) return 'AI Prism';
    if (location.startsWith('/dashboard/data-quality')) return 'Data Quality';
    if (location.startsWith('/dashboard/lineage')) return 'Data Lineage';
    if (location.startsWith('/dashboard/governance')) return 'Governance';
    if (location.startsWith('/dashboard/analytics')) return 'Analytics';
    if (location.startsWith('/dashboard/distribution')) return 'Distribution Monitor';
    if (location.startsWith('/dashboard/notifications')) return 'Notifications';
    if (location.startsWith('/dashboard/settings')) return 'Settings';
    if (location.startsWith('/dashboard/profile')) return 'My Profile';
    if (location.startsWith('/dashboard/org/sso')) return 'Enterprise SSO';
    if (location.startsWith('/dashboard/org/scim-tokens')) return 'SCIM 2.0 Provisioning';
    if (location.startsWith('/dashboard/org/workflows')) return 'Workflow Engine';
    if (location.startsWith('/dashboard/org/connectors')) return 'Connector Marketplace';
    if (location.startsWith('/dashboard/org/enrichment')) return 'Third-Party Enrichment';
    return BrandingManager.productName;
  }

  void _showNotificationsPanel() {
    showNotificationCenter(
      context,
      onDismiss: () {
        // Re-fetch the live count after the panel closes â€” the user may have
        // read some notifications but not all.
        _loadUnreadCount();
      },
    );
  }

  Future<void> _handleLogout() async {
    await AuthManager.logout();
    if (mounted) context.go('/login');
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Private helper widgets
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _KeyboardShortcutHint extends StatelessWidget {
  final String text;
  const _KeyboardShortcutHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.elevatedCard,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(
          text,
          style: AppTextStyles.labelSmall.copyWith(fontSize: 10),
        ),
      ),
    );
  }
}

class _AiPulseDot extends StatefulWidget {
  const _AiPulseDot();

  @override
  State<_AiPulseDot> createState() => _AiPulseDotState();
}

class _AiPulseDotState extends State<_AiPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 0.8, end: 1.35).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.4, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Opacity(
              opacity: _opacity.value,
              child: Transform.scale(
                scale: _scale.value,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.aiPurple.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              gradient: AppColors.purpleGradient,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
