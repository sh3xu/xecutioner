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
  });

  final String url;
  final String sessionId;
  final HostHooks hooks;

  /// NOTE: Inject WebSocket channel for tests / custom transports.
  final WebSocketChannelFactory? channelFactory;
  final Iterable<String>? protocols;
}

abstract class UiClient {
  Future<void> connect();
  void disconnect();
  bool isConnected();
  Snapshot? getLastSnapshot();

  /// Execute locally without the network (useful for demos/tests).
  Future<CommandResult> executeLocal(Command command);
}

class _UiClientImpl implements UiClient {
  _UiClientImpl(this._options);

  final UiClientOptions _options;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Snapshot? _lastSnapshot;
  bool _connected = false;

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
    channel.sink.add(jsonEncode(message));
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

  @override
  Future<void> connect() async {
    final completer = Completer<void>();

    final uri = Uri.parse(_options.url);
    final factory = _options.channelFactory ??
        ((Uri u, {Iterable<String>? protocols}) =>
            WebSocketChannel.connect(u, protocols: protocols));

    try {
      _channel = factory(uri, protocols: _options.protocols);
    } catch (error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
      rethrow;
    }

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
          if (!completer.isCompleted) {
            completer.complete();
          }
          return;
        }
        _onMessage(data);
      },
      onError: (Object error) {
        if (!_connected && !completer.isCompleted) {
          completer.completeError(
            StateError('WebSocket connection failed: $error'),
          );
        }
      },
      onDone: () {
        _connected = false;
      },
    );

    _send({
      'type': 'handshake',
      'protocolVersion': protocolVersion,
      'sessionId': _options.sessionId,
      'capabilities': List<String>.from(clientCapabilities),
      'clientInfo': {'platform': 'flutter'},
    });

    return completer.future;
  }

  @override
  void disconnect() {
    _connected = false;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_channel?.sink.close());
    _channel = null;
  }
}

/// Thin Flutter / Dart client: handshake, receive commands, return results.
UiClient createUiClient(UiClientOptions options) => _UiClientImpl(options);
