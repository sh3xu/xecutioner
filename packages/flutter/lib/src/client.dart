import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'executors.dart';
import 'protocol/constants.dart';
import 'protocol/types.dart';
import 'protocol/validate.dart';
import 'types.dart';

typedef WebSocketChannelFactory = WebSocketChannel Function(
  Uri uri, {
  Iterable<String>? protocols,
});

/// Configuration options for creating a [UiClient].
class UiClientOptions {
  const UiClientOptions({
    required this.url,
    required this.sessionId,
    required this.hooks,
    this.channelFactory,
    this.protocols,
    this.clientInfo,
    this.autoReconnect = true,
    this.initialReconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.onConnectionStatusChanged,
    this.onLog,
  });

  /// Remote WebSocket server endpoint (e.g. `ws://10.0.2.2:4100/xecutioner`).
  final String url;

  /// Session identifier shared with the backend AI agent tool binding.
  final String sessionId;

  /// Host hooks providing UI tree snapshots, action dispatch, and navigation.
  final HostHooks hooks;

  /// Injected factory for custom WebSocket transports or unit test doubles.
  final WebSocketChannelFactory? channelFactory;

  /// Subprotocols sent during the WebSocket upgrade handshake.
  final Iterable<String>? protocols;

  /// Metadata merged into the handshake `clientInfo` object (e.g. app version, OS).
  final Map<String, dynamic>? clientInfo;

  /// Whether to automatically reconnect with exponential backoff on connection loss.
  final bool autoReconnect;

  /// Initial delay before the first reconnection attempt.
  final Duration initialReconnectDelay;

  /// Maximum delay ceiling for exponential backoff between reconnection attempts.
  final Duration maxReconnectDelay;

  /// Callback invoked whenever connection state changes (`true` = connected, `false` = disconnected).
  final void Function(bool connected)? onConnectionStatusChanged;

  /// Stream/callback for detailed networking and protocol execution logs.
  final void Function(String message)? onLog;
}

/// Low-level protocol client connecting the Flutter app to the Xecutioner WebSocket server.
abstract class UiClient {
  /// Connects to the configured WebSocket server and completes when the handshake succeeds.
  Future<void> connect();

  /// Closes the WebSocket connection and stops auto-reconnect timers.
  void disconnect();

  /// Completely releases all resources, subscriptions, and timers.
  void dispose();

  /// Whether the WebSocket is currently connected and authenticated.
  bool isConnected();

  /// Returns the most recently captured UI snapshot, if any.
  Snapshot? getLastSnapshot();

  /// Executes a command locally without touching the network (ideal for unit testing).
  Future<CommandResult> executeLocal(Command command);

  /// Triggers an immediate reconnection attempt, bypassing any active backoff timer.
  Future<void> reconnectNow();
}

class _UiClientImpl implements UiClient {
  _UiClientImpl(this._options) : _currentDelay = _options.initialReconnectDelay;

  final UiClientOptions _options;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Snapshot? _lastSnapshot;
  bool _connected = false;
  bool _manuallyDisconnected = false;
  bool _disposed = false;

  Timer? _reconnectTimer;
  Duration _currentDelay;
  Completer<void>? _handshakeCompleter;

  late final ExecuteContext _ctx = ExecuteContext(
    hooks: _options.hooks,
    lastSnapshot: null,
    setLastSnapshot: (snapshot) {
      _lastSnapshot = snapshot;
    },
  );

  void _log(String message) {
    _options.onLog?.call(message);
  }

  @override
  Snapshot? getLastSnapshot() => _lastSnapshot;

  @override
  Future<CommandResult> executeLocal(Command command) =>
      executeCommand(command, _ctx);

  @override
  bool isConnected() => _connected && _channel != null;

  void _send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    try {
      final json = jsonEncode(message);
      channel.sink.add(json);
    } catch (e) {
      _log('[WS] Error sending message: $e');
    }
  }

  String _formatCommandParams(Command c) {
    final parts = <String>[];
    if (c.elementId != null) parts.add('elementId="${c.elementId}"');
    if (c.screenId != null) parts.add('screenId="${c.screenId}"');
    if (c.text != null) {
      final isSensitive =
          (c.elementId?.toLowerCase().contains('password') ?? false) ||
          (c.elementId?.toLowerCase().contains('secret') ?? false);
      parts.add('text="${isSensitive ? '******' : c.text}"');
    }
    if (c.direction != null) parts.add('direction="${c.direction}"');
    if (c.amount != null) parts.add('amount=${c.amount}');
    if (c.params != null && c.params!.isNotEmpty) parts.add('params=${c.params}');
    if (c.waitCondition != null) parts.add('waitCondition=${c.waitCondition}');
    if (c.maxDestinations != null) parts.add('maxDestinations=${c.maxDestinations}');
    return parts.isEmpty ? 'none' : parts.join(', ');
  }

  Future<void> _handleCommand(Command command) async {
    final stopwatch = Stopwatch()..start();
    _log(
      '[CMD] ◀ Received command "${command.action}" '
      '(callId=${command.callId}, ${_formatCommandParams(command)})',
    );

    try {
      final result = await executeCommand(command, _ctx);
      stopwatch.stop();

      if (result.ok) {
        _log(
          '[CMD] ▶ ✓ Successfully executed "${command.action}" '
          'in ${stopwatch.elapsedMilliseconds}ms '
          '(snapshot=${result.snapshot?.snapshotId ?? 'none'})',
        );
      } else {
        _log(
          '[CMD] ▶ ✕ Failed "${command.action}" in ${stopwatch.elapsedMilliseconds}ms '
          '| error [${result.errorCode}]: ${result.errorMessage}',
        );
      }

      _send({'type': 'result', 'result': result.toJson()});
    } catch (error, stack) {
      stopwatch.stop();
      _log(
        '[CMD] ▶ ✕ Unhandled exception executing "${command.action}" '
        'in ${stopwatch.elapsedMilliseconds}ms: $error\n$stack',
      );
      _send({
        'type': 'result',
        'result': {
          'callId': command.callId,
          'ok': false,
          'error': {
            'code': 'internal_error',
            'message': 'Host exception: $error',
          },
        },
      });
    }
  }

  void _onMessage(String raw) {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      _log('[WS] Received malformed JSON from server: $raw ($e)');
      return;
    }

    final type = message['type'];
    if (type == 'ping') {
      _log('[WS] Received ping from server -> replying with pong');
      _send({'type': 'pong'});
      return;
    }

    if (type == 'command') {
      final rawCommand = message['command'];
      final validated = validateCommand(rawCommand);
      if (validated.ok && validated.value != null) {
        unawaited(_handleCommand(validated.value!));
      } else {
        _log(
          '[WS] Invalid command payload received from server: '
          '${validated.error ?? "validation failed"}. Payload: $rawCommand',
        );
      }
    }
  }

  void _cleanupSocket() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _setupChannel() {
    _cleanupSocket();

    _log('[WS] Opening connection to ${_options.url} (session: ${_options.sessionId})...');
    final uri = Uri.parse(_options.url);
    final factory = _options.channelFactory ??
        ((Uri u, {Iterable<String>? protocols}) =>
            WebSocketChannel.connect(u, protocols: protocols));

    _channel = factory(uri, protocols: _options.protocols);

    _subscription = _channel!.stream.listen(
      (event) {
        final data = event is String ? event : event.toString();
        Map<String, dynamic>? message;
        try {
          message = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          return;
        }

        if (message['type'] == 'handshake') {
          _connected = true;
          _currentDelay = _options.initialReconnectDelay;
          _log('[WS] ✓ Handshake successful! Client authenticated with server.');
          _options.onConnectionStatusChanged?.call(true);

          if (_handshakeCompleter != null && !_handshakeCompleter!.isCompleted) {
            _handshakeCompleter!.complete();
          }
          return;
        }
        _onMessage(data);
      },
      onError: (Object error) {
        _log('[WS] Socket stream error: $error');
        _handleDisconnect(error);
      },
      onDone: () {
        _log('[WS] Socket stream closed by remote server');
        _handleDisconnect(null);
      },
    );

    _log('[WS] Sending handshake (protocol=$protocolVersion, session=${_options.sessionId})...');
    _send({
      'type': 'handshake',
      'protocolVersion': protocolVersion,
      'sessionId': _options.sessionId,
      'capabilities': List<String>.from(clientCapabilities),
      'clientInfo': {'platform': 'flutter', ...?_options.clientInfo},
    });
  }

  void _handleDisconnect(Object? error) {
    final wasConnected = _connected;
    _connected = false;
    _cleanupSocket();

    if (_handshakeCompleter != null && !_handshakeCompleter!.isCompleted) {
      _handshakeCompleter!.completeError(
        StateError('WebSocket connection failed: $error'),
      );
    }

    if (wasConnected) {
      _log('[WS] Connection lost.');
      _options.onConnectionStatusChanged?.call(false);
    }

    if (_options.autoReconnect && !_manuallyDisconnected && !_disposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_manuallyDisconnected || _disposed || _connected) return;
    _reconnectTimer?.cancel();

    _log('[WS] Scheduling auto-reconnect in ${_currentDelay.inSeconds}s (backoff timer)...');
    _reconnectTimer = Timer(_currentDelay, () {
      if (!_manuallyDisconnected && !_disposed && !_connected) {
        _attemptReconnect();
      }
    });

    // Exponential backoff
    final nextMs = (_currentDelay.inMilliseconds * 1.5).round();
    final maxMs = _options.maxReconnectDelay.inMilliseconds;
    _currentDelay = Duration(milliseconds: nextMs > maxMs ? maxMs : nextMs);
  }

  Future<void> _attemptReconnect() async {
    if (_manuallyDisconnected || _disposed || _connected) return;
    _log('[WS] Attempting reconnection now...');
    try {
      _setupChannel();
    } catch (e) {
      _log('[WS] Reconnect attempt failed immediately: $e');
      _scheduleReconnect();
    }
  }

  @override
  Future<void> connect() async {
    _manuallyDisconnected = false;
    _reconnectTimer?.cancel();
    _currentDelay = _options.initialReconnectDelay;

    _handshakeCompleter = Completer<void>();

    try {
      _setupChannel();
    } catch (error) {
      _log('[WS] Initial connection error: $error');
      if (!_handshakeCompleter!.isCompleted) {
        _handshakeCompleter!.completeError(error);
      }
      if (_options.autoReconnect && !_manuallyDisconnected) {
        _scheduleReconnect();
      }
      rethrow;
    }

    return _handshakeCompleter!.future;
  }

  @override
  Future<void> reconnectNow() async {
    if (_connected || _manuallyDisconnected || _disposed) return;
    _log('[WS] Immediate reconnect requested (bypassing delay timer)');
    _reconnectTimer?.cancel();
    _currentDelay = _options.initialReconnectDelay;
    await _attemptReconnect();
  }

  @override
  void disconnect() {
    _manuallyDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final wasConnected = _connected;
    _connected = false;
    _cleanupSocket();
    _log('[WS] Client disconnected manually.');
    if (wasConnected) {
      _options.onConnectionStatusChanged?.call(false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
  }
}

/// Creates a new [UiClient] instance configured with [options].
UiClient createUiClient(UiClientOptions options) => _UiClientImpl(options);
