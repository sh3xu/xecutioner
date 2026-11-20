import type { Snapshot, UiElement } from "@xecutioner/protocol";
import type { AppContextReader, NavigationAdapter } from "./navigation/types.js";

/**
 * Host-provided node shape. Apps can feed accessibility / testID trees.
 * Keeps the client free of RN runtime coupling for unit tests.
 */
export type HostUiNode = {
  testID?: string;
  accessibilityLabel?: string;
  accessibilityRole?: string;
  accessibilityState?: {
    disabled?: boolean;
    selected?: boolean;
    checked?: boolean | "mixed";
  };
  accessibilityValue?: { text?: string };
  accessible?: boolean;
  /** NOTE: Mark sensitive fields for redaction in snapshots. */
  xecutionerRedact?: boolean;
  props?: Record<string, unknown>;
  children?: HostUiNode[];
  /** Optional measured layout */
  bounds?: UiElement["bounds"];
  /** Optional action hints from the host */
  actions?: string[];
};

export type SnapshotContext = {
  screen?: string;
  route?: string;
  tokenBudget?: number;
};

export type HostHooks = {
  onAiActing?: (acting: boolean) => void;
  onApprovalRequest?: (payload: {
    callId: string;
    action: string;
    elementId?: string;
    screenId?: string;
  }) => Promise<boolean>;
  getRootNode: () => HostUiNode | null | undefined;
  /** Optional: apply tap/input/scroll against the live view tree */
  performAction?: (request: {
    action: "tap" | "scroll" | "input";
    elementId: string;
    text?: string;
    direction?: "up" | "down" | "left" | "right";
    amount?: number;
  }) => Promise<void>;
  getScreenMeta?: () => { screen?: string; route?: string };
  /**
   * Preferred: full context reader (runtime + declared + auto routes).
   * Falls back to `navigation` alone when unset.
   */
  contextReader?: AppContextReader;
  /** Optional bare navigation adapter when no contextReader is provided. */
  navigation?: NavigationAdapter;
};

export type LastSnapshot = Snapshot | null;
