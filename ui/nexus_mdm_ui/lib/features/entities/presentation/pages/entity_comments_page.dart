import 'package:flutter/material.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class EntityCommentsPage extends StatefulWidget {
  final String entityId;
  const EntityCommentsPage({super.key, required this.entityId});

  @override
  State<EntityCommentsPage> createState() => _EntityCommentsPageState();
}

class _EntityCommentsPageState extends State<EntityCommentsPage> {
  final _apiClient = ApiClient();
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();

  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;
  String _currentUserId = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _currentUserId = await AuthManager.getUserId() ?? '';
    await _loadComments();
  }

  Future<void> _loadComments() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final resp = await _apiClient.get<Map<String, dynamic>>(
        '/v1/entities/${widget.entityId}/comments',
      );
      final items = (resp.data?['items'] as List? ?? []).cast<Map<String, dynamic>>();
      setState(() { _comments = items; _loading = false; });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendComment() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _apiClient.post<Map<String, dynamic>>(
        '/v1/entities/${widget.entityId}/comments',
        data: {'content': text},
      );
      _inputCtrl.clear();
      await _loadComments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      setState(() => _sending = false);
    }
  }

  Future<void> _editComment(Map<String, dynamic> comment) async {
    final ctrl = TextEditingController(text: comment['content'] as String? ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Edit Comment', style: AppTextStyles.titleMedium),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.navyBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _apiClient.patch<Map<String, dynamic>>(
          '/v1/entities/${widget.entityId}/comments/${comment['comment_id']}',
          data: {'content': ctrl.text.trim()},
        );
        await _loadComments();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _deleteComment(Map<String, dynamic> comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete Comment?', style: AppTextStyles.titleMedium),
        content: Text('This cannot be undone.', style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _apiClient.delete<void>(
          '/v1/entities/${widget.entityId}/comments/${comment['comment_id']}',
        );
        await _loadComments();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  String _relativeTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Comments', style: AppTextStyles.titleLarge),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadComments),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildCommentList()),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildCommentList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 8),
            Text(_error, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadComments, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: AppColors.secondaryText),
            const SizedBox(height: 16),
            Text('No comments yet', style: AppTextStyles.titleMedium.copyWith(color: AppColors.secondaryText)),
            const SizedBox(height: 8),
            Text('Start the conversation below', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.secondaryText)),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      itemCount: _comments.length,
      itemBuilder: (ctx, i) => _buildCommentTile(_comments[i]),
    );
  }

  Widget _buildCommentTile(Map<String, dynamic> comment) {
    final isOwn = (comment['author_id'] as String? ?? '') == _currentUserId;
    final authorName = comment['author_name'] as String? ?? 'Unknown';
    return GestureDetector(
      onLongPress: isOwn ? () => _showCommentActions(comment) : null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
              child: Text(_initials(authorName),
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: isOwn
                      ? Border.all(color: AppColors.primary.withValues(alpha: 0.3))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(authorName,
                            style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
                        const Spacer(),
                        Text(_relativeTime(comment['created_at'] as String?),
                            style: AppTextStyles.bodySmall),
                        if (isOwn) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.edit_outlined, size: 12, color: AppColors.secondaryText),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(comment['content'] as String? ?? '', style: AppTextStyles.bodyMedium),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCommentActions(Map<String, dynamic> comment) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () { Navigator.pop(ctx); _editComment(comment); },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.error),
              title: Text('Delete', style: TextStyle(color: AppColors.error)),
              onTap: () { Navigator.pop(ctx); _deleteComment(comment); },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                focusNode: _focusNode,
                style: AppTextStyles.bodyMedium,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Add a comment…',
                  hintStyle: AppTextStyles.inputHint,
                  filled: true,
                  fillColor: AppColors.inputFill,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _sendComment(),
              ),
            ),
            const SizedBox(width: 8),
            _sending
                ? const SizedBox(width: 40, height: 40,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    onPressed: _sendComment,
                    icon: Icon(Icons.send_rounded, color: AppColors.primary),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                      shape: const CircleBorder(),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
