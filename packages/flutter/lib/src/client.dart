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
  });

  final String url;
  final String sessionId;
  final HostHooks hooks;

  /// NOTE: Inject WebSocket channel for tests / custom transports.
  final WebSocketChannelFactory? channelFactory;
  final Iterable<String>? protocols;

  /// Extra fields merged into the handshake `clientInfo` object.
  final Map<String, dynamic>? clientInfo;

  /// Automatically reconnect when the WebSocket connection is lost.
  final bool autoReconnect;

  /// Starting delay for exponential backoff.
  final Duration initialReconnectDelay;

  /// Maximum delay between reconnection attempts.
  final Duration maxReconnectDelay;

  /// Callback notified whenever connection state changes.
  final void Function(bool connected)? onConnectionStatusChanged;
}

abstract class UiClient {
  Future<void> connect();
  void disconnect();
  void dispose();
  bool isConnected();
  Snapshot? getLastSnapshot();

  /// Execute locally without the network (useful for demos/tests).
  Future<CommandResult> executeLocal(Command command);

  /// Trigger an immediate reconnection attempt (e.g. when app resumes from background).
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
      channel.sink.add(jsonEncode(message));
    } catch (_) {}
  }

  Future<void> _handleCommand(Command command) async {
    final result = await executeCommand(command, _ctx);
    _send({'type': 'result', 'result': result.toJson()});
  }

  void _onMessage(String raw) {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    if (message['type'] == 'ping') {
      _send({'type': 'pong'});
      return;
    }

    if (message['type'] == 'command') {
      final validated = validateCommand(message['command']);
      if (validated.ok && validated.value != null) {
        unawaited(_handleCommand(validated.value!));
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
          _options.onConnectionStatusChanged?.call(true);

          if (_handshakeCompleter != null && !_handshakeCompleter!.isCompleted) {
            _handshakeCompleter!.complete();
          }
          return;
        }
        _onMessage(data);
      },
      onError: (Object error) {
        _handleDisconnect(error);
      },
      onDone: () {
        _handleDisconnect(null);
      },
    );

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
      _options.onConnectionStatusChanged?.call(false);
    }

    if (_options.autoReconnect && !_manuallyDisconnected && !_disposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_manuallyDisconnected || _disposed || _connected) return;
    _reconnectTimer?.cancel();

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
    try {
      _setupChannel();
    } catch (_) {
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

/// Thin Flutter / Dart client: handshake, receive commands, return results.
UiClient createUiClient(UiClientOptions options) => _UiClientImpl(options);
