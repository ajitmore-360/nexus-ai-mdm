import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/api_responses.dart';

class PrismRepository {
  final ApiClient _apiClient;

  PrismRepository(this._apiClient);

  /// Sends a chat message and streams the AI response in real time using SSE.
  ///
  /// Connects to /copilot/stream; Ollama tokens arrive as SSE events and are
  /// yielded immediately.  Falls back to /copilot (simulated char-by-char) if
  /// the streaming endpoint is unreachable or returns an error before any data.
  Stream<String> chat(String message, {List<Map<String, String>>? history}) async* {
    bool anyYielded = false;
    try {
      final response = await _apiClient.post<ResponseBody>(
        AppConstants.aiPrismStreamPath,
        data: {
          'message': message,
          'response_format': 'auto',
          if (history != null && history.isNotEmpty) 'history': history,
        },
        options: Options(
          responseType: ResponseType.stream,
          // 120s covers worst-case CPU-only generation; streaming means data
          // arrives incrementally so this is effectively a per-chunk timeout.
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      final body = response.data;
      if (body == null) throw Exception('empty SSE response body');

      // SSE format: "data: {json}\n" lines; Ollama tokens arrive as
      // {"chunk":"<token>"}.  [DONE] marks end-of-stream.
      final lineStream = body.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') break;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final chunk = json['chunk'] as String? ?? '';
          if (chunk.isNotEmpty) {
            yield chunk;
            anyYielded = true;
          }
        } catch (_) {
          // skip malformed SSE line
        }
      }
      return; // SSE completed
    } catch (e) {
      assert(() {
        debugPrint('[PrismRepository] SSE stream error: $e');
        return true;
      }());
      if (anyYielded) return; // partial response already delivered â€” don't retry
    }

    // Fallback: full response from /copilot, simulated char-by-char
    yield* _simulatedChat(message, history: history);
  }

  /// Full-response fallback â€” calls /copilot and simulates token streaming.
  Stream<String> _simulatedChat(
    String message, {
    List<Map<String, String>>? history,
  }) async* {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        AppConstants.aiPrismPath,
        data: {
          'message': message,
          'response_format': 'auto',
          if (history != null && history.isNotEmpty) 'history': history,
        },
      );

      final data = response.data;
      final fullText = data != null
          ? PrismResponse.fromJson(data).answer
          : 'I received your query but got an empty response. Please try again.';

      for (int i = 0; i < fullText.length; i++) {
        yield fullText[i];
        await Future.delayed(
          const Duration(milliseconds: AppConstants.aiResponseStreamDelayMs),
        );
      }
    } catch (e) {
      assert(() {
        debugPrint('[PrismRepository] _simulatedChat error: $e');
        return true;
      }());
      const errorText = 'I\'m having trouble connecting to the AI service. '
          'Please check your connection and try again.';
      for (int i = 0; i < errorText.length; i++) {
        yield errorText[i];
        await Future.delayed(
          const Duration(milliseconds: AppConstants.aiResponseStreamDelayMs),
        );
      }
    }
  }

  /// Executes a structured tool call (e.g. run a query, trigger an action).
  Future<ApiResult<Map<String, dynamic>>> executeToolCall(
    String toolName,
    Map<String, dynamic> parameters,
  ) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '${AppConstants.aiPrismPath}/tools/$toolName',
        data: parameters,
      );
      final data = response.data;
      if (data == null) {
        return const Failure(ApiException(message: 'Empty tool response'));
      }
      return Success(data);
    } catch (e) {
      assert(() {
        debugPrint('[PrismRepository] executeToolCall error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }
}
