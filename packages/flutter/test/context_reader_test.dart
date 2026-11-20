import 'package:test/test.dart';
import 'package:xecutioner_flutter/xecutioner_flutter.dart';

NavigationAdapter mockNav({
  RuntimeNavState? Function()? getState,
  List<String> Function()? getKnownRoutes,
}) {
  return NavigationAdapter(
    getState: getState ??
        () => const RuntimeNavState(
              screenId: 'orders',
              stack: ['tabs', 'orders'],
              tabs: ['orders', 'profile'],
              params: {'filter': 'open'},
            ),
    getKnownRoutes: getKnownRoutes ??
        () => const ['orders', 'order_detail', 'profile', 'login'],
    navigate: (_, [__]) async {},
    back: () async {},
  );
}

void main() {
  group('createAppContextReader', () {
    test('merges runtime, auto, and declared destinations with declared winning',
        () {
      final reader = createAppContextReader(
        CreateAppContextReaderOptions(
          app: const AppInfo(name: 'Shop', description: 'Demo shop app'),
          navigation: mockNav(),
          screens: const [
            ScreenDefinition(
              id: 'order_detail',
              title: 'Order detail',
              description: 'One order: items, status, tracking',
              params: {'orderId': 'string'},
            ),
          ],
        ),
      );

      final ctx = reader.read();
      expect(ctx.app.name, 'Shop');
      expect(ctx.current.screenId, 'orders');
      expect(ctx.current.stack, ['tabs', 'orders']);
      expect(ctx.current.params, {'filter': 'open'});

      final detail =
          ctx.destinations.where((d) => d.id == 'order_detail').first;
      expect(detail.source, 'declared');
      expect(detail.description.contains('One order'), isTrue);

      final orders = ctx.destinations.where((d) => d.id == 'orders');
      expect(orders, isNotEmpty);
    });

    test('defineScreens updates the declared map', () {
      final reader = createAppContextReader(
        CreateAppContextReaderOptions(
          app: const AppInfo(name: 'Shop', description: 'Demo'),
          navigation: mockNav(getKnownRoutes: () => const []),
        ),
      );
      reader.defineScreens(const [
        ScreenDefinition(
          id: 'checkout',
          title: 'Checkout',
          description: 'Pay for the cart',
        ),
      ]);
      expect(
        reader.read().destinations.any((d) => d.id == 'checkout'),
        isTrue,
      );
    });

    test('returns unknown current when no navigation adapter is present', () {
      final reader = createAppContextReader(
        const CreateAppContextReaderOptions(
          app: AppInfo(name: 'Shop', description: 'Demo'),
          screens: [
            ScreenDefinition(
              id: 'home',
              title: 'Home',
              description: 'Home screen',
            ),
          ],
        ),
      );
      final ctx = reader.read();
      expect(ctx.current.screenId, 'unknown');
      expect(ctx.destinations[0].id, 'home');
    });
  });
}
