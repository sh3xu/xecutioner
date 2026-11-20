import '../protocol/types.dart';

export '../protocol/types.dart' show AppInfo;

/// Live navigation observation from a framework adapter.
class RuntimeNavState {
  const RuntimeNavState({
    required this.screenId,
    required this.stack,
    this.params,
    this.tabs,
  });

  final String screenId;
  final Map<String, dynamic>? params;
  final List<String> stack;
  final List<String>? tabs;
}

/// Framework-specific navigation bridge. go_router / Navigator /
/// custom routers each supply these callbacks.
class NavigationAdapter {
  NavigationAdapter({
    required this.getState,
    required this.navigate,
    required this.back,
    this.getKnownRoutes,
    this.reset,
  });

  final RuntimeNavState? Function() getState;

  /// Auto-extracted route names when the host can list them.
  final List<String> Function()? getKnownRoutes;

  final Future<void> Function(String screenId, [Map<String, dynamic>? params])
      navigate;

  final Future<void> Function() back;

  final Future<void> Function(String screenId, [Map<String, dynamic>? params])?
      reset;
}

/// Developer-declared screen map entry.
class ScreenDefinition {
  const ScreenDefinition({
    required this.id,
    required this.title,
    required this.description,
    this.params,
    this.reachableFrom,
    this.requiresAuth,
    this.policy,
  });

  final String id;
  final String title;
  final String description;
  final Map<String, dynamic>? params;
  final List<String>? reachableFrom;
  final bool? requiresAuth;
  final String? policy;
}

abstract class AppContextReader {
  AppContext read({num? maxDestinations});

  void defineScreens(List<ScreenDefinition> screens);

  List<ScreenDefinition> getScreens();

  NavigationAdapter? getNavigation();

  List<ScreenDestination> toDestinations();
}
