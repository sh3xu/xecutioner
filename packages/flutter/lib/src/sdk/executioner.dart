import 'dart:async';

import 'package:flutter/widgets.dart';

import '../client.dart';
import '../executors.dart';
import '../navigation/context_reader.dart';
import '../navigation/types.dart';
import '../protocol/types.dart';
import '../types.dart';
import 'actions.dart';
import 'commands.dart';
import 'policy.dart';

/// Everything needed to plug Xecutioner into an app.
///
/// The framework-agnostic core: navigation adapter, declared screens, action
/// registry, policy, and optional remote [url].
class XecutionerConfig {
  const XecutionerConfig({
    this.app,
    this.url,
    this.sessionId,
    this.navigation,
    this.screens = const [],
    this.actions,
    this.policy = XecutionerPolicy.permissive,
    this.getRootNode,
    this.performAction,
    this.onApprovalRequest,
    this.onAiActing,
    this.connectOnInit = true,
    this.clientInfo,
    this.autoReconnect = true,
    this.initialReconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
  });

  /// App metadata sent in `get_context`. Defaults to a generic host app.
  final AppInfo? app;

  /// WebSocket URL of the Xecutioner server. When null the SDK runs in
  /// local-only mode: [Xecutioner.executeLocal] and the convenience methods
  /// still work, but no remote commands are received.
  final String? url;

  /// Session id for the handshake. Auto-generated when omitted.
  final String? sessionId;

  /// Framework navigation bridge (go_router / Navigator / GetX / custom).
  final NavigationAdapter? navigation;

  /// Developer-declared screen map. Screen ids matching [policy] screen
  /// patterns automatically inherit `deny` / `approval` policies.
  final List<ScreenDefinition> screens;

  /// Element registry. When omitted a fresh [ExecutionerActions] is created
  /// and exposed as [Xecutioner.actions].
  final ExecutionerActions? actions;

  /// Client-side allow / approval / deny / redact rules.
  final XecutionerPolicy policy;

  /// Escape hatch: fully custom host tree. When set, the action registry is
  /// still used for dispatch but not for snapshot nodes.
  final GetRootNode? getRootNode;

  /// Escape hatch: custom action dispatch. Called when the registry cannot
  /// handle a request (unknown element or unsupported action).
  final PerformAction? performAction;

  /// User approval prompt hook. Consulted for policy `approval` decisions and
  /// every element action, matching the low-level `HostHooks` semantics.
  final OnApprovalRequest? onApprovalRequest;

  final OnAiActing? onAiActing;

  /// Connect to [url] during [Xecutioner.init]. Failures are logged and the
  /// SDK stays in local mode.
  final bool connectOnInit;

  /// Extra handshake `clientInfo` fields (platform, version, ...).
  final Map<String, dynamic>? clientInfo;

  /// Automatically reconnect on network loss or app resume from background.
  final bool autoReconnect;

  /// Initial backoff delay before reconnecting.
  final Duration initialReconnectDelay;

  /// Maximum backoff delay between reconnection attempts.
  final Duration maxReconnectDelay;
}

class _XecutionerLifecycleObserver with WidgetsBindingObserver {
  _XecutionerLifecycleObserver(this._xecutioner);
  final Xecutioner _xecutioner;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _xecutioner._onAppResumed();
    }
  }
}

/// Plug-and-play Xecutioner host SDK.
class Xecutioner {
  Xecutioner._(this.config) : actions = config.actions ?? ExecutionerActions() {
    _hooks = _buildHooks();
    _localCtx = ExecuteContext(
      hooks: _hooks,
      lastSnapshot: null,
      setLastSnapshot: (_) {},
    );
    _initLifecycleObserver();
  }

  final XecutionerConfig config;

  /// Element registry backing snapshots and action dispatch.
  final ExecutionerActions actions;

  late final HostHooks _hooks;
  late final ExecuteContext _localCtx;

  UiClient? _client;
  String? _sessionId;
  bool _disposed = false;
  bool _isActing = false;
  _XecutionerLifecycleObserver? _lifecycleObserver;

  final _logController = StreamController<String>.broadcast();
  final _actingController = StreamController<bool>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  /// Human-readable event log (connect, dispatch misses, policy decisions).
  Stream<String> get logs => _logController.stream;

  /// Emits whenever the host is executing an AI command.
  Stream<bool> get acting => _actingController.stream;
  bool get isActing => _isActing;

  /// Emits connection state changes (`true` when connected, `false` when lost).
  Stream<bool> get connectionStatus => _connectionController.stream;

  /// The connected client, when a [XecutionerConfig.url] was provided.
  UiClient? get client => _client;

  /// The session id used for the handshake (null until [connect]).
  String? get sessionId => _sessionId;

  /// Whether a remote client is currently connected.
  bool get isConnected => _client?.isConnected() ?? false;

  void _initLifecycleObserver() {
    try {
      final binding = WidgetsBinding.instance;
      _lifecycleObserver = _XecutionerLifecycleObserver(this);
      binding.addObserver(_lifecycleObserver!);
    } catch (_) {
      // Running in pure Dart environment without Flutter WidgetsBinding.
    }
  }

  void _onAppResumed() {
    if (_disposed || isConnected || !config.autoReconnect) return;
    _log('app resumed to foreground: triggering reconnect');
    _client?.reconnectNow();
  }

  static Future<Xecutioner> init(XecutionerConfig config) async {
    final xecutioner = Xecutioner._(config);
    if (config.connectOnInit && config.url != null) {
      try {
        await xecutioner.connect();
      } catch (error) {
        xecutioner._log('connect failed ($error); running in local mode');
      }
    }
    return xecutioner;
  }

  /// (Re)connect to the configured server. No-op-safe to call again.
  Future<void> connect() async {
    final url = config.url;
    if (url == null) {
      throw StateError('xecutioner: no server url configured');
    }
    _sessionId ??= config.sessionId ?? _generateSessionId();
    _client ??= createUiClient(
      UiClientOptions(
        url: url,
        sessionId: _sessionId!,
        hooks: _hooks,
        protocols: const ['xecutioner'],
        clientInfo: config.clientInfo,
        autoReconnect: config.autoReconnect,
        initialReconnectDelay: config.initialReconnectDelay,
        maxReconnectDelay: config.maxReconnectDelay,
        onLog: (msg) => _log(msg),
        onConnectionStatusChanged: (connected) {
          if (!_disposed) {
            _connectionController.add(connected);
            _log(connected
                ? '[STATUS] Connected to $url (session $_sessionId)'
                : '[STATUS] Connection lost; will attempt reconnect');
          }
        },
      ),
    );
    await _client!.connect();
    _log('connected to $url (session $_sessionId)');
  }

  void disconnect() {
    _client?.disconnect();
    _log('disconnected');
  }

  /// Trigger an immediate reconnection attempt (e.g. after regaining internet or returning from background).
  Future<void> reconnect() async {
    if (_client != null) {
      await _client!.reconnectNow();
    } else {
      await connect();
    }
  }

  /// Execute a command locally — identical code path to remote commands,
  /// without requiring a server connection.
  Future<CommandResult> executeLocal(Command command) =>
      executeCommand(command, _localCtx);

  Future<CommandResult> tap(String elementId, {String? snapshotId}) =>
      executeLocal(XecutionerCommands.tap(elementId, snapshotId: snapshotId));

  Future<CommandResult> input(
    String elementId,
    String text, {
    String? snapshotId,
  }) =>
      executeLocal(
        XecutionerCommands.input(elementId, text, snapshotId: snapshotId),
      );

  Future<CommandResult> scroll(
    String elementId, {
    String? direction,
    num? amount,
    String? snapshotId,
  }) =>
      executeLocal(
        XecutionerCommands.scroll(
          elementId,
          direction: direction,
          amount: amount,
          snapshotId: snapshotId,
        ),
      );

  Future<CommandResult> navigate(
    String screenId, {
    Map<String, dynamic>? params,
  }) =>
      executeLocal(XecutionerCommands.navigate(screenId, params: params));

  Future<CommandResult> back() =>
      executeLocal(XecutionerCommands.back());

  Future<CommandResult> readScreen() =>
      executeLocal(XecutionerCommands.readScreen());

  Future<CommandResult> getContext({num? maxDestinations}) =>
      executeLocal(XecutionerCommands.getContext(maxDestinations: maxDestinations));

  Future<CommandResult> waitFor({
    String? elementId,
    String? labelContains,
    num? timeoutMs,
  }) =>
      executeLocal(
        XecutionerCommands.waitFor(
          elementId: elementId,
          labelContains: labelContains,
          timeoutMs: timeoutMs,
        ),
      );

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_lifecycleObserver != null) {
      try {
        WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      } catch (_) {}
      _lifecycleObserver = null;
    }
    _client?.dispose();
    _client = null;
    await _actingController.close();
    await _connectionController.close();
    await _logController.close();
  }

  void _log(String message) {
    if (_disposed) return;
    _logController.add('[xecutioner] $message');
  }

  String _generateSessionId() {
    final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rand = DateTime.now().microsecondsSinceEpoch
        .toRadixString(36)
        .padLeft(8, '0')
        .substring(0, 8);
    return 'xec_${now}_$rand';
  }

  HostHooks _buildHooks() {
    final app =
        config.app ?? const AppInfo(name: 'app', description: 'Host application');
    final reader = createAppContextReader(
      CreateAppContextReaderOptions(
        app: app,
        navigation: config.navigation,
        screens: _effectiveScreens(),
      ),
    );
    return HostHooks(
      getRootNode: _getRootNode,
      performAction: _performAction,
      getScreenMeta: _getScreenMeta,
      contextReader: reader,
      navigation: config.navigation,
      onAiActing: _onAiActing,
      onApprovalRequest: _onApprovalRequest,
    );
  }

  List<ScreenDefinition> _effectiveScreens() {
    return config.screens.map((screen) {
      if (screen.policy != null) return screen;
      final decision = config.policy.checkScreen(screen.id);
      if (decision == XecutionerPolicyDecision.allow) return screen;
      return ScreenDefinition(
        id: screen.id,
        title: screen.title,
        description: screen.description,
        params: screen.params,
        reachableFrom: screen.reachableFrom,
        requiresAuth: screen.requiresAuth,
        policy: decision == XecutionerPolicyDecision.deny ? 'deny' : 'approval',
      );
    }).toList();
  }

  HostUiNode? _getRootNode() {
    final override = config.getRootNode;
    if (override != null) return override();

    final nodes = actions.toHostUiNodes();
    _applyRedaction(nodes);
    if (nodes.isEmpty) return null;

    return HostUiNode(
      testID: 'xecutioner-root',
      accessibilityLabel: 'Xecutioner UI',
      accessibilityRole: 'summary',
      props: const {'source': 'xecutioner_registry'},
      children: nodes,
    );
  }

  void _applyRedaction(List<HostUiNode> nodes) {
    void visit(HostUiNode node) {
      final id = node.testID;
      if (id != null && config.policy.shouldRedact(id)) {
        node.xecutionerRedact = true;
      }
      node.children?.forEach(visit);
    }

    nodes.forEach(visit);
  }

  ScreenMeta _getScreenMeta() {
    final state = config.navigation?.getState.call();
    if (state == null) return const ScreenMeta();
    return ScreenMeta(
      screen: state.screenId,
      route: state.stack.isNotEmpty ? state.stack.last : state.screenId,
    );
  }

  Future<void> _performAction(PerformActionRequest request) async {
    _log(
      '[ACTION] Dispatching "${request.action}" on "${request.elementId}"'
      '${request.text != null ? ' (text="${request.text}")' : ''}',
    );
    try {
      await actions.dispatch(request);
      _log('[ACTION] ✓ Handled "${request.action}" on "${request.elementId}" successfully');
    } catch (error) {
      final fallback = config.performAction;
      if (fallback == null) {
        _log('[ACTION] ✕ Failed "${request.action}" on "${request.elementId}": $error');
        rethrow;
      }
      _log(
        '[ACTION] Registry miss for "${request.action}" on "${request.elementId}" ($error); '
        'delegating to host fallback performAction',
      );
      await fallback(request);
      _log('[ACTION] ✓ Handled by fallback performAction');
    }
  }

  Future<bool> _onApprovalRequest(ApprovalRequest request) async {
    final elementId = request.elementId;
    if (elementId != null) {
      final decision = config.policy.checkElement(elementId);
      if (decision == XecutionerPolicyDecision.deny) {
        _log('[POLICY] ✕ BLOCKED BY POLICY: element "$elementId" is denied');
        return false;
      }
      if (decision == XecutionerPolicyDecision.approval) {
        _log('[POLICY] ⚠ USER APPROVAL REQUIRED for element "$elementId"');
        final handler = config.onApprovalRequest;
        if (handler != null) {
          final approved = await handler(request);
          _log('[POLICY] User approval result for "$elementId": ${approved ? "ALLOWED" : "DENIED"}');
          return approved;
        }
        _log('[POLICY] No onApprovalRequest handler provided; allowing "$elementId" by default');
        return true;
      }
    }

    final screenId = request.screenId;
    if (request.action == 'navigate' && screenId != null) {
      final decision = config.policy.checkScreen(screenId);
      if (decision == XecutionerPolicyDecision.deny) {
        _log('[POLICY] ✕ BLOCKED BY POLICY: screen "$screenId" is denied');
        return false;
      }
      if (decision == XecutionerPolicyDecision.approval) {
        _log('[POLICY] ⚠ USER APPROVAL REQUIRED for navigation to "$screenId"');
        final handler = config.onApprovalRequest;
        if (handler != null) {
          final approved = await handler(request);
          _log('[POLICY] User approval result for screen "$screenId": ${approved ? "ALLOWED" : "DENIED"}');
          return approved;
        }
        _log('[POLICY] No onApprovalRequest handler provided; allowing screen "$screenId" by default');
        return true;
      }
    }

    final handler = config.onApprovalRequest;
    if (handler != null) return handler(request);
    return true;
  }

  void _onAiActing(bool acting) {
    _isActing = acting;
    _actingController.add(acting);
    config.onAiActing?.call(acting);
  }
}
