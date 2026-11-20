import 'dart:async';

import 'package:flutter/widgets.dart';

import '../navigation/types.dart';

/// Observes the [Navigator] route stack so the SDK can report the current
/// screen and route names.
///
/// Attach once to the app's `Navigator` (or `MaterialApp.navigatorObservers`)
/// and pass it to [createNavigatorAdapter].
class ExecutionerNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _stack.remove(oldRoute);
    if (newRoute != null) _stack.add(newRoute);
  }

  /// Name of the top-most route (`RouteSettings.name`), if any.
  String? get currentRouteName {
    if (_stack.isEmpty) return null;
    return _stack.last.settings.name;
  }

  /// Route names for the whole stack, bottom to top.
  List<String> get routeNames => _stack
      .map((route) => route.settings.name ?? 'unnamed')
      .toList(growable: false);
}

class CreateNavigatorAdapterOptions {
  const CreateNavigatorAdapterOptions({
    required this.navigatorKey,
    required this.observer,
    this.knownRoutes,
    this.arguments,
    this.settleDelay = const Duration(milliseconds: 250),
  });

  /// `GlobalKey<NavigatorState>` of the app's Navigator.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Observer attached to the same Navigator.
  final ExecutionerNavigatorObserver observer;

  /// Static route names when they can't be auto-extracted.
  final List<String>? knownRoutes;

  /// Returns current route arguments, if the host tracks them.
  final Map<String, dynamic>? Function()? arguments;

  /// How long to wait after push/pop for the observer stack to settle.
  final Duration settleDelay;
}

/// [NavigationAdapter] for Flutter's imperative `Navigator` (named routes).
NavigationAdapter createNavigatorAdapter(CreateNavigatorAdapterOptions options) {
  NavigatorState? navigator() => options.navigatorKey.currentState;

  return NavigationAdapter(
    getState: () {
      final name = options.observer.currentRouteName;
      if (name == null) return null;
      return RuntimeNavState(
        screenId: name,
        params: options.arguments?.call(),
        stack: options.observer.routeNames,
      );
    },
    getKnownRoutes: options.knownRoutes == null
        ? null
        : () => options.knownRoutes!,
    navigate: (screenId, [params]) async {
      final state = navigator();
      if (state == null) {
        throw StateError(
          'navigation_unavailable: navigator is not mounted',
        );
      }
      unawaited(state.pushNamed(screenId, arguments: params));
      await Future<void>.delayed(options.settleDelay);
    },
    back: () async {
      final state = navigator();
      if (state == null) {
        throw StateError(
          'navigation_unavailable: navigator is not mounted',
        );
      }
      final didPop = await state.maybePop();
      if (!didPop) {
        throw StateError('navigation_unavailable: cannot go back');
      }
      await Future<void>.delayed(options.settleDelay);
    },
  );
}

class CreateGetXAdapterOptions {
  const CreateGetXAdapterOptions({
    required this.currentRoute,
    required this.toNamed,
    required this.back,
    this.arguments,
    this.tabs,
    this.knownRoutes,
    this.settleDelay = const Duration(milliseconds: 400),
  });

  /// e.g. `() => Get.currentRoute`
  final String Function() currentRoute;

  /// e.g. `(route, {arguments}) => Get.toNamed(route, arguments: arguments)`
  final Future<Object?> Function(String route, {Object? arguments}) toNamed;

  /// e.g. `() => Get.back()` — may be async.
  final FutureOr<void> Function() back;

  /// e.g. `() => Get.arguments is Map ? Get.arguments as Map<String, dynamic> : null`
  final Map<String, dynamic>? Function()? arguments;

  /// e.g. shell/tab identifiers for the current screen, when the app has
  /// persistent tab shells (IndexedStack, etc.).
  final List<String>? Function()? tabs;

  /// e.g. `() => AppPages.routes.map((p) => p.name ?? '').where((n) => n.isNotEmpty).toList()`
  final List<String> Function()? knownRoutes;

  /// How long to wait for `currentRoute` to reflect the navigation.
  final Duration settleDelay;
}

/// [NavigationAdapter] for GetX, supplied via closures so the package does
/// not need a hard `get` dependency.
NavigationAdapter createGetXAdapter(CreateGetXAdapterOptions options) {
  return NavigationAdapter(
    getState: () {
      final route = options.currentRoute();
      if (route.isEmpty) return null;
      return RuntimeNavState(
        screenId: route,
        params: options.arguments?.call(),
        stack: [route],
        tabs: options.tabs?.call(),
      );
    },
    getKnownRoutes: options.knownRoutes,
    navigate: (screenId, [params]) async {
      await options.toNamed(screenId, arguments: params);
      final deadline = DateTime.now().add(options.settleDelay);
      while (options.currentRoute() != screenId &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    },
    back: () async {
      await options.back();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );
}
