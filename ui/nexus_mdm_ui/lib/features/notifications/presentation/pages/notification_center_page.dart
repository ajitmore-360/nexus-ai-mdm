import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/websocket_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

// ──────────────────────────────────────────────
// Domain models
// ──────────────────────────────────────────────

enum _NotifType { match, merge, quality, system }

extension _NotifTypeMeta on _NotifType {
  String get label {
    switch (this) {
      case _NotifType.match:
        return 'Match';
      case _NotifType.merge:
        return 'Merge';
      case _NotifType.quality:
        return 'Quality';
      case _NotifType.system:
        return 'System';
    }
  }

  Color get borderColor {
    switch (this) {
      case _NotifType.match:
        return AppColors.primary;
      case _NotifType.merge:
        return AppColors.aiPurple;
      case _NotifType.quality:
        return AppColors.warning;
      case _NotifType.system:
        return AppColors.info;
    }
  }

  IconData get icon {
    switch (this) {
      case _NotifType.match:
        return Icons.compare_arrows_rounded;
      case _NotifType.merge:
        return Icons.merge_rounded;
      case _NotifType.quality:
        return Icons.health_and_safety_outlined;
      case _NotifType.system:
        return Icons.info_outline_rounded;
    }
  }
}

class _Notification {
  final String id;
  final _NotifType type;
  final String title;
  final String body;
  final String? entityId;
  final DateTime timestamp;
  bool isRead;

  _Notification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.entityId,
    required this.timestamp,
    this.isRead = false,
  });
}

// ──────────────────────────────────────────────
// Public entry-point: show as slide-over overlay
// ──────────────────────────────────────────────

/// Call this from the shell to open the notification panel.
void showNotificationCenter(BuildContext context, {VoidCallback? onDismiss}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _NotificationOverlay(
      onClose: () {
        entry.remove();
        onDismiss?.call();
      },
    ),
  );
  overlay.insert(entry);
}

// ──────────────────────────────────────────────
// Overlay wrapper (slide from right)
// ──────────────────────────────────────────────

class _NotificationOverlay extends StatefulWidget {
  final VoidCallback onClose;
  const _NotificationOverlay({required this.onClose});

  @override
  State<_NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<_NotificationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _barrierFade;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _barrierFade = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _animCtrl.reverse();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Barrier
        FadeTransition(
          opacity: _barrierFade,
          child: GestureDetector(
            onTap: _close,
            child: Container(
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),
        ),
        // Panel
        Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: _slideAnim,
            child: NotificationCenterPanel(onClose: _close),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// Panel widget (also usable standalone)
// ──────────────────────────────────────────────

class NotificationCenterPanel extends StatefulWidget {
  final VoidCallback? onClose;

  const NotificationCenterPanel({super.key, this.onClose});

  @override
  State<NotificationCenterPanel> createState() => _NotificationCenterPanelState();
}

class _NotificationCenterPanelState extends State<NotificationCenterPanel> {
  _NotifType? _activeFilter;

  // WebSocket
  late final WebSocketClient _wsClient;
  StreamSubscription<Map<String, dynamic>>? _msgSub;
  void Function()? _stateListener;

  bool get _wsLive =>
      _wsClient.connectionState.value == WsConnectionState.connected;

  @override
  void initState() {
    super.initState();
    _wsClient = GetIt.instance<WebSocketClient>();
    _wsClient.connect();
    _msgSub = _wsClient.messages.listen(_onWsMessage);
    _stateListener = () { if (mounted) setState(() {}); };
    _wsClient.connectionState.addListener(_stateListener!);
    _loadFromAuditLog();
  }

  Future<void> _loadFromAuditLog() async {
    try {
      final api = ApiClient();
      final resp = await api.get<Map<String, dynamic>>(
        AppConstants.auditEventsPath,
        queryParameters: {'page_size': '20'},
      );
      if (!mounted) return;
      final items = resp.data?['items'] as List<dynamic>? ?? [];
      final loaded = items.map((e) {
        final m = e as Map<String, dynamic>;
        final eventType = m['event_type'] as String? ?? 'system';
        final notifType = _notifTypeFromEvent(eventType);
        final ts = m['timestamp'] as String?;
        return _Notification(
          id: m['event_id'] as String? ?? 'audit_${items.indexOf(e)}',
          type: notifType,
          title: eventType.replaceAll('_', ' ').replaceFirstMapped(
              RegExp(r'^.'), (x) => x[0]!.toUpperCase()),
          body: _bodyFromEvent(m),
          entityId: (m['aggregate_id'] as String?),
          timestamp: ts != null ? DateTime.tryParse(ts) ?? DateTime.now() : DateTime.now(),
          isRead: true,
        );
      }).toList();
      if (mounted) setState(() => _notifications.insertAll(0, loaded));
    } catch (_) {}
  }

  static _NotifType _notifTypeFromEvent(String eventType) {
    final e = eventType.toLowerCase();
    if (e.contains('match') || e.contains('duplicate')) return _NotifType.match;
    if (e.contains('merge') || e.contains('golden'))    return _NotifType.merge;
    if (e.contains('quality') || e.contains('violat'))  return _NotifType.quality;
    return _NotifType.system;
  }

  static String _bodyFromEvent(Map<String, dynamic> m) {
    final eventType = (m['event_type'] as String? ?? '').toLowerCase();
    final aggType = m['aggregate_type'] as String? ?? 'entity';
    final aggId = m['aggregate_id'] as String? ?? '';
    final short = aggId.length > 8 ? aggId.substring(0, 8) : aggId;
    if (eventType.contains('match'))   return 'Match event on $aggType $short…';
    if (eventType.contains('merge'))   return 'Merge on $aggType $short… completed';
    if (eventType.contains('golden'))  return '$aggType $short… elevated to golden record';
    if (eventType.contains('quality')) return 'Quality issue detected on $aggType $short…';
    return '$aggType $short… — ${(m['event_type'] as String? ?? '').replaceAll('_', ' ')}';
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    if (_stateListener != null) {
      _wsClient.connectionState.removeListener(_stateListener!);
    }
    super.dispose();
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String? ?? '';
    final notifType = switch (type) {
      'match_detected' || 'match_found'           => _NotifType.match,
      'golden_record_created' || 'merge_completed' => _NotifType.merge,
      'quality_alert' || 'quality_degraded'        => _NotifType.quality,
      _                                            => _NotifType.system,
    };
    final payload = msg['payload'] as Map<String, dynamic>? ?? {};
    final title = payload['title'] as String? ??
        type.replaceAll('_', ' ').toLowerCase();
    final body  = payload['message'] as String? ??
        payload['body'] as String? ?? '';
    final entityId = msg['entity_id'] as String? ??
        payload['entity_id'] as String?;

    final notif = _Notification(
      id: 'ws_${DateTime.now().millisecondsSinceEpoch}',
      type: notifType,
      title: title,
      body: body,
      entityId: entityId,
      timestamp: msg['timestamp'] != null
          ? DateTime.tryParse(msg['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
    if (mounted) setState(() => _notifications.insert(0, notif));
  }

  final List<_Notification> _notifications = [];

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  List<_Notification> get _filtered {
    if (_activeFilter == null) return _notifications;
    return _notifications.where((n) => n.type == _activeFilter).toList();
  }

  void _markAllRead() {
    setState(() {
      for (final n in _notifications) {
        n.isRead = true;
      }
    });
  }

  void _dismiss(String id) {
    setState(() => _notifications.removeWhere((n) => n.id == id));
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 380,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(left: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 32,
            offset: Offset(-8, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildConnectionStatus(),
          _buildFilterTabs(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Text('Notifications', style: AppTextStyles.titleMedium),
          const SizedBox(width: 10),
          if (_unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$_unreadCount',
                style: AppTextStyles.badgeLabel.copyWith(color: Colors.white),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: _markAllRead,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            child: Text(
              'Mark all read',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.secondaryText),
            onPressed: widget.onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Close',
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
  }

  // ── WebSocket indicator ──────────────────────
  Widget _buildConnectionStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _wsLive ? AppColors.primary : AppColors.warning,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (_wsLive ? AppColors.primary : AppColors.warning)
                      .withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _wsLive ? 'Live' : 'Reconnecting...',
            style: AppTextStyles.labelSmall.copyWith(
              color: _wsLive ? AppColors.primary : AppColors.warning,
            ),
          ),
          const Spacer(),
          Text(
            'WebSocket',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.mutedText),
          ),
        ],
      ),
    );
  }

  // ── Filter Tabs ──────────────────────────────
  Widget _buildFilterTabs() {
    final filters = <({String label, _NotifType? type})>[
      (label: 'All', type: null),
      (label: 'Matches', type: _NotifType.match),
      (label: 'Merges', type: _NotifType.merge),
      (label: 'Quality', type: _NotifType.quality),
      (label: 'System', type: _NotifType.system),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: filters.map((f) {
          final isActive = _activeFilter == f.type;
          final borderColor = f.type?.borderColor ?? AppColors.primary;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeFilter = f.type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? borderColor.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: isActive
                      ? Border.all(color: borderColor.withValues(alpha: 0.4))
                      : Border.all(color: Colors.transparent),
                ),
                child: Text(
                  f.label,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: isActive ? borderColor : AppColors.secondaryText,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── List ─────────────────────────────────────
  Widget _buildList() {
    final items = _filtered;
    if (items.isEmpty) return _buildEmptyState();

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(
        color: AppColors.divider,
        height: 1,
        indent: 20,
        endIndent: 20,
      ),
      itemBuilder: (context, i) => _buildNotifItem(items[i], i),
    );
  }

  Widget _buildNotifItem(_Notification notif, int index) {
    return Dismissible(
      key: ValueKey(notif.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _dismiss(notif.id),
      background: Container(
        color: AppColors.error.withValues(alpha: 0.15),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
      ),
      child: InkWell(
        onTap: () => setState(() => notif.isRead = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: notif.isRead ? Colors.transparent : notif.type.borderColor.withValues(alpha: 0.04),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left border accent
              Container(
                width: 3,
                height: 48,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: notif.isRead
                      ? notif.type.borderColor.withValues(alpha: 0.3)
                      : notif.type.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Icon
              Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: notif.type.borderColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(notif.type.icon, size: 16, color: notif.type.borderColor),
              ),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: notif.type.borderColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            notif.type.label.toUpperCase(),
                            style: AppTextStyles.badgeLabel.copyWith(
                              color: notif.type.borderColor,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(_relativeTime(notif.timestamp), style: AppTextStyles.timestamp),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      notif.title,
                      style: AppTextStyles.labelMedium.copyWith(
                        fontWeight: notif.isRead ? FontWeight.w500 : FontWeight.w700,
                        color: notif.isRead ? AppColors.secondaryText : AppColors.primaryText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notif.body,
                      style: AppTextStyles.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (notif.entityId != null) ...[
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => context.go('/dashboard/entities/${notif.entityId}'),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.open_in_new_rounded,
                                size: 11, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(
                              notif.entityId!,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.primary,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Unread dot
              if (!notif.isRead)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4, left: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    ).animate(delay: (index * 40).ms).fadeIn(duration: 250.ms).slideX(begin: 0.03, end: 0);
  }

  // ── Empty state ──────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: AppColors.primary,
              size: 32,
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05), duration: 1200.ms, curve: Curves.easeInOut),
          const SizedBox(height: 16),
          Text('All caught up!', style: AppTextStyles.titleSmall),
          const SizedBox(height: 6),
          Text(
            'No notifications in this category.',
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).scale(begin: const Offset(0.9, 0.9), end: const Offset(1.0, 1.0));
  }
}
