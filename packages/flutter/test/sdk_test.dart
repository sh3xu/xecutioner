import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xecutioner_flutter/xecutioner_flutter.dart';

class _FakeSink implements WebSocketSink {
  _FakeSink(this._inner);
  final StreamSink<dynamic> _inner;

  @override
  void add(dynamic data) => _inner.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<dynamic> stream) => _inner.addStream(stream);

  @override
  Future<void> close([int? closeCode, String? closeReason]) => _inner.close();

  @override
  Future<void> get done => _inner.done;
}

class _FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  _FakeWebSocketChannel(this.incoming, this.outgoingSink);
  final Stream<dynamic> incoming;
  final StreamSink<dynamic> outgoingSink;

  @override
  Stream<dynamic> get stream => incoming;

  @override
  WebSocketSink get sink => _FakeSink(outgoingSink);

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();
}

void main() {
  group('ExecutionerActions', () {
    test('dispatches tap to the registered handler', () async {
      final actions = ExecutionerActions();
      var taps = 0;
      actions.onTap('btn', label: 'Go', onTap: () => taps++);

      await actions.dispatch(
        const PerformActionRequest(action: 'tap', elementId: 'btn'),
      );
      expect(taps, 1);
    });

    test('dispatches input through a bound setter', () async {
      final actions = ExecutionerActions();
      String? value;
      actions.onInput(
        'field',
        getValue: () => value,
        setValue: (text) => value = text,
      );

      await actions.dispatch(
        const PerformActionRequest(
          action: 'input',
          elementId: 'field',
          text: 'hello',
        ),
      );
      expect(value, 'hello');
    });

    test('throws element_not_found for unknown ids', () {
      final actions = ExecutionerActions();
      expect(
        () => actions.dispatch(
          const PerformActionRequest(action: 'tap', elementId: 'nope'),
        ),
        throwsA(
          isA<ExecutionerActionException>().having(
            (e) => e.code,
            'code',
            'element_not_found',
          ),
        ),
      );
    });

    test('throws not_actionable when no handler is registered', () {
      final actions = ExecutionerActions()
        ..add(ExecutionerElement(id: 'view', role: 'view'));
      expect(
        () => actions.dispatch(
          const PerformActionRequest(action: 'tap', elementId: 'view'),
        ),
        throwsA(
          isA<ExecutionerActionException>().having(
            (e) => e.code,
            'code',
            'not_actionable',
          ),
        ),
      );
    });

    test('supports suffix matching like the protocol finder', () async {
      final actions = ExecutionerActions();
      var taps = 0;
      actions.onTap('home:search-tab', onTap: () => taps++);

      await actions.dispatch(
        const PerformActionRequest(action: 'tap', elementId: 'search-tab'),
      );
      expect(taps, 1);
    });

    test('toHostUiNodes exposes role, value and redaction', () {
      final actions = ExecutionerActions()
        ..onInput(
          'password',
          role: 'textbox',
          sensitive: true,
          getValue: () => 's3cret',
          setValue: (_) {},
        )
        ..onTap('ok', label: 'OK', onTap: () {});

      final nodes = actions.toHostUiNodes();
      expect(nodes, hasLength(2));
      final password = nodes.firstWhere((n) => n.testID == 'password');
      expect(password.xecutionerRedact, isTrue);
      expect(password.accessibilityRole, 'textbox');
      expect(password.actions, contains('input'));

      final ok = nodes.firstWhere((n) => n.testID == 'ok');
      expect(ok.accessibilityLabel, 'OK');
      expect(ok.actions, contains('tap'));
    });
  });

  group('XecutionerPolicy', () {
    test('matches glob patterns', () {
      expect(xecutionerPatternMatches('btn-*', 'btn-submit'), isTrue);
      expect(xecutionerPatternMatches('btn-?', 'btn-a'), isTrue);
      expect(xecutionerPatternMatches('exact', 'exact'), isTrue);
      expect(xecutionerPatternMatches('btn-*', 'other'), isFalse);
    });

    test('deny wins over approval', () {
      const policy = XecutionerPolicy(
        approvalElementPatterns: ['pay-*'],
        denyElementPatterns: ['pay-delete*'],
      );
      expect(
        policy.checkElement('pay-delete-card'),
        XecutionerPolicyDecision.deny,
      );
      expect(
        policy.checkElement('pay-confirm'),
        XecutionerPolicyDecision.approval,
      );
      expect(
        policy.checkElement('other'),
        XecutionerPolicyDecision.allow,
      );
    });
  });

  group('XecutionerCommands', () {
    test('builders produce valid protocol commands', () {
      final commands = [
        XecutionerCommands.tap('a'),
        XecutionerCommands.input('b', 'text'),
        XecutionerCommands.scroll('c', direction: 'down', amount: 100),
        XecutionerCommands.navigate('/home', params: {'x': 1}),
        XecutionerCommands.back(),
        XecutionerCommands.readScreen(),
        XecutionerCommands.getContext(),
        XecutionerCommands.waitFor(elementId: 'd', timeoutMs: 500),
      ];
      for (final command in commands) {
        final result = validateCommand(command.toJson());
        expect(result.ok, isTrue, reason: command.action);
      }
    });
  });

  group('Xecutioner facade (local mode)', () {
    test('executes tap/input/read through the real executor', () async {
      final x = await Xecutioner.init(
        const XecutionerConfig(connectOnInit: false),
      );
      addTearDown(x.dispose);

      var taps = 0;
      String? value;
      x.actions
        ..onTap('btn', label: 'Go', onTap: () => taps++)
        ..onInput(
          'field',
          getValue: () => value,
          setValue: (text) => value = text,
        );

      final tapResult = await x.tap('btn');
      expect(tapResult.ok, isTrue);
      expect(taps, 1);

      final inputResult = await x.input('field', 'abc');
      expect(inputResult.ok, isTrue);
      expect(value, 'abc');

      final readResult = await x.readScreen();
      expect(readResult.ok, isTrue);
      final ids = readResult.snapshot!.elements
          .expand((e) => [e.id, ...?e.children?.map((c) => c.id)])
          .toList();
      expect(ids, contains('btn'));
      expect(ids, contains('field'));
    });

    test('policy deny blocks element actions', () async {
      final x = await Xecutioner.init(
        const XecutionerConfig(
          connectOnInit: false,
          policy: XecutionerPolicy(
            denyElementPatterns: ['secret-*'],
          ),
        ),
      );
      addTearDown(x.dispose);

      var taps = 0;
      x.actions.onTap('secret-btn', onTap: () => taps++);

      final result = await x.tap('secret-btn');
      expect(result.ok, isFalse);
      expect(result.errorCode, 'blocked_by_policy');
      expect(taps, 0);
    });

    test('policy approval delegates to the approval hook', () async {
      var asked = 0;
      final x = await Xecutioner.init(
        XecutionerConfig(
          connectOnInit: false,
          policy: const XecutionerPolicy(
            approvalElementPatterns: ['pay-*'],
          ),
          onApprovalRequest: (_) async {
            asked++;
            return false;
          },
        ),
      );
      addTearDown(x.dispose);

      var taps = 0;
      x.actions.onTap('pay-now', onTap: () => taps++);

      final result = await x.tap('pay-now');
      expect(result.ok, isFalse);
      expect(result.errorCode, 'blocked_by_policy');
      expect(asked, greaterThan(0));
      expect(taps, 0);
    });

    test('navigates through a supplied adapter and rejects unknown screens',
        () async {
      String? current = '/home';
      final navigated = <String>[];
      final x = await Xecutioner.init(
        XecutionerConfig(
          connectOnInit: false,
          navigation: NavigationAdapter(
            getState: () => RuntimeNavState(
              screenId: current ?? 'unknown',
              stack: [current ?? 'unknown'],
            ),
            getKnownRoutes: () => const ['/home', '/search'],
            navigate: (screenId, [params]) async {
              navigated.add(screenId);
              current = screenId;
            },
            back: () async => current = '/home',
          ),
          screens: const [
            ScreenDefinition(
              id: '/search',
              title: 'Search',
              description: 'Search screen',
            ),
          ],
        ),
      );
      addTearDown(x.dispose);

      final ok = await x.navigate('/search');
      expect(ok.ok, isTrue);
      expect(navigated, ['/search']);

      final bad = await x.navigate('/nope');
      expect(bad.ok, isFalse);
      expect(bad.errorCode, 'unknown_screen');

      final context = await x.getContext();
      expect(context.ok, isTrue);
      expect(
        context.appContext!.destinations.map((d) => d.id),
        containsAll(['/home', '/search']),
      );
    });

    test('screen policy patterns mark declared screens', () async {
      var navigated = 0;
      final x = await Xecutioner.init(
        XecutionerConfig(
          connectOnInit: false,
          policy: const XecutionerPolicy(
            denyScreens: ['/admin*'],
          ),
          navigation: NavigationAdapter(
            getState: () =>
                const RuntimeNavState(screenId: '/home', stack: ['/home']),
            getKnownRoutes: () => const ['/home', '/admin'],
            navigate: (screenId, [params]) async => navigated++,
            back: () async {},
          ),
          screens: const [
            ScreenDefinition(
              id: '/admin',
              title: 'Admin',
              description: 'Admin screen',
            ),
          ],
        ),
      );
      addTearDown(x.dispose);

      final result = await x.navigate('/admin');
      expect(result.ok, isFalse);
      expect(result.errorCode, 'blocked_by_policy');
      expect(navigated, 0);
    });
  });

  group('createGetXAdapter', () {
    test('reports state and waits for route changes', () async {
      var route = '/home';
      final calls = <String>[];
      final adapter = createGetXAdapter(
        CreateGetXAdapterOptions(
          currentRoute: () => route,
          toNamed: (r, {arguments}) async {
            calls.add(r);
            route = r;
            return null;
          },
          back: () => route = '/home',
          knownRoutes: () => const ['/home', '/search'],
        ),
      );

      final state = adapter.getState();
      expect(state!.screenId, '/home');

      await adapter.navigate('/search');
      expect(calls, ['/search']);
      expect(adapter.getState()!.screenId, '/search');
      expect(adapter.getKnownRoutes!(), contains('/home'));
    });
  });

  group('UiClient auto-reconnect', () {
    test('reconnects automatically after unexpected channel close', () async {
      var connectionAttempts = 0;
      final statusChanges = <bool>[];
      StreamController<String>? currentServerStream;

      final client = createUiClient(
        UiClientOptions(
          url: 'ws://fake',
          sessionId: 'test-session',
          hooks: HostHooks(getRootNode: () => null),
          autoReconnect: true,
          initialReconnectDelay: const Duration(milliseconds: 20),
          maxReconnectDelay: const Duration(milliseconds: 50),
          onConnectionStatusChanged: statusChanges.add,
          channelFactory: (uri, {protocols}) {
            connectionAttempts++;
            final serverStream = StreamController<String>.broadcast();
            currentServerStream = serverStream;
            Future.microtask(() {
              serverStream.add('{"type":"handshake"}');
            });
            return _FakeWebSocketChannel(
              serverStream.stream,
              StreamController<dynamic>(),
            );
          },
        ),
      );

      await client.connect();
      expect(client.isConnected(), isTrue);
      expect(connectionAttempts, 1);
      expect(statusChanges, [true]);

      // Simulate unexpected server disconnect
      await currentServerStream?.close();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(client.isConnected(), isFalse);
      expect(statusChanges, [true, false]);

      // Wait for backoff reconnect (20ms delay)
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(connectionAttempts, 2);
      expect(client.isConnected(), isTrue);
      expect(statusChanges, [true, false, true]);

      // Disconnect cleanly
      client.disconnect();
      expect(client.isConnected(), isFalse);
    });

    test('reconnectNow triggers immediate reconnection', () async {
      var connectionAttempts = 0;
      StreamController<String>? currentServerStream;

      final client = createUiClient(
        UiClientOptions(
          url: 'ws://fake',
          sessionId: 'test-session',
          hooks: HostHooks(getRootNode: () => null),
          autoReconnect: true,
          initialReconnectDelay: const Duration(seconds: 100),
          channelFactory: (uri, {protocols}) {
            connectionAttempts++;
            final serverStream = StreamController<String>.broadcast();
            currentServerStream = serverStream;
            Future.microtask(() {
              serverStream.add('{"type":"handshake"}');
            });
            return _FakeWebSocketChannel(
              serverStream.stream,
              StreamController<dynamic>(),
            );
          },
        ),
      );

      await client.connect();
      expect(connectionAttempts, 1);

      await currentServerStream?.close();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(client.isConnected(), isFalse);

      await client.reconnectNow();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(connectionAttempts, 2);
      expect(client.isConnected(), isTrue);

      client.disconnect();
    });
  });
}
