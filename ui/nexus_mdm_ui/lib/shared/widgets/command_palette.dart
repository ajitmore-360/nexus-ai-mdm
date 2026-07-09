import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_animations.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Entry model
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

enum _EntryKind { navigation, action }

class _PaletteEntry {
  final String id;
  final _EntryKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final String? shortcut;

  /// Returns the navigation action bound to [context].
  final void Function(BuildContext) onSelect;

  const _PaletteEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.iconColor = AppColors.primary,
    this.shortcut,
    required this.onSelect,
  });
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// All commands
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

List<_PaletteEntry> _allEntries() => [
      // Navigation
      _PaletteEntry(
        id: 'nav_dashboard',
        kind: _EntryKind.navigation,
        title: 'Dashboard',
        subtitle: 'Overview, KPIs and activity feed',
        icon: Icons.dashboard_rounded,
        shortcut: 'G D',
        onSelect: (ctx) => ctx.go('/dashboard'),
      ),
      _PaletteEntry(
        id: 'nav_entities',
        kind: _EntryKind.navigation,
        title: 'Entity Explorer',
        subtitle: 'Browse and search all master records',
        icon: Icons.hub_rounded,
        shortcut: 'G E',
        onSelect: (ctx) => ctx.go('/dashboard/entities'),
      ),
      _PaletteEntry(
        id: 'nav_prism',
        kind: _EntryKind.navigation,
        title: 'AI Prism',
        subtitle: 'Chat with your data using natural language',
        icon: Icons.auto_awesome_rounded,
        iconColor: AppColors.aiPurple,
        shortcut: 'G A',
        onSelect: (ctx) => ctx.go('/dashboard/ai-prism'),
      ),
      _PaletteEntry(
        id: 'nav_queue',
        kind: _EntryKind.navigation,
        title: 'Match Queue',
        subtitle: 'Review and resolve duplicate candidates',
        icon: Icons.pending_actions_rounded,
        iconColor: AppColors.warning,
        shortcut: 'G Q',
        onSelect: (ctx) => ctx.go('/dashboard/match-queue'),
      ),
      _PaletteEntry(
        id: 'nav_quality',
        kind: _EntryKind.navigation,
        title: 'Data Quality',
        subtitle: 'Quality rules, scores and trends',
        icon: Icons.health_and_safety_rounded,
        onSelect: (ctx) => ctx.go('/dashboard/data-quality'),
      ),
      _PaletteEntry(
        id: 'nav_governance',
        kind: _EntryKind.navigation,
        title: 'Governance',
        subtitle: 'Policies, GDPR and compliance',
        icon: Icons.policy_rounded,
        onSelect: (ctx) => ctx.go('/dashboard/governance'),
      ),
      _PaletteEntry(
        id: 'nav_analytics',
        kind: _EntryKind.navigation,
        title: 'Analytics',
        subtitle: 'Reports, charts and exports',
        icon: Icons.analytics_rounded,
        onSelect: (ctx) => ctx.go('/dashboard/analytics'),
      ),
      _PaletteEntry(
        id: 'nav_golden',
        kind: _EntryKind.navigation,
        title: 'Golden Records',
        subtitle: 'Authoritative master records',
        icon: Icons.stars_rounded,
        iconColor: AppColors.statusGolden,
        onSelect: (ctx) => ctx.go('/dashboard/golden-records'),
      ),
      _PaletteEntry(
        id: 'nav_settings',
        kind: _EntryKind.navigation,
        title: 'Settings',
        subtitle: 'App configuration and preferences',
        icon: Icons.settings_rounded,
        iconColor: AppColors.secondaryText,
        onSelect: (ctx) => ctx.go('/dashboard/settings'),
      ),
      // Actions
      _PaletteEntry(
        id: 'act_create',
        kind: _EntryKind.action,
        title: 'Create New Entity',
        subtitle: 'Add a master data record from scratch',
        icon: Icons.add_circle_rounded,
        shortcut: 'C',
        onSelect: (ctx) => ctx.push('/dashboard/entities/create'),
      ),
      _PaletteEntry(
        id: 'act_match',
        kind: _EntryKind.action,
        title: 'Open Match Queue',
        subtitle: 'Start reviewing duplicate candidates',
        icon: Icons.merge_type_rounded,
        iconColor: AppColors.aiPurple,
        onSelect: (ctx) => ctx.go('/dashboard/match-queue'),
      ),
    ];

// Simple fuzzy: every whitespace-split word of [query] must appear somewhere.
bool _matches(_PaletteEntry e, String query) {
  if (query.isEmpty) return true;
  final hay = '${e.title} ${e.subtitle}'.toLowerCase();
  return query.toLowerCase().split(RegExp(r'\s+')).every(
        (w) => w.isEmpty || hay.contains(w),
      );
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Public API
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Future<void> showCommandPalette(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'CommandPalette',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: AppAnimations.fast,
    pageBuilder: (ctx, _, __) => const _CommandPaletteOverlay(),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: AppAnimations.snappyEnter,
        reverseCurve: AppAnimations.quickExit,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Overlay widget
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _CommandPaletteOverlay extends StatefulWidget {
  const _CommandPaletteOverlay();

  @override
  State<_CommandPaletteOverlay> createState() =>
      _CommandPaletteOverlayState();
}

class _CommandPaletteOverlayState
    extends State<_CommandPaletteOverlay> {
  final _searchCtrl    = TextEditingController();
  final _scrollCtrl    = ScrollController();
  final _focusNode     = FocusNode();
  final _entries       = _allEntries();

  List<_PaletteEntry> _results = [];
  int _selectedIdx = 0;

  @override
  void initState() {
    super.initState();
    _results = _entries;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // â”€â”€ Logic â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _onQuery(String q) {
    setState(() {
      _results    = _entries.where((e) => _matches(e, q)).toList();
      _selectedIdx = 0;
    });
  }

  void _commit() {
    if (_results.isEmpty) return;
    final entry = _results[_selectedIdx];
    Navigator.pop(context);
    entry.onSelect(context);
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selectedIdx =
          (_selectedIdx + delta + _results.length) % _results.length;
    });
    _tryScroll();
  }

  void _tryScroll() {
    if (!_scrollCtrl.hasClients) return;
    const kItemHeight = 64.0;
    final target = (_selectedIdx * kItemHeight).clamp(
      0.0,
      _scrollCtrl.position.maxScrollExtent,
    );
    _scrollCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _commit();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.pop(context);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        behavior: HitTestBehavior.opaque,
        child: Align(
          alignment: const Alignment(0, -0.15),
          child: GestureDetector(
            onTap: () {}, // absorb taps inside
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _onKey,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                  child: Container(
                    width: 640,
                    constraints: const BoxConstraints(maxHeight: 540),
                    decoration: BoxDecoration(
                      color: AppColors.glassSurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.divider),
                      boxShadow: AppColors.glowShadow(
                        color: AppColors.primary,
                        intensity: 0.8,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSearch(),
                        const Divider(height: 1, color: AppColors.divider),
                        Flexible(
                          child: _results.isEmpty
                              ? _buildEmpty()
                              : _buildList(),
                        ),
                        _buildFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // â”€â”€ Search input â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (b) =>
                AppColors.auroraGradient.createShader(b),
            child: const Icon(Icons.search_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onQuery,
              style: AppTextStyles.bodyLarge,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search pages, actions, recordsâ€¦',
                hintStyle:
                    AppTextStyles.bodyLarge.copyWith(color: AppColors.mutedText),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              cursorColor: AppColors.primary,
            ),
          ),
          const _Kbd('ESC'),
        ],
      ),
    );
  }

  // â”€â”€ Results list â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildList() {
    final nav = _results
        .where((e) => e.kind == _EntryKind.navigation)
        .toList();
    final act =
        _results.where((e) => e.kind == _EntryKind.action).toList();

    // Build a flat list of widgets, tracking global index as we go.
    int gIdx = 0;
    final rows = <Widget>[];

    void addSection(String label, List<_PaletteEntry> items) {
      if (items.isEmpty) return;
      rows.add(_buildSectionHeader(label));
      for (final e in items) {
        final idx = gIdx++;
        rows.add(_buildRow(e, idx));
      }
    }

    addSection('Navigation', nav);
    addSection('Actions', act);

    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: 8),
      shrinkWrap: true,
      children: rows,
    );
  }

  Widget _buildSectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
        child: Text(label.toUpperCase(), style: AppTextStyles.tableHeader),
      );

  Widget _buildRow(_PaletteEntry entry, int idx) {
    final selected = idx == _selectedIdx;
    return MouseRegion(
      onEnter: (_) => setState(() => _selectedIdx = idx),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedIdx = idx);
          _commit();
        },
        child: AnimatedContainer(
          duration: AppAnimations.micro,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.25)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              // Icon chip
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: entry.iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(entry.icon,
                    color: entry.iconColor, size: 17),
              ),
              const SizedBox(width: 12),
              // Labels
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.title,
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.primaryText,
                          fontWeight: FontWeight.w600,
                        )),
                    Text(entry.subtitle,
                        style: AppTextStyles.bodySmall,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (entry.shortcut != null) _Kbd(entry.shortcut!),
            ],
          ),
        ),
      ),
    )
        .animate(delay: AppAnimations.stagger(idx, baseMs: 20))
        .fadeIn(duration: AppAnimations.fast)
        .slideX(begin: 0.02, end: 0, duration: AppAnimations.fast);
  }

  // â”€â”€ Empty state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildEmpty() => Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                color: AppColors.mutedText, size: 36),
            const SizedBox(height: 12),
            Text('No results',
                style: AppTextStyles.titleSmall),
            const SizedBox(height: 4),
            Text('Try a different keyword',
                style: AppTextStyles.bodySmall),
          ],
        ),
      );

  // â”€â”€ Footer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildFooter() => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            const _KbdIcon(Icons.keyboard_arrow_up_rounded),
            const SizedBox(width: 2),
            const _KbdIcon(Icons.keyboard_arrow_down_rounded),
            const SizedBox(width: 6),
            Text('Navigate', style: AppTextStyles.labelSmall),
            const SizedBox(width: 16),
            const _KbdIcon(Icons.keyboard_return_rounded),
            const SizedBox(width: 6),
            Text('Open', style: AppTextStyles.labelSmall),
            const Spacer(),
            ShaderMask(
              shaderCallback: (b) =>
                  AppColors.auroraGradient.createShader(b),
              child: Text('Azile AI MDM',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: Colors.white)),
            ),
          ],
        ),
      );
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Small helpers
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _Kbd extends StatelessWidget {
  final String text;
  const _Kbd(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.elevatedCard,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(text,
            style: AppTextStyles.labelSmall.copyWith(
              fontSize: 10,
              fontFamily: 'monospace',
            )),
      );
}

class _KbdIcon extends StatelessWidget {
  final IconData icon;
  const _KbdIcon(this.icon);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.elevatedCard,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.divider),
        ),
        child: Icon(icon, size: 12, color: AppColors.secondaryText),
      );
}
