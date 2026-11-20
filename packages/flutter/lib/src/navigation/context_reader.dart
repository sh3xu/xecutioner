import '../protocol/constants.dart';
import '../protocol/helpers.dart';
import '../protocol/types.dart';
import 'types.dart';

class CreateAppContextReaderOptions {
  const CreateAppContextReaderOptions({
    required this.app,
    this.navigation,
    this.screens,
  });

  final AppInfo app;
  final NavigationAdapter? navigation;
  final List<ScreenDefinition>? screens;
}

List<ScreenDestination> _toDeclaredDestinations(List<ScreenDefinition> screens) {
  return screens
      .map(
        (screen) => ScreenDestination(
          id: screen.id,
          title: screen.title,
          description: screen.description,
          params: screen.params,
          reachableFrom: screen.reachableFrom,
          requiresAuth: screen.requiresAuth,
          policy: screen.policy,
          source: 'declared',
        ),
      )
      .toList();
}

List<ScreenDestination> _toAutoDestinations(List<String> routeNames) {
  return routeNames
      .map(
        (id) => ScreenDestination(
          id: id,
          title: id,
          description:
              'Route "$id" (auto-extracted; no developer description yet)',
          source: 'auto',
        ),
      )
      .toList();
}

List<ScreenDestination> _toRuntimeDestinations(RuntimeNavState state) {
  final ids = <String>{state.screenId, ...state.stack, ...?state.tabs};
  return ids
      .where((id) => id.isNotEmpty)
      .map(
        (id) => ScreenDestination(
          id: id,
          title: id,
          description: 'Observed at runtime ($id)',
          source: 'runtime',
        ),
      )
      .toList();
}

class _AppContextReaderImpl implements AppContextReader {
  _AppContextReaderImpl(this._options)
      : _declared = List<ScreenDefinition>.from(_options.screens ?? const []);

  final CreateAppContextReaderOptions _options;
  List<ScreenDefinition> _declared;

  List<ScreenDestination> _buildDestinations({num? maxDestinations}) {
    final state = _options.navigation?.getState.call();
    final autoRoutes =
        _options.navigation?.getKnownRoutes?.call() ?? const <String>[];
    return mergeDestinations(
      declared: _toDeclaredDestinations(_declared),
      auto: _toAutoDestinations(autoRoutes),
      runtime: state != null ? _toRuntimeDestinations(state) : null,
      maxDestinations: maxDestinations,
    );
  }

  @override
  NavigationAdapter? getNavigation() => _options.navigation;

  @override
  List<ScreenDefinition> getScreens() => List.unmodifiable(_declared);

  @override
  void defineScreens(List<ScreenDefinition> screens) {
    _declared = List.from(screens);
  }

  @override
  List<ScreenDestination> toDestinations() => _buildDestinations();

  @override
  AppContext read({num? maxDestinations}) {
    final state = _options.navigation?.getState.call();
    final limit = maxDestinations ?? defaultContextDestinationLimit;

    final context = AppContext(
      app: _options.app,
      current: AppCurrent(
        screenId: state?.screenId ?? 'unknown',
        params: state?.params,
        stack: state?.stack ?? const [],
        tabs: state?.tabs,
      ),
      destinations: _buildDestinations(),
    );

    return trimAppContext(
      context,
      options: TrimAppContextOptions(
        maxDestinations: limit,
        preferRelatedToCurrent: true,
      ),
    );
  }
}

/// Client-side context reader: combines runtime nav state, declared screen map,
/// and auto-extracted routes into a single AppContext.
AppContextReader createAppContextReader(CreateAppContextReaderOptions options) {
  return _AppContextReaderImpl(options);
}
