import {
  type AppContext,
  DEFAULT_CONTEXT_DESTINATION_LIMIT,
  mergeDestinations,
  type ScreenDestination,
  trimAppContext,
} from "@xecutioner/protocol";
import type {
  AppContextReader,
  AppInfo,
  NavigationAdapter,
  RuntimeNavState,
  ScreenDefinition,
} from "./types.js";

export type CreateAppContextReaderOptions = {
  app: AppInfo;
  navigation?: NavigationAdapter;
  screens?: ScreenDefinition[];
};

function toDeclaredDestinations(screens: ScreenDefinition[]): ScreenDestination[] {
  return screens.map((screen) => ({
    id: screen.id,
    title: screen.title,
    description: screen.description,
    params: screen.params,
    reachableFrom: screen.reachableFrom,
    requiresAuth: screen.requiresAuth,
    policy: screen.policy,
    source: "declared" as const,
  }));
}

function toAutoDestinations(routeNames: string[]): ScreenDestination[] {
  return routeNames.map((id) => ({
    id,
    title: id,
    description: `Route "${id}" (auto-extracted; no developer description yet)`,
    source: "auto" as const,
  }));
}

function toRuntimeDestinations(state: RuntimeNavState): ScreenDestination[] {
  const ids = new Set<string>([state.screenId, ...state.stack, ...(state.tabs ?? [])]);
  return [...ids].filter(Boolean).map((id) => ({
    id,
    title: id,
    description: `Observed at runtime (${id})`,
    source: "runtime" as const,
  }));
}

/**
 * Client-side context reader: combines runtime nav state, declared screen map,
 * and auto-extracted routes into a single AppContext.
 */
export function createAppContextReader(options: CreateAppContextReaderOptions): AppContextReader {
  let declared: ScreenDefinition[] = options.screens ? [...options.screens] : [];
  const navigation = options.navigation;

  function buildDestinations(maxDestinations?: number): ScreenDestination[] {
    const state = navigation?.getState() ?? null;
    const autoRoutes = navigation?.getKnownRoutes?.() ?? [];
    return mergeDestinations(
      {
        declared: toDeclaredDestinations(declared),
        auto: toAutoDestinations(autoRoutes),
        runtime: state ? toRuntimeDestinations(state) : undefined,
      },
      { maxDestinations },
    );
  }

  return {
    getNavigation: () => navigation,

    getScreens: () => [...declared],

    defineScreens: (screens) => {
      declared = [...screens];
    },

    toDestinations: () => buildDestinations(),

    read: (readOptions) => {
      const state = navigation?.getState() ?? null;
      const maxDestinations = readOptions?.maxDestinations ?? DEFAULT_CONTEXT_DESTINATION_LIMIT;

      const context: AppContext = {
        app: options.app,
        current: {
          screenId: state?.screenId ?? "unknown",
          params: state?.params,
          stack: state?.stack ?? [],
          tabs: state?.tabs,
        },
        destinations: buildDestinations(),
      };

      return trimAppContext(context, {
        maxDestinations,
        preferRelatedToCurrent: true,
      });
    },
  };
}
