import type { NavigationAdapter, RuntimeNavState } from "./types.js";

/**
 * Minimal React Navigation / Expo Router state shape we understand.
 * Avoids a hard dependency on @react-navigation/* packages.
 */
export type ReactNavigationStateLike = {
  index?: number;
  routeNames?: string[];
  routes?: Array<{
    name: string;
    params?: Record<string, unknown>;
    state?: ReactNavigationStateLike;
  }>;
  type?: string;
  stale?: boolean;
};

export type ReactNavigationRefLike = {
  getRootState?: () => ReactNavigationStateLike | undefined;
  getState?: () => ReactNavigationStateLike | undefined;
  navigate?: (name: string, params?: Record<string, unknown>) => void;
  goBack?: () => void;
  canGoBack?: () => boolean;
  reset?: (state: unknown) => void;
  getCurrentRoute?: () => { name?: string; params?: Record<string, unknown> } | undefined;
};

function leafRoute(
  state: ReactNavigationStateLike | undefined,
  stack: string[] = [],
): { screenId: string; params?: Record<string, unknown>; stack: string[] } | null {
  if (!state?.routes?.length) {
    return null;
  }
  const index = state.index ?? state.routes.length - 1;
  const route = state.routes[index];
  if (!route) {
    return null;
  }
  const nextStack = [...stack, route.name];
  if (route.state) {
    return leafRoute(route.state, nextStack);
  }
  return {
    screenId: route.name,
    params: route.params,
    stack: nextStack,
  };
}

/**
 * Collect tab names when a tab navigator is present in the tree.
 */
export function extractTabNames(state: ReactNavigationStateLike | undefined): string[] {
  if (!state) return [];
  if (state.type === "tab" || state.type === "material" || state.type === "drawer") {
    return state.routeNames ?? state.routes?.map((r) => r.name) ?? [];
  }
  const index = state.index ?? 0;
  const child = state.routes?.[index]?.state;
  return extractTabNames(child);
}

/**
 * Parse a React Navigation root state into RuntimeNavState.
 */
export function parseReactNavigationState(
  state: ReactNavigationStateLike | undefined,
): RuntimeNavState | null {
  const leaf = leafRoute(state);
  if (!leaf) {
    return null;
  }
  return {
    screenId: leaf.screenId,
    params: leaf.params,
    stack: leaf.stack,
    tabs: extractTabNames(state),
  };
}

/**
 * Collect all route names reachable in a navigation state tree.
 */
export function collectRouteNames(
  state: ReactNavigationStateLike | undefined,
  out = new Set<string>(),
): string[] {
  if (!state) return [...out];
  for (const name of state.routeNames ?? []) {
    out.add(name);
  }
  for (const route of state.routes ?? []) {
    out.add(route.name);
    if (route.state) {
      collectRouteNames(route.state, out);
    }
  }
  return [...out];
}

export type CreateReactNavigationAdapterOptions = {
  /**
   * Return the navigation ref (or an object with getRootState / navigate / goBack).
   * Called on each read/navigate so the ref can be attached after mount.
   */
  getRef: () => ReactNavigationRefLike | null | undefined;
  /** Optional static route list when state is not yet mounted. */
  knownRoutes?: string[];
  /** Optional deep-link fallback when navigate by name is unavailable. */
  openUrl?: (url: string) => void | Promise<void>;
  buildDeepLink?: (screenId: string, params?: Record<string, unknown>) => string | null;
};

/**
 * Navigation adapter for React Navigation and Expo Router refs.
 */
export function createReactNavigationAdapter(
  options: CreateReactNavigationAdapterOptions,
): NavigationAdapter {
  function readState(): ReactNavigationStateLike | undefined {
    const ref = options.getRef();
    return ref?.getRootState?.() ?? ref?.getState?.();
  }

  return {
    getState: () => parseReactNavigationState(readState()),

    getKnownRoutes: () => {
      const fromState = collectRouteNames(readState());
      const staticRoutes = options.knownRoutes ?? [];
      return [...new Set([...staticRoutes, ...fromState])];
    },

    navigate: async (screenId, params) => {
      const ref = options.getRef();
      if (ref?.navigate) {
        ref.navigate(screenId, params);
        return;
      }
      const url = options.buildDeepLink?.(screenId, params) ?? null;
      if (url && options.openUrl) {
        await options.openUrl(url);
        return;
      }
      throw new Error("navigation_unavailable: no navigate handler on navigation ref");
    },

    back: async () => {
      const ref = options.getRef();
      if (!ref?.goBack) {
        throw new Error("navigation_unavailable: no goBack handler on navigation ref");
      }
      if (ref.canGoBack && !ref.canGoBack()) {
        throw new Error("navigation_unavailable: cannot go back");
      }
      ref.goBack();
    },
  };
}
