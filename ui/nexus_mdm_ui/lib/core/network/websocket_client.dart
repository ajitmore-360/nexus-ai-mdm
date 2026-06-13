import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

// ──────────────────────────────────────────────
// Public enums & models
// ──────────────────────────────────────────────

/// Connection state exposed to UI via [WebSocketClient.connectionState].
enum WsConnectionState {
  connecting,
  connected,
  disconnected,
  error,
}

/// Internal reconnect state (not exposed publicly).
enum WebSocketState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// Parsed message from the server.
class WebSocketMessage {
  final String type;
  final String? entityId;
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  const WebSocketMessage({
    required this.type,
    this.entityId,
    required this.payload,
    required this.timestamp,
  });

  factory WebSocketMessage.fromJson(Map<String, dynamic> json) =>
      WebSocketMessage(
        type: json['type'] as String? ?? 'unknown',
        entityId: json['entity_id'] as String?,
        payload: json['payload'] as Map<String, dynamic>? ?? const {},
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}

// ──────────────────────────────────────────────
// WebSocketClient
// ──────────────────────────────────────────────

class WebSocketClient {
  // ── Stream controllers ───────────────────────
  final StreamController<Map<String, dynamic>> _rawMessageController =
      StreamController<Map<String, dynamic>>.broadcast();

  // ── Public surface ───────────────────────────

  /// Raw deserialized messages as Map — used by notification centre and shell.
  Stream<Map<String, dynamic>> get messages => _rawMessageController.stream;

  /// ValueNotifier-based state: easy to consume with ValueListenableBuilder
  /// or to read synchronously without subscribing.
  final ValueNotifier<WsConnectionState> connectionState =
      ValueNotifier(WsConnectionState.disconnected);

  // ── Internal ─────────────────────────────────
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;

  static const int _maxReconnectAttempts = 10;
  static const Duration _pingInterval = Duration(seconds: 30);
  // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (cap)
  static const Duration _baseDelay = Duration(seconds: 1);
  static const Duration _maxDelay = Duration(seconds: 30);

  // ── Connect ──────────────────────────────────

  Future<void> connect() async {
    if (_disposed) return;
    if (connectionState.value == WsConnectionState.connecting ||
        connectionState.value == WsConnectionState.connected) {
      return;
    }

    _setPublicState(WsConnectionState.connecting);
    _shouldReconnect = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final tenantId = prefs.getString(AppConstants.storageTenantId) ??
          '00000000-0000-0000-0000-000000000001';
      final userId = prefs.getString(AppConstants.storageUserId) ?? 'anon';

      // Primary URL format: ws://localhost:8086/ws?tenant_id=...&user_id=...
      final uri = Uri.parse(
        'ws://localhost:8086/ws?tenant_id=$tenantId&user_id=$userId',
      );

      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _setPublicState(WsConnectionState.connected);
      _reconnectAttempts = 0;
      _startPing();

      _channelSub = _channel!.stream.listen(
        _onData,
        onError: _onChannelError,
        onDone: _onChannelDone,
        cancelOnError: false,
      );
    } catch (e) {
      _setPublicState(WsConnectionState.error);
      _scheduleReconnect();
    }
  }

  // ── Data handler ─────────────────────────────

  void _onData(dynamic raw) {
    if (_disposed) return;
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;

      // Absorb server pong silently
      if (json['type'] == 'pong') return;

      _rawMessageController.add(json);
    } catch (_) {
      // Malformed frame — ignore
    }
  }

  void _onChannelError(Object error) {
    _setPublicState(WsConnectionState.error);
    _tearDownChannel();
    _scheduleReconnect();
  }

  void _onChannelDone() {
    if (connectionState.value == WsConnectionState.connected) {
      _tearDownChannel();
      _scheduleReconnect();
    }
  }

  // ── Ping/pong ────────────────────────────────

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (connectionState.value == WsConnectionState.connected) {
        _send({'type': 'ping', 'timestamp': DateTime.now().toIso8601String()});
      }
    });
  }

  // ── Reconnect ────────────────────────────────

  void _scheduleReconnect() {
    if (_disposed || !_shouldReconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _setPublicState(WsConnectionState.disconnected);
      return;
    }

    _reconnectAttempts++;
    final seconds =
        (_baseDelay.inSeconds * (1 << (_reconnectAttempts - 1).clamp(0, 4)))
            .clamp(1, _maxDelay.inSeconds);
    final delay = Duration(seconds: seconds);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, connect);
  }

  // ── Send ─────────────────────────────────────

  void _send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {
      // Sink may be closed — ignore
    }
  }

  void sendMessage(String type, Map<String, dynamic> payload) {
    if (connectionState.value == WsConnectionState.connected) {
      _send({
        'type': type,
        'payload': payload,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  void subscribe(String topic) =>
      sendMessage('subscribe', {'topic': topic});

  void unsubscribe(String topic) =>
      sendMessage('unsubscribe', {'topic': topic});

  // ── Disconnect ───────────────────────────────

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _tearDownChannel();
    _setPublicState(WsConnectionState.disconnected);
  }

  void _tearDownChannel() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channelSub?.cancel();
    _channelSub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  // ── Dispose ──────────────────────────────────

  void dispose() {
    _disposed = true;
    _shouldReconnect = false;
    _tearDownChannel();
    connectionState.dispose();
    _rawMessageController.close();
  }

  // ── Helpers ──────────────────────────────────

  void _setPublicState(WsConnectionState state) {
    if (!_disposed) {
      connectionState.value = state;
    }
  }

  // ── Legacy compatibility ──────────────────────
  // The existing code in the repo uses WebSocketState + stateChanges.
  // These shims allow old code to continue compiling unchanged.

  Stream<WebSocketState> get stateChanges => connectionState.value.toInternal
      .let((_) => _rawMessageController.stream.map((_) => _internalState));

  WebSocketState get _internalState {
    switch (connectionState.value) {
      case WsConnectionState.connecting:
        return WebSocketState.connecting;
      case WsConnectionState.connected:
        return WebSocketState.connected;
      case WsConnectionState.error:
        return WebSocketState.error;
      case WsConnectionState.disconnected:
        return WebSocketState.disconnected;
    }
  }

  WebSocketState get state => _internalState;
}

// ──────────────────────────────────────────────
// Small extension helpers
// ──────────────────────────────────────────────

extension _WsStateExt on WsConnectionState {
  WebSocketState get toInternal {
    switch (this) {
      case WsConnectionState.connecting:
        return WebSocketState.connecting;
      case WsConnectionState.connected:
        return WebSocketState.connected;
      case WsConnectionState.error:
        return WebSocketState.error;
      case WsConnectionState.disconnected:
        return WebSocketState.disconnected;
    }
  }
}

extension _LetExt<T> on T {
  R let<R>(R Function(T) block) => block(this);
}
