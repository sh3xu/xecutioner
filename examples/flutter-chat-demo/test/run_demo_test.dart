import 'package:test/test.dart';
import 'package:xecutioner_flutter/xecutioner_flutter.dart';
import 'package:xecutioner_flutter_chat_demo/host_app.dart';

void main() {
  test('scripted host path reaches checkout with email', () async {
    final host = createDemoHost();
    final contextReader = createAppContextReader(
      CreateAppContextReaderOptions(
        app: const AppInfo(name: 'Shop', description: 'Demo'),
        navigation: host.createNavigationAdapter(),
        screens: const [
          ScreenDefinition(
            id: 'orders',
            title: 'Orders',
            description: 'Orders list',
          ),
          ScreenDefinition(
            id: 'order_detail',
            title: 'Order detail',
            description: 'Detail',
          ),
          ScreenDefinition(
            id: 'checkout',
            title: 'Checkout',
            description: 'Checkout',
          ),
        ],
      ),
    );

    final client = createUiClient(
      UiClientOptions(
        url: 'ws://127.0.0.1:9/xecutioner',
        sessionId: 'test',
        hooks: HostHooks(
          getRootNode: host.getRoot,
          performAction: createDemoPerformAction(host),
          contextReader: contextReader,
        ),
      ),
    );

    final deadline = DateTime.now().millisecondsSinceEpoch + 15000;
    final nav = await client.executeLocal(
      Command(
        callId: '1',
        action: 'navigate',
        screenId: 'checkout',
        idempotencyKey: 'a',
        deadline: deadline,
      ),
    );
    expect(nav.ok, isTrue);

    final read = await client.executeLocal(
      Command(
        callId: '2',
        action: 'read_screen',
        idempotencyKey: 'b',
        deadline: deadline,
      ),
    );
    expect(read.ok, isTrue);

    final input = await client.executeLocal(
      Command(
        callId: '3',
        action: 'input',
        elementId: 'email-input',
        text: 'buyer@example.com',
        snapshotId: client.getLastSnapshot()?.snapshotId,
        idempotencyKey: 'c',
        deadline: deadline,
      ),
    );
    expect(input.ok, isTrue);
    expect(host.getEmail(), 'buyer@example.com');
    expect(host.getScreenId(), 'checkout');
  });
}
