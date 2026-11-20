import 'package:xecutioner_flutter/xecutioner_flutter.dart';

enum DemoScreen { list, detail, checkout }

const screenIds = <DemoScreen, String>{
  DemoScreen.list: 'orders',
  DemoScreen.detail: 'order_detail',
  DemoScreen.checkout: 'checkout',
};

class DemoHost {
  DemoHost({
    required this.getRoot,
    required this.getScreen,
    required this.getScreenId,
    required this.navigate,
    required this.navigateById,
    required this.back,
    required this.setEmail,
    required this.getEmail,
    required this.getNavState,
    required this.createNavigationAdapter,
  });

  final HostUiNode Function() getRoot;
  final DemoScreen Function() getScreen;
  final String Function() getScreenId;
  final void Function(DemoScreen screen) navigate;
  final void Function(String screenId, [Map<String, dynamic>? params])
      navigateById;
  final void Function() back;
  final void Function(String email) setEmail;
  final String Function() getEmail;
  final RuntimeNavState Function() getNavState;
  final NavigationAdapter Function() createNavigationAdapter;
}

/// Minimal multi-screen host tree used by the demo (simulates Flutter screens).
DemoHost createDemoHost() {
  var screen = DemoScreen.list;
  var email = '';
  var stack = <DemoScreen>[DemoScreen.list];
  String? orderId;

  HostUiNode listTree() => HostUiNode(
        testID: 'screen-list',
        accessibilityRole: 'summary',
        accessibilityLabel: 'Orders',
        children: [
          HostUiNode(
            testID: 'order-1',
            accessibilityRole: 'button',
            accessibilityLabel: 'Order 1001 — Blue sneakers',
          ),
          HostUiNode(
            testID: 'order-2',
            accessibilityRole: 'button',
            accessibilityLabel: 'Order 1002 — Red jacket',
          ),
        ],
      );

  HostUiNode detailTree() => HostUiNode(
        testID: 'screen-detail',
        accessibilityRole: 'summary',
        accessibilityLabel: 'Order 1001',
        children: [
          HostUiNode(
            testID: 'order-title',
            accessibilityRole: 'header',
            accessibilityLabel: 'Blue sneakers',
          ),
          HostUiNode(
            testID: 'buy-button',
            accessibilityRole: 'button',
            accessibilityLabel: 'Buy now',
          ),
          HostUiNode(
            testID: 'back-button',
            accessibilityRole: 'button',
            accessibilityLabel: 'Back to list',
          ),
        ],
      );

  HostUiNode checkoutTree() => HostUiNode(
        testID: 'screen-checkout',
        accessibilityRole: 'summary',
        accessibilityLabel: 'Checkout',
        children: [
          HostUiNode(
            testID: 'email-input',
            accessibilityRole: 'textbox',
            accessibilityLabel: 'Email',
            props: {'value': email},
            accessibilityValue: AccessibilityValue(text: email),
          ),
          HostUiNode(
            testID: 'submit-order',
            accessibilityRole: 'button',
            accessibilityLabel: 'Submit order',
          ),
        ],
      );

  late final DemoHost host;
  host = DemoHost(
    getScreen: () => screen,
    getScreenId: () => screenIds[screen]!,
    getEmail: () => email,
    setEmail: (value) => email = value,
    navigate: (next) {
      screen = next;
      stack = [...stack, next];
    },
    navigateById: (screenId, [params]) {
      if (screenId == 'orders') {
        screen = DemoScreen.list;
        stack = [DemoScreen.list];
        orderId = null;
        return;
      }
      if (screenId == 'order_detail') {
        screen = DemoScreen.detail;
        stack = [DemoScreen.list, DemoScreen.detail];
        orderId = params?['orderId'] is String ? params!['orderId'] as String : '1001';
        return;
      }
      if (screenId == 'checkout') {
        screen = DemoScreen.checkout;
        stack = [DemoScreen.list, DemoScreen.detail, DemoScreen.checkout];
      }
    },
    back: () {
      if (stack.length <= 1) return;
      stack = stack.sublist(0, stack.length - 1);
      screen = stack.last;
    },
    getNavState: () => RuntimeNavState(
      screenId: screenIds[screen]!,
      stack: stack.map((s) => screenIds[s]!).toList(),
      params: orderId != null ? {'orderId': orderId} : null,
      tabs: const ['orders', 'profile'],
    ),
    createNavigationAdapter: () => NavigationAdapter(
      getState: () => host.getNavState(),
      getKnownRoutes: () =>
          const ['orders', 'order_detail', 'checkout', 'profile'],
      navigate: (screenId, [params]) async {
        host.navigateById(screenId, params);
      },
      back: () async {
        host.back();
      },
    ),
    getRoot: () {
      if (screen == DemoScreen.detail) return detailTree();
      if (screen == DemoScreen.checkout) return checkoutTree();
      return listTree();
    },
  );

  return host;
}

/// Wire performAction navigation for the demo host.
PerformAction createDemoPerformAction(DemoHost host) {
  return (request) async {
    if (request.action == 'tap') {
      if (request.elementId == 'order-1') host.navigate(DemoScreen.detail);
      if (request.elementId == 'buy-button') host.navigate(DemoScreen.checkout);
      if (request.elementId == 'back-button') host.navigate(DemoScreen.list);
    }
    if (request.action == 'input' && request.elementId == 'email-input') {
      host.setEmail(request.text ?? '');
    }
  };
}
