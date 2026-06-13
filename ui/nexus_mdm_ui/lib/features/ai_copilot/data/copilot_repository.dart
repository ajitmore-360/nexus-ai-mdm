import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/api_responses.dart';

class CopilotRepository {
  final ApiClient _apiClient;

  CopilotRepository(this._apiClient);

  /// Sends a chat message and streams the AI response character-by-character.
  ///
  /// Calls the copilot endpoint; on success it simulates streaming by yielding
  /// the response text one character at a time with [AppConstants.aiResponseStreamDelayMs]
  /// delay between each character. On error, yields an error message string.
  Stream<String> chat(String message, {List<Map<String, String>>? history}) async* {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        AppConstants.aiCopilotPath,
        data: {
          'message': message,
          if (history != null && history.isNotEmpty) 'history': history,
        },
      );

      final data = response.data;
      final fullText = data != null
          ? CopilotResponse.fromJson(data).answer
          : 'I received your query but got an empty response. Please try again.';

      // Stream character-by-character to simulate token streaming
      for (int i = 0; i < fullText.length; i++) {
        yield fullText[i];
        await Future.delayed(
          const Duration(milliseconds: AppConstants.aiResponseStreamDelayMs),
        );
      }
    } catch (e) {
      assert(() {
        debugPrint('[CopilotRepository] chat error: $e');
        return true;
      }());
      // Yield a friendly error message streamed the same way
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
        '${AppConstants.aiCopilotPath}/tools/$toolName',
        data: parameters,
      );
      final data = response.data;
      if (data == null) {
        return const Failure(ApiException(message: 'Empty tool response'));
      }
      return Success(data);
    } catch (e) {
      assert(() {
        debugPrint('[CopilotRepository] executeToolCall error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }
}
