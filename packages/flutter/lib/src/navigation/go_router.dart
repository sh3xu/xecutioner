import 'types.dart';

/// Minimal go_router-like surface we understand.
/// Avoids a hard dependency on the go_router package (mirrors RN's ref-like API).
abstract class GoRouterLike {
  /// Current matched location, e.g. `/orders/1001`.
  String get location;

  /// Named routes known to the router configuration, when available.
  List<String> get knownRoutes => const [];

  /// Stack of route names / path segments for context.
  List<String> get stack => const [];

  /// Optional tab / shell branch names.
  List<String> get tabs => const [];

  /// Path / query params for the current leaf route.
  Map<String, dynamic>? get params => null;

  void go(String location, {Object? extra});

  void pop();

  bool canPop();
}

/// Concrete host stub for tests / demos that duck-types go_router.
class SimpleGoRouter implements GoRouterLike {
  SimpleGoRouter({
    required this.location,
    this.knownRoutes = const [],
    this.stack = const [],
    this.tabs = const [],
    this.params,
    this.onGo,
    this.onPop,
    this.canPopValue = true,
  });

  @override
  String location;

  @override
  List<String> knownRoutes;

  @override
  List<String> stack;

  @override
  List<String> tabs;

  @override
  Map<String, dynamic>? params;

  final void Function(String location, Object? extra)? onGo;
  final void Function()? onPop;
  final bool canPopValue;

  @override
  void go(String location, {Object? extra}) {
    this.location = location;
    onGo?.call(location, extra);
  }

  @override
  void pop() => onPop?.call();

  @override
  bool canPop() => canPopValue;
}

class CreateGoRouterAdapterOptions {
  const CreateGoRouterAdapterOptions({
    required this.getRouter,
    this.knownRoutes,
    this.openUrl,
    this.buildDeepLink,
    this.screenIdToLocation,
  });

  /// Return the router (or duck-typed go_router). Called on each read/navigate
  /// so the instance can be attached after MaterialApp.router mounts.
  final GoRouterLike? Function() getRouter;

  /// Optional static route list when the router is not yet mounted.
  final List<String>? knownRoutes;

  final Future<void> Function(String url)? openUrl;

  final String? Function(String screenId, Map<String, dynamic>? params)?
      buildDeepLink;

  /// Map a protocol screenId to a go_router location. Defaults to `/$screenId`.
  final String Function(String screenId, Map<String, dynamic>? params)?
      screenIdToLocation;
}

String _defaultLocation(String screenId, Map<String, dynamic>? params) {
  if (params == null || params.isEmpty) {
    return '/$screenId';
  }
  final query = params.entries
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent('${e.value}')}',
      )
      .join('&');
  return '/$screenId?$query';
}

String _screenIdFromLocation(String location) {
  final uri = Uri.parse(location.startsWith('/') ? location : '/$location');
  if (uri.pathSegments.isEmpty) {
    return 'unknown';
  }
  return uri.pathSegments.last;
}

List<String> _stackFromLocation(String location) {
  final uri = Uri.parse(location.startsWith('/') ? location : '/$location');
  return uri.pathSegments.where((s) => s.isNotEmpty).toList();
}

RuntimeNavState? parseGoRouterState(GoRouterLike? router) {
  if (router == null) return null;
  final location = router.location;
  if (location.isEmpty) return null;
  final stack =
      router.stack.isNotEmpty ? router.stack : _stackFromLocation(location);
  return RuntimeNavState(
    screenId: _screenIdFromLocation(location),
    params: router.params,
    stack: stack.isNotEmpty ? stack : [_screenIdFromLocation(location)],
    tabs: router.tabs.isNotEmpty ? router.tabs : null,
  );
}

List<String> collectGoRouterRouteNames(
  GoRouterLike? router, {
  List<String> staticRoutes = const [],
}) {
  final fromRouter = router?.knownRoutes ?? const [];
  return {...staticRoutes, ...fromRouter}.toList();
}

/// Navigation adapter for go_router (and duck-typed routers with the same API).
NavigationAdapter createGoRouterAdapter(CreateGoRouterAdapterOptions options) {
  GoRouterLike? router() => options.getRouter();

  return NavigationAdapter(
    getState: () => parseGoRouterState(router()),
    getKnownRoutes: () => collectGoRouterRouteNames(
      router(),
      staticRoutes: options.knownRoutes ?? const [],
    ),
    navigate: (screenId, [params]) async {
      final r = router();
      if (r != null) {
        final toLocation = options.screenIdToLocation ?? _defaultLocation;
        r.go(toLocation(screenId, params), extra: params);
        return;
      }
      final url = options.buildDeepLink?.call(screenId, params);
      if (url != null && options.openUrl != null) {
        await options.openUrl!(url);
        return;
      }
      throw StateError(
        'navigation_unavailable: no go_router instance available',
      );
    },
    back: () async {
      final r = router();
      if (r == null) {
        throw StateError(
          'navigation_unavailable: no go_router instance available',
        );
      }
      if (!r.canPop()) {
        throw StateError('navigation_unavailable: cannot go back');
      }
      r.pop();
    },
  );
}
