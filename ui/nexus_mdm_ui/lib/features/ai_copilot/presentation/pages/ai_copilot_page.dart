import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/widgets/ai_badge.dart';

class _ChatMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final bool isStreaming;

  const _ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.isStreaming = false,
  });

  _ChatMessage copyWith({String? content, bool? isStreaming}) =>
      _ChatMessage(
        id: id,
        content: content ?? this.content,
        isUser: isUser,
        timestamp: timestamp,
        isStreaming: isStreaming ?? this.isStreaming,
      );
}

class AiCopilotPage extends StatefulWidget {
  const AiCopilotPage({super.key});

  @override
  State<AiCopilotPage> createState() => _AiCopilotPageState();
}

class _AiCopilotPageState extends State<AiCopilotPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isThinking = false;
  bool _isListening = false;
  Timer? _streamTimer;
  int _charIndex = 0;

  static const _welcomeMessage = '''Hello! I'm Nexus AI, your intelligent MDM assistant.

I can help you:
• **Analyze** entity data and quality scores
• **Find** duplicates and match candidates
• **Explain** matching decisions and confidence scores
• **Query** your data in natural language
• **Generate** data quality reports
• **Suggest** merge and governance actions

What would you like to know about your master data?''';

  static const Map<String, String> _demoResponses = {
    'low trust': '''I found **47 entities** with trust scores below 65%:

**Top concerns:**
1. **23 Person entities** — missing email or phone fields
2. **15 Organization entities** — conflicting address data from 3+ sources
3. **9 Product entities** — duplicate SKUs detected from CSV imports

**Recommended actions:**
• Run bulk enrichment for the 23 Person entities
• Review Organization address conflicts in Match Queue
• De-duplicate Product SKUs (estimated: 2 hours)

Would you like me to create a prioritized remediation plan?''',

    'duplicate': '''**Duplicate Analysis Summary** (last 30 days):

📊 **By Source System:**
| Source | Duplicates | % of Ingest |
|--------|-----------|-------------|
| Salesforce CRM | 523 | 8.2% |
| CSV Import | 389 | 24.1% |
| HubSpot | 287 | 6.8% |

**Root causes identified:**
1. **No pre-ingestion deduplication** on CSV imports
2. **Inconsistent name normalization** across CRM systems
3. **Missing unique identifiers** in 18% of Salesforce records

**AI Recommendation:** Enable pre-ingestion validation rules for CSV imports. Estimated reduction: **67% fewer duplicates**.

Shall I configure these rules automatically?''',

    'match score': '''**Match Score Explanation for Entity ENT-003:**

The 93% confidence score is computed as a weighted ensemble of:

| Algorithm | Score | Weight |
|-----------|-------|--------|
| Name similarity (Jaro-Winkler) | 87% | 0.30 |
| Phone exact match | 99% | 0.35 |
| Email domain match | 72% | 0.20 |
| Address proximity | 91% | 0.15 |

**Ensemble score: 90.6% → adjusted to 93%** (AI correction factor applied based on historical patterns for this entity type)

**Verdict:** HIGH CONFIDENCE MATCH — recommend auto-merge with steward review.

Want me to process this merge?''',
  };

  @override
  void initState() {
    super.initState();
    _addAiMessage(_welcomeMessage);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _streamTimer?.cancel();
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
    if (text.trim().isEmpty || _isThinking) return;
    _inputController.clear();
    _addUserMessage(text);
    setState(() => _isThinking = true);

    // Try real API first, fall back to demo responses if backend is offline
    try {
      final apiClient = ApiClient();
      final response = await apiClient.post<Map<String, dynamic>>(
        AppConstants.aiCopilotPath,
        data: {
          'prompt':    text,
          'tenant_id': '00000000-0000-0000-0000-000000000001',
        },
      );

      if (!mounted) return;
      setState(() => _isThinking = false);

      final body   = response.data;
      final answer = body?['data']?['answer'] as String?
                   ?? body?['answer']         as String?
                   ?? _getLocalFallback(text.toLowerCase());
      _streamResponse(answer);

    } catch (_) {
      // Backend offline or error — stream local demo response
      if (!mounted) return;
      setState(() => _isThinking = false);
      _streamResponse(_getLocalFallback(text.toLowerCase()));
    }
  }

  /// Local fallback used when the AI service is unreachable.
  /// Keeps the UI functional during development without a running backend.
  String _getLocalFallback(String query) {
    if (query.contains('low') || query.contains('trust')) {
      return _demoResponses['low trust']!;
    }
    if (query.contains('duplicate') || query.contains('source')) {
      return _demoResponses['duplicate']!;
    }
    if (query.contains('match') || query.contains('score') || query.contains('explain')) {
      return _demoResponses['match score']!;
    }
    return 'I\'ve analyzed your query: **"$query"**\n\n'
        'The AI service is currently offline. Start the backend with:\n'
        '```\ncd nexus-ai-mdm/infra\ndocker compose up -d\n```\n\n'
        'Once running, I can answer questions using your live entity data.';
  }

  void _streamResponse(String fullText) {
    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    final streamMsg = _ChatMessage(
      id: msgId,
      content: '',
      isUser: false,
      timestamp: DateTime.now(),
      isStreaming: true,
    );
    setState(() => _messages.add(streamMsg));
    _charIndex = 0;
    _scrollToBottom();

    _streamTimer?.cancel();
    _streamTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.aiResponseStreamDelayMs),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_charIndex >= fullText.length) {
          timer.cancel();
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == msgId);
            if (idx != -1) {
              _messages[idx] = _messages[idx].copyWith(
                content: fullText,
                isStreaming: false,
              );
            }
          });
          return;
        }
        // Stream 3 chars at a time for speed
        _charIndex = (_charIndex + 3).clamp(0, fullText.length);
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == msgId);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(
              content: fullText.substring(0, _charIndex),
            );
          }
        });
        _scrollToBottom();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
              Text('Nexus AI Copilot', style: AppTextStyles.titleMedium)
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
                    'Nexus AI v2.1 · Connected',
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
                      Text('Nexus AI',
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
    // Simple markdown renderer — bold (**text**) and newlines
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
                      'Ask anything about your data — entities, matches, quality...',
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
