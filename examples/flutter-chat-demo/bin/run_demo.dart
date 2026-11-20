import 'package:xecutioner_flutter/xecutioner_flutter.dart';
import 'package:xecutioner_flutter_chat_demo/host_app.dart';

/// Local scripted demo: exercises executors against a mock host tree.
/// NOTE: Full WS + server path remains in examples/rn-chat-demo; this demo
/// validates the Flutter client API surface without requiring Node.
Future<void> main() async {
  final host = createDemoHost();
  final contextReader = createAppContextReader(
    CreateAppContextReaderOptions(
      app: const AppInfo(
        name: 'Shop',
        description: 'Demo commerce app for Xecutioner UI control',
      ),
      navigation: host.createNavigationAdapter(),
      screens: const [
        ScreenDefinition(
          id: 'orders',
          title: 'Orders',
          description: "List of the user's past orders",
        ),
        ScreenDefinition(
          id: 'order_detail',
          title: 'Order detail',
          description: 'One order: items, status, tracking, buy button',
          params: {'orderId': 'string'},
          reachableFrom: ['orders'],
        ),
        ScreenDefinition(
          id: 'checkout',
          title: 'Checkout',
          description: 'Enter email and submit the order',
          reachableFrom: ['order_detail'],
        ),
      ],
    ),
  );

  final client = createUiClient(
    UiClientOptions(
      url: 'ws://127.0.0.1:8787/xecutioner',
      sessionId: 'flutter-demo-session',
      hooks: HostHooks(
        getRootNode: host.getRoot,
        getScreenMeta: () => ScreenMeta(screen: host.getScreenId()),
        performAction: createDemoPerformAction(host),
        contextReader: contextReader,
        onAiActing: (acting) {
          // ignore: avoid_print
          print(acting ? '[host] AI is acting' : '[host] AI idle');
        },
      ),
    ),
  );

  final deadline = DateTime.now().millisecondsSinceEpoch + 15000;
  final steps = <({String tool, bool ok})>[];

  Future<void> run(String tool, Command command) async {
    final result = await client.executeLocal(command);
    steps.add((tool: tool, ok: result.ok));
    // ignore: avoid_print
    print('- $tool: ${result.ok ? 'ok' : 'fail'} ${result.errorCode ?? ''}');
  }

  await run(
    'ui_get_context',
    Command(
      callId: 'c1',
      action: 'get_context',
      idempotencyKey: 'i1',
      deadline: deadline,
    ),
  );
  await run(
    'ui_navigate',
    Command(
      callId: 'c2',
      action: 'navigate',
      screenId: 'order_detail',
      params: {'orderId': '1001'},
      idempotencyKey: 'i2',
      deadline: deadline,
    ),
  );
  await run(
    'ui_read_screen',
    Command(
      callId: 'c3',
      action: 'read_screen',
      idempotencyKey: 'i3',
      deadline: deadline,
    ),
  );
  await run(
    'ui_navigate',
    Command(
      callId: 'c4',
      action: 'navigate',
      screenId: 'checkout',
      idempotencyKey: 'i4',
      deadline: deadline,
    ),
  );
  await run(
    'ui_read_screen',
    Command(
      callId: 'c5',
      action: 'read_screen',
      idempotencyKey: 'i5',
      deadline: deadline,
    ),
  );

  final snapId = client.getLastSnapshot()?.snapshotId;
  await run(
    'ui_input',
    Command(
      callId: 'c6',
      action: 'input',
      elementId: 'email-input',
      text: 'buyer@example.com',
      snapshotId: snapId,
      idempotencyKey: 'i6',
      deadline: deadline,
    ),
  );
  await run(
    'ui_tap',
    Command(
      callId: 'c7',
      action: 'tap',
      elementId: 'submit-order',
      snapshotId: client.getLastSnapshot()?.snapshotId,
      idempotencyKey: 'i7',
      deadline: deadline,
    ),
  );
  await run(
    'ui_get_context',
    Command(
      callId: 'c8',
      action: 'get_context',
      idempotencyKey: 'i8',
      deadline: deadline,
    ),
  );

  // ignore: avoid_print
  print('\nFinal screen: ${host.getScreenId()}');
  // ignore: avoid_print
  print('Email: ${host.getEmail()}');

  final success = steps.every((s) => s.ok) &&
      host.getScreen() == DemoScreen.checkout &&
      host.getEmail() == 'buyer@example.com';

  if (!success) {
    // ignore: avoid_print
    print('Demo task failed');
    throw StateError('flutter-chat-demo failed');
  }

  // ignore: avoid_print
  print('\nDemo task succeeded (context + navigate path).');
}
