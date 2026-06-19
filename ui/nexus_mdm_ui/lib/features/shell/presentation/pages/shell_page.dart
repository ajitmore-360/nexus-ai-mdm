import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/nexus_logo.dart';
import '../../../../shared/widgets/command_palette.dart';
import '../../../../shared/models/user.dart';
import '../../../notifications/presentation/pages/notification_center_page.dart';

User _userFromAuth({
  required String name,
  required String email,
  required String role,
  required String tenantId,
}) {
  final userRole = UserRole.values.firstWhere(
    (r) => r.name == role,
    orElse: () => UserRole.viewer,
  );
  return User(
    id: '',
    email: email,
    name: name.isNotEmpty ? name : email.split('@').first,
    role: userRole,
    tenantId: tenantId,
    tenantName: '',
    createdAt: DateTime(2024),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models for grouped nav
// ─────────────────────────────────────────────────────────────────────────────

class _NavItem {
  final String emoji;
  final String label;
  final String route;
  final String? badge;
  final bool isAi;

  const _NavItem({
    required this.emoji,
    required this.label,
    required this.route,
    this.badge,
    this.isAi = false,
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

// ─────────────────────────────────────────────────────────────────────────────
// Shell page
// ─────────────────────────────────────────────────────────────────────────────

class ShellPage extends StatefulWidget {
  final Widget child;

  const ShellPage({super.key, required this.child});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  bool _isSidebarExpanded = true;
  int _notificationCount = 5;
  User _currentUser = User.demo;
  bool _paletteOpen = false;

  // ── Grouped nav definition ────────────────────────────────────────────────

  static const _navGroups = [
    _NavGroup(
      label: 'OVERVIEW',
      items: [
        _NavItem(emoji: '🏠', label: 'Dashboard', route: '/dashboard'),
      ],
    ),
    _NavGroup(
      label: 'PLATFORM',
      // Visible only to admin (maps to superAdmin concept in this codebase)
      visibleTo: [UserRole.admin],
      items: [
        _NavItem(emoji: '👑', label: 'Tenants', route: '/dashboard/admin/tenants'),
        _NavItem(emoji: '🔧', label: 'System', route: '/dashboard/settings'),
      ],
    ),
    _NavGroup(
      label: 'ORG SETUP',
      visibleTo: [UserRole.admin, UserRole.steward],
      items: [
        _NavItem(emoji: '👥', label: 'Users & Roles', route: '/dashboard/org/users'),
        _NavItem(emoji: '#️⃣', label: 'Entity Types', route: '/dashboard/org/entity-types'),
        _NavItem(emoji: '🗂', label: 'Attributes', route: '/dashboard/org/attributes'),
        _NavItem(emoji: '🔌', label: 'Source Systems', route: '/dashboard/org/sources'),
      ],
    ),
    _NavGroup(
      label: 'ENTITIES',
      items: [
        _NavItem(emoji: '🔍', label: 'Browse & Search', route: '/dashboard/entities'),
        _NavItem(emoji: '✨', label: 'Create Entity', route: '/dashboard/entities/create'),
        _NavItem(emoji: '📥', label: 'Ingest Data', route: '/dashboard/entities/ingest'),
      ],
    ),
    _NavGroup(
      label: 'MDM WORKFLOW',
      items: [
        _NavItem(emoji: '🎯', label: 'Match Queue', route: '/dashboard/match-queue', badge: '12'),
        _NavItem(emoji: '🔀', label: 'Merge Studio', route: '/dashboard/merge/select/select'),
        _NavItem(emoji: '⭐', label: 'Golden Records', route: '/dashboard/golden-records'),
        _NavItem(emoji: '📡', label: 'Distribution', route: '/dashboard/distribution'),
        _NavItem(emoji: '🔔', label: 'Notifications', route: '/dashboard/notifications', badge: '5'),
      ],
    ),
  ];

  static const _bottomNavItems = [
    _NavItem(emoji: '🏠', label: 'Dashboard', route: '/dashboard'),
    _NavItem(emoji: '🔍', label: 'Explorer', route: '/dashboard/entities'),
    _NavItem(emoji: '🎯', label: 'Queue', route: '/dashboard/match-queue'),
    _NavItem(emoji: '✨', label: 'AI', route: '/dashboard/ai-copilot', isAi: true),
    _NavItem(emoji: '⚙️', label: 'Settings', route: '/dashboard/settings'),
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  Future<void> _loadCurrentUser() async {
    final name     = await AuthManager.getUserName() ?? '';
    final email    = await AuthManager.getUserEmail() ?? '';
    final role     = await AuthManager.getUserRole() ?? 'viewer';
    final tenantId = await AuthManager.getTenantId() ?? '';
    if (!mounted) return;
    setState(() {
      _currentUser = _userFromAuth(
        name: name,
        email: email,
        role: role,
        tenantId: tenantId,
      );
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

  // ── Build ─────────────────────────────────────────────────────────────────

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
        child: NexusLogo(size: 28, showText: false),
      ),
      title: Text('Nexus AI MDM', style: AppTextStyles.titleMedium),
      actions: [
        _buildNotificationButton(),
        _buildUserAvatar(compact: true),
        const SizedBox(width: 8),
      ],
    );
  }

  // ── Sidebar ───────────────────────────────────────────────────────────────

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
                NexusLogo(
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
                _buildNavItemWidget(
                  context,
                  const _NavItem(
                    emoji: '⚙️',
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
    final widgets = <Widget>[];
    for (final group in _navGroups) {
      // Role-based visibility check
      if (group.visibleTo != null &&
          !group.visibleTo!.contains(_currentUser.role)) {
        continue;
      }

      widgets.add(_buildGroupHeader(group.label));

      for (final item in group.items) {
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
    return location.startsWith(route);
  }

  Widget _buildNavItemWidget(
      BuildContext context, _NavItem item, bool isActive) {
    return Tooltip(
      message: _isSidebarExpanded ? '' : item.label,
      preferBelow: false,
      child: InkWell(
        onTap: () => context.go(item.route),
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
                    Text(
                      item.emoji,
                      style: TextStyle(
                        fontSize: 15,
                        color: isActive
                            ? null
                            : null, // emoji is self-colored
                      ),
                    ),
                    if (item.badge != null && !_isSidebarExpanded)
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
                            item.badge!,
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
                if (item.badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      item.badge!,
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

  // ── Top bar ───────────────────────────────────────────────────────────────

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
                          'Search pages, actions, records…',
                          style: AppTextStyles.inputHint.copyWith(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const _KeyboardShortcutHint(text: '⌘K'),
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
        if (value == 'settings') context.go('/dashboard/settings');
      },
    );
  }

  // ── Mobile bottom nav ─────────────────────────────────────────────────────

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
                  icon: Text(item.emoji, style: const TextStyle(fontSize: 20)),
                  label: item.label,
                ))
            .toList(),
      ),
    );
  }

  // ── Page title map ────────────────────────────────────────────────────────

  String _getPageTitle(String location) {
    if (location == '/dashboard') return 'Dashboard';
    if (location.startsWith('/dashboard/admin/tenants')) return 'Tenants';
    if (location.startsWith('/dashboard/org/users')) return 'Users & Roles';
    if (location.startsWith('/dashboard/org/entity-types')) return 'Entity Types';
    if (location.startsWith('/dashboard/org/attributes')) return 'Attribute Schema';
    if (location.startsWith('/dashboard/org/sources')) return 'Source Systems';
    if (location.startsWith('/dashboard/entities/create')) return 'Create Entity';
    if (location.startsWith('/dashboard/entities/ingest')) return 'Ingest Data';
    if (location.startsWith('/dashboard/entities')) return 'Entity Explorer';
    if (location.startsWith('/dashboard/match-queue')) return 'Match Queue';
    if (location.startsWith('/dashboard/merge')) return 'Merge Studio';
    if (location.startsWith('/dashboard/golden-records')) return 'Golden Records';
    if (location.startsWith('/dashboard/ai-copilot')) return 'AI Copilot';
    if (location.startsWith('/dashboard/data-quality')) return 'Data Quality';
    if (location.startsWith('/dashboard/lineage')) return 'Data Lineage';
    if (location.startsWith('/dashboard/governance')) return 'Governance';
    if (location.startsWith('/dashboard/analytics')) return 'Analytics';
    if (location.startsWith('/dashboard/distribution')) return 'Distribution Monitor';
    if (location.startsWith('/dashboard/notifications')) return 'Notifications';
    if (location.startsWith('/dashboard/settings')) return 'Settings';
    return 'Nexus AI MDM';
  }

  void _showNotificationsPanel() {
    showNotificationCenter(
      context,
      onDismiss: () => setState(() => _notificationCount = 0),
    );
  }

  Future<void> _handleLogout() async {
    await AuthManager.logout();
    if (mounted) context.go('/login');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helper widgets
// ─────────────────────────────────────────────────────────────────────────────

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
