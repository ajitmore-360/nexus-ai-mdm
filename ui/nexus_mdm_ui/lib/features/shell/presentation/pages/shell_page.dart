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

  static const _navItems = [
    _NavItem(
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard_rounded,
      label: 'Dashboard',
      route: '/dashboard',
    ),
    _NavItem(
      icon: Icons.hub_outlined,
      activeIcon: Icons.hub_rounded,
      label: 'Explorer',
      route: '/dashboard/entities',
    ),
    _NavItem(
      icon: Icons.pending_actions_outlined,
      activeIcon: Icons.pending_actions_rounded,
      label: 'Match Queue',
      route: '/dashboard/match-queue',
      badge: '12',
    ),
    _NavItem(
      icon: Icons.merge_outlined,
      activeIcon: Icons.merge_rounded,
      label: 'Merge',
      route: '/dashboard/merge/select/select',
    ),
    _NavItem(
      icon: Icons.stars_outlined,
      activeIcon: Icons.stars_rounded,
      label: 'Golden Records',
      route: '/dashboard/golden-records',
    ),
    _NavItem(
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome_rounded,
      label: 'AI Copilot',
      route: '/dashboard/ai-copilot',
      isAi: true,
    ),
    _NavItem(
      icon: Icons.health_and_safety_outlined,
      activeIcon: Icons.health_and_safety_rounded,
      label: 'Data Quality',
      route: '/dashboard/data-quality',
    ),
    _NavItem(
      icon: Icons.account_tree_outlined,
      activeIcon: Icons.account_tree_rounded,
      label: 'Lineage',
      route: '/dashboard/lineage',
    ),
    _NavItem(
      icon: Icons.policy_outlined,
      activeIcon: Icons.policy_rounded,
      label: 'Governance',
      route: '/dashboard/governance',
    ),
    _NavItem(
      icon: Icons.analytics_outlined,
      activeIcon: Icons.analytics_rounded,
      label: 'Analytics',
      route: '/dashboard/analytics',
    ),
    _NavItem(
      icon: Icons.send_outlined,
      activeIcon: Icons.send_rounded,
      label: 'Distribution',
      route: '/dashboard/distribution',
    ),
  ];

  static const _bottomNavItems = [
    _NavItem(
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard_rounded,
      label: 'Dashboard',
      route: '/dashboard',
    ),
    _NavItem(
      icon: Icons.hub_outlined,
      activeIcon: Icons.hub_rounded,
      label: 'Explorer',
      route: '/dashboard/entities',
    ),
    _NavItem(
      icon: Icons.pending_actions_outlined,
      activeIcon: Icons.pending_actions_rounded,
      label: 'Queue',
      route: '/dashboard/match-queue',
    ),
    _NavItem(
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome_rounded,
      label: 'AI',
      route: '/dashboard/ai-copilot',
    ),
    _NavItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: 'Settings',
      route: '/dashboard/settings',
    ),
  ];

  // ── Global cmd/ctrl+K shortcut ────────────────────────────────────────────

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
      return true; // consumed — don't propagate
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    super.dispose();
  }

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
          // Sidebar
          AnimatedContainer(
            duration: AppConstants.animNormal,
            curve: Curves.easeInOut,
            width: _isSidebarExpanded
                ? AppConstants.sidebarWidth
                : AppConstants.sidebarCollapsedWidth,
            child: _buildSidebar(context),
          ),

          // Main content
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

          // Nav items
          Expanded(
            child: ListView.separated(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              itemCount: _navItems.length,
              separatorBuilder: (_, i) => i == 4
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Divider(
                        color: AppColors.divider,
                        height: 1,
                        indent: 8,
                        endIndent: 8,
                      ),
                    )
                  : const SizedBox(height: 2),
              itemBuilder: (context, i) {
                final item = _navItems[i];
                final isActive = location.startsWith(item.route) ||
                    (item.route == '/dashboard' &&
                        location == '/dashboard');
                return _buildNavItem(context, item, isActive);
              },
            ),
          ),

          // Bottom section — settings + user
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.divider, width: 1),
              ),
            ),
            child: Column(
              children: [
                _buildNavItem(
                  context,
                  const _NavItem(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings_rounded,
                    label: 'Settings',
                    route: '/dashboard/settings',
                  ),
                  location == '/dashboard/settings',
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

  Widget _buildNavItem(
      BuildContext context, _NavItem item, bool isActive) {
    return Tooltip(
      message: _isSidebarExpanded ? '' : item.label,
      preferBelow: false,
      child: InkWell(
        onTap: () => context.go(item.route),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    width: 1)
                : null,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    isActive ? item.activeIcon : item.icon,
                    color: isActive
                        ? AppColors.primary
                        : AppColors.secondaryText,
                    size: 20,
                  ),
                  if (item.badge != null)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        constraints: const BoxConstraints(
                            minWidth: 16, minHeight: 16),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.badge!,
                          style: AppTextStyles.badgeLabel.copyWith(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  if (item.isAi)
                    const Positioned(
                      right: -4,
                      bottom: -4,
                      child: _AiPulseDot(),
                    ),
                ],
              ),
              if (_isSidebarExpanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: AppTextStyles.sidebarItem.copyWith(
                      color: isActive
                          ? AppColors.primary
                          : AppColors.secondaryText,
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
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

          // Global search — opens the command palette
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

  Widget _buildBottomNav(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    int currentIndex = 0;
    for (int i = 0; i < _bottomNavItems.length; i++) {
      if (location.startsWith(_bottomNavItems[i].route)) {
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
        items: _bottomNavItems
            .map((item) => BottomNavigationBarItem(
                  icon: Icon(item.icon),
                  activeIcon: Icon(item.activeIcon),
                  label: item.label,
                ))
            .toList(),
      ),
    );
  }

  String _getPageTitle(String location) {
    if (location == '/dashboard') return 'Dashboard';
    if (location.startsWith('/dashboard/entities')) return 'Entity Explorer';
    if (location.startsWith('/dashboard/match-queue')) return 'Match Queue';
    if (location.startsWith('/dashboard/golden-records')) {
      return 'Golden Records';
    }
    if (location.startsWith('/dashboard/ai-copilot')) return 'AI Copilot';
    if (location.startsWith('/dashboard/data-quality')) return 'Data Quality';
    if (location.startsWith('/dashboard/lineage')) return 'Data Lineage';
    if (location.startsWith('/dashboard/governance')) return 'Governance';
    if (location.startsWith('/dashboard/analytics')) return 'Analytics';
    if (location.startsWith('/dashboard/distribution')) return 'Distribution Monitor';
    if (location.startsWith('/dashboard/settings')) return 'Settings';
    return 'Nexus AI MDM';
  }

  /// Opens the full NotificationCenter as a right-side slide-over overlay.
  void _showNotificationsPanel() {
    showNotificationCenter(
      context,
      onDismiss: () => setState(() => _notificationCount = 0),
    );
  }

  Future<void> _handleLogout() async {
    // Clears ALL auth tokens from Keychain/Keystore (not just SharedPreferences)
    await AuthManager.logout();
    if (mounted) context.go('/login');
  }
}

// ──────────────────────────────────────────────
// Private helpers
// ──────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
  final String? badge;
  final bool isAi;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
    this.badge,
    this.isAi = false,
  });
}

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

/// Pulsing purple dot shown on the AI Copilot nav item.
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
          // Ripple ring
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
          // Solid core
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
