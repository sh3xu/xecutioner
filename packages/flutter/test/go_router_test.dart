import 'package:test/test.dart';
import 'package:xecutioner_flutter/xecutioner_flutter.dart';

void main() {
  group('parseGoRouterState', () {
    test('reads the leaf route, stack, params, and tabs', () {
      final router = SimpleGoRouter(
        location: '/orders/order_detail',
        stack: const ['orders', 'order_detail'],
        tabs: const ['orders', 'profile'],
        params: const {'orderId': '1001'},
        knownRoutes: const ['orders', 'order_detail', 'profile'],
      );
      final parsed = parseGoRouterState(router);
      expect(parsed?.screenId, 'order_detail');
      expect(parsed?.params, {'orderId': '1001'});
      expect(parsed?.stack, ['orders', 'order_detail']);
      expect(parsed?.tabs, ['orders', 'profile']);
    });
  });

  group('collectGoRouterRouteNames', () {
    test('merges static and router routes', () {
      final router = SimpleGoRouter(
        location: '/orders',
        knownRoutes: const ['orders', 'profile'],
      );
      final names = collectGoRouterRouteNames(
        router,
        staticRoutes: const ['checkout'],
      )..sort();
      expect(names, ['checkout', 'orders', 'profile']);
    });
  });

  group('createGoRouterAdapter', () {
    test('navigates and goes back through the router', () async {
      final calls = <String>[];
      final router = SimpleGoRouter(
        location: '/orders/order_detail',
        stack: const ['orders', 'order_detail'],
        knownRoutes: const ['orders', 'order_detail', 'checkout'],
        onGo: (location, extra) {
          calls.add('nav:$location:${extra ?? {}}');
        },
        onPop: () => calls.add('back'),
      );

      final adapter = createGoRouterAdapter(
        CreateGoRouterAdapterOptions(getRouter: () => router),
      );

      expect(adapter.getState()?.screenId, 'order_detail');
      await adapter.navigate('checkout', {'cartId': 'c1'});
      await adapter.back();
      expect(calls.length, 2);
      expect(calls[0].startsWith('nav:/checkout?cartId=c1:'), isTrue);
      expect(calls[1], 'back');
    });
  });
}
