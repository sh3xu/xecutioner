import type { AppContext, ScreenDestination } from "@xecutioner/protocol";

/**
 * Live navigation observation from a framework adapter.
 */
export type RuntimeNavState = {
  screenId: string;
  params?: Record<string, unknown>;
  stack: string[];
  tabs?: string[];
};

/**
 * Framework-specific navigation bridge. React Navigation / Expo Router /
 * custom routers each implement this thin interface.
 */
export type NavigationAdapter = {
  getState: () => RuntimeNavState | null | undefined;
  /** Auto-extracted route names when the host can list them. */
  getKnownRoutes?: () => string[];
  navigate: (screenId: string, params?: Record<string, unknown>) => void | Promise<void>;
  back: () => void | Promise<void>;
  reset?: (screenId: string, params?: Record<string, unknown>) => void | Promise<void>;
};

/**
 * Developer-declared screen map entry (Phase 1 supports registration; policy enforced later).
 */
export type ScreenDefinition = {
  id: string;
  title: string;
  description: string;
  params?: Record<string, unknown>;
  reachableFrom?: string[];
  requiresAuth?: boolean;
  policy?: "allow" | "approval" | "deny";
};

export type AppInfo = {
  name: string;
  description: string;
};

export type AppContextReader = {
  read: (options?: { maxDestinations?: number }) => AppContext;
  defineScreens: (screens: ScreenDefinition[]) => void;
  getScreens: () => ScreenDefinition[];
  getNavigation: () => NavigationAdapter | undefined;
  toDestinations: () => ScreenDestination[];
};
