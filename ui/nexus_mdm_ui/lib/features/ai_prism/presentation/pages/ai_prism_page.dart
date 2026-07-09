import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/license/licensed_module.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/widgets/ai_badge.dart';
import '../../../../shared/widgets/license_gate.dart';
import '../../data/prism_repository.dart';

class _ChatMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final bool isStreaming;
  final Map<String, dynamic>? tableData;

  const _ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.isStreaming = false,
    this.tableData,
  });

  _ChatMessage copyWith({
    String? content,
    bool? isStreaming,
    Map<String, dynamic>? tableData,
    bool clearTable = false,
  }) =>
      _ChatMessage(
        id: id,
        content: content ?? this.content,
        isUser: isUser,
        timestamp: timestamp,
        isStreaming: isStreaming ?? this.isStreaming,
        tableData: clearTable ? null : (tableData ?? this.tableData),
      );
}

class AiPrismPage extends StatefulWidget {
  const AiPrismPage({super.key});

  @override
  State<AiPrismPage> createState() => _AiPrismPageState();
}

class _AiPrismPageState extends State<AiPrismPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isThinking = false;
  bool _isListening = false;

  static const _welcomeMessage = '''Hello! I'm Azile AI, your intelligent MDM assistant.

I can help you:
â€¢ **Analyze** entity data and quality scores
â€¢ **Find** duplicates and match candidates
â€¢ **Explain** matching decisions and confidence scores
â€¢ **Query** your data in natural language
â€¢ **Generate** data quality reports
â€¢ **Suggest** merge and governance actions

What would you like to know about your master data?''';


  @override
  void initState() {
    super.initState();
    _addAiMessage(_welcomeMessage);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addAiMessage(String content) {
    final msg = _ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isUser: false,
      timestamp: DateTime.now(),
    );
    setState(() => _messages.add(msg));
    _scrollToBottom();
  }

  void _addUserMessage(String content) {
    final msg = _ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isUser: true,
      timestamp: DateTime.now(),
    );
    setState(() => _messages.add(msg));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || _isThinking) return;
    _inputController.clear();
    _addUserMessage(query);
    setState(() => _isThinking = true);

    // Add an empty AI message that will grow as tokens arrive.
    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() => _messages.add(_ChatMessage(
      id: msgId,
      content: '',
      isUser: false,
      timestamp: DateTime.now(),
      isStreaming: true,
    )));
    _scrollToBottom();

    final buffer = StringBuffer();
    bool firstChunk = true;

    try {
      final repo = PrismRepository(GetIt.instance<ApiClient>());
      await for (final chunk in repo.chat(query)) {
        if (!mounted) break;
        if (firstChunk) {
          firstChunk = false;
          setState(() => _isThinking = false);
        }
        buffer.write(chunk);
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == msgId);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(content: buffer.toString());
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      buffer.write('I\'m having trouble connecting to the AI service. '
          'Please check your connection and try again.');
    }

    if (!mounted) return;

    // After streaming: extract table JSON from anywhere in the response.
    // The LLM may prepend a prose sentence before the JSON object.
    Map<String, dynamic>? parsedTable;
    String finalContent = buffer.isEmpty ? 'No response received.' : buffer.toString();
    const tableMarker = '{"type":"table"';
    final jsonIdx = finalContent.indexOf(tableMarker);
    if (jsonIdx >= 0) {
      try {
        final decoded = jsonDecode(finalContent.substring(jsonIdx));
        if (decoded is Map<String, dynamic> && decoded['type'] == 'table') {
          parsedTable = decoded;
          // Keep any preamble prose; strip the raw JSON block
          finalContent = finalContent.substring(0, jsonIdx).trim();
        }
      } catch (_) {
        // Not valid JSON at that position â€” treat full response as prose
      }
    }

    setState(() {
      _isThinking = false;
      final idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(
          content: finalContent,
          isStreaming: false,
          tableData: parsedTable,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LicenseGuard(
      module: LicensedModule.aiPrism,
      child: _buildMain(),
    );
  }

  Widget _buildMain() {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildMessageList()),
          if (_isThinking) _buildThinkingIndicator(),
          _buildSuggestedPrompts(),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppColors.purpleGradient,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppColors.aiPurple.withValues(alpha:0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome,
                color: Colors.white, size: 22),
          ).animate().fadeIn().scaleXY(begin: 0.8, end: 1.0),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Azile AI Prism', style: AppTextStyles.titleMedium)
                  .animate(delay: 50.ms).fadeIn(),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Azile AI v2.1 Â· Connected',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.secondaryText),
                  ),
                ],
              ).animate(delay: 100.ms).fadeIn(),
            ],
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _messages.clear());
              _addAiMessage(_welcomeMessage);
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('New chat'),
          ).animate(delay: 150.ms).fadeIn(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      itemCount: _messages.length,
      itemBuilder: (context, i) => _buildMessage(_messages[i], i),
    );
  }

  Widget _buildMessage(_ChatMessage msg, int index) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.65,
          ),
          margin: const EdgeInsets.only(bottom: 16, left: 60),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                msg.content,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.navyBackground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatTime(msg.timestamp),
                style: AppTextStyles.timestamp.copyWith(
                  color: AppColors.navyBackground.withValues(alpha:0.6),
                ),
              ),
            ],
          ),
        ).animate(delay: 0.ms).fadeIn(duration: 300.ms).slideX(
            begin: 0.1, end: 0, duration: 300.ms),
      );
    }

    // AI message
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 16, right: 60),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 10, top: 2),
              decoration: BoxDecoration(
                gradient: AppColors.purpleGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome,
                  color: Colors.white, size: 16),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Azile AI',
                          style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.aiPurple)),
                      const SizedBox(width: 8),
                      Text(_formatTime(msg.timestamp),
                          style: AppTextStyles.timestamp),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.elevatedCard,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      border: Border.all(
                          color: AppColors.aiPurple.withValues(alpha:0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (msg.tableData != null)
                          _buildTableMessage(msg.tableData!)
                        else
                          _buildMarkdownText(msg.content),
                        if (msg.isStreaming)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _buildCursor(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ).animate(delay: 0.ms).fadeIn(duration: 300.ms).slideX(
          begin: -0.05, end: 0, duration: 300.ms),
    );
  }

  Widget _buildTableMessage(Map<String, dynamic> data) {
    final columns = (data['columns'] as List?)?.map((c) => c.toString()).toList() ?? [];
    final rawRows = (data['rows'] as List?) ?? [];
    final summary = data['summary'] as String? ?? '';

    // Normalize rows: LLM may return either arrays or objects per row
    final rows = rawRows.map((row) {
      if (row is List) return row.map((v) => v?.toString() ?? '').toList();
      if (row is Map) return columns.map((c) => row[c]?.toString() ?? '').toList();
      return <String>[];
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary.isNotEmpty) ...[
          Text(summary, style: AppTextStyles.aiMessage),
          const SizedBox(height: 10),
        ],
        Text(
          '${rows.length} result${rows.length == 1 ? '' : 's'}',
          style: AppTextStyles.labelSmall.copyWith(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              AppColors.aiPurple.withValues(alpha: 0.08),
            ),
            dataRowColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AppColors.aiPurple.withValues(alpha: 0.04)
                  : null,
            ),
            border: TableBorder.all(
              color: AppColors.divider,
              width: 1,
              borderRadius: BorderRadius.circular(6),
            ),
            headingTextStyle: AppTextStyles.labelSmall.copyWith(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w600,
            ),
            dataTextStyle: AppTextStyles.bodySmall.copyWith(
              color: AppColors.primaryText,
            ),
            columns: columns.map((c) => DataColumn(label: Text(c))).toList(),
            rows: rows
                .map((row) => DataRow(
                      cells: List.generate(
                        columns.length,
                        (i) => DataCell(Text(i < row.length ? row[i] : '')),
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCursor() {
    return Container(
      width: 2,
      height: 16,
      decoration: BoxDecoration(
        color: AppColors.aiPurple,
        borderRadius: BorderRadius.circular(1),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true))
        .fadeIn(duration: 400.ms);
  }

  Widget _buildMarkdownText(String text) {
    // Simple markdown renderer â€” bold (**text**) and newlines
    final spans = <TextSpan>[];
    final parts = text.split('\n');

    for (int lineIdx = 0; lineIdx < parts.length; lineIdx++) {
      if (lineIdx > 0) {
        spans.add(const TextSpan(text: '\n'));
      }
      final line = parts[lineIdx];
      final boldParts = line.split('**');
      for (int i = 0; i < boldParts.length; i++) {
        if (i % 2 == 0) {
          spans.add(TextSpan(
            text: boldParts[i],
            style: AppTextStyles.aiMessage,
          ));
        } else {
          spans.add(TextSpan(
            text: boldParts[i],
            style: AppTextStyles.aiMessage.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ));
        }
      }
    }

    return RichText(text: TextSpan(children: spans));
  }

  Widget _buildThinkingIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: AppColors.purpleGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome,
                  color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            const AiThinkingIndicator(label: 'Thinking'),
          ],
        ).animate().fadeIn(duration: 300.ms),
      ),
    );
  }

  Widget _buildSuggestedPrompts() {
    final prompts = AppConstants.aiSuggestedPrompts.take(4).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: prompts.map((prompt) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => _sendMessage(prompt),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.elevatedCard,
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    prompt,
                    style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primaryText),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Voice button
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _isListening
                  ? AppColors.error.withValues(alpha:0.12)
                  : AppColors.elevatedCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isListening
                    ? AppColors.error.withValues(alpha:0.4)
                    : AppColors.divider,
              ),
            ),
            child: IconButton(
              onPressed: () =>
                  setState(() => _isListening = !_isListening),
              icon: Icon(
                _isListening ? Icons.mic_rounded : Icons.mic_outlined,
                size: 20,
                color: _isListening
                    ? AppColors.error
                    : AppColors.secondaryText,
              ),
              tooltip: 'Voice input',
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 10),

          // Input field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: TextField(
                controller: _inputController,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (v) => _sendMessage(v),
                decoration: const InputDecoration(
                  hintText:
                      'Ask anything about your data â€” entities, matches, quality...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                style: AppTextStyles.inputText,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Send button
          GestureDetector(
            onTap: () => _sendMessage(_inputController.text),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: _isThinking
                    ? const LinearGradient(colors: [
                        AppColors.mutedText,
                        AppColors.mutedText
                      ])
                    : AppColors.purpleGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: _isThinking
                    ? null
                    : [
                        BoxShadow(
                          color: AppColors.aiPurple.withValues(alpha:0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: _isThinking
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
