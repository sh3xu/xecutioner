/* eslint-disable */
/**
 * NOTE: Generated from schemas/protocol.json — do not edit by hand.
 * Run `pnpm generate` in @xecutioner/protocol to regenerate.
 */

/**
 * Wire protocol for in-app UI control
 */
export type XecutionerWire =
  | ProtocolVersion
  | ErrorCode
  | ScreenDestination
  | AppContext
  | ElementState
  | Bounds
  | UiElement
  | Snapshot
  | CommandAction
  | Command
  | CommandResult
  | Handshake
  | WireMessage;
export type ProtocolVersion = "0.1.0";
export type ErrorCode =
  | "stale_snapshot"
  | "element_not_found"
  | "not_actionable"
  | "blocked_by_policy"
  | "timeout"
  | "client_unavailable"
  | "invalid_arguments"
  | "internal_error"
  | "unknown_screen"
  | "navigation_unavailable";
export type CommandAction =
  "tap" | "scroll" | "input" | "read_screen" | "wait_for" | "get_context" | "navigate" | "back";
export type WireMessage =
  | Handshake
  | {
      type: "command";
      command: Command;
    }
  | {
      type: "result";
      result: CommandResult;
    }
  | {
      type: "ping";
    }
  | {
      type: "pong";
    }
  | {
      type: "client_unavailable";
      sessionId: string;
      reason?: string;
    };

export interface ScreenDestination {
  id: string;
  title: string;
  description: string;
  params?: {
    [k: string]: unknown;
  };
  reachableFrom?: string[];
  requiresAuth?: boolean;
  policy?: "allow" | "approval" | "deny";
  /**
   * Where this destination entry came from
   */
  source?: "declared" | "auto" | "runtime";
}
export interface AppContext {
  app: {
    name: string;
    description: string;
  };
  current: {
    screenId: string;
    params?: {
      [k: string]: unknown;
    };
    stack: string[];
    tabs?: string[];
  };
  destinations: ScreenDestination[];
}
export interface ElementState {
  enabled?: boolean;
  focused?: boolean;
  checked?: boolean;
  visible?: boolean;
}
export interface Bounds {
  x: number;
  y: number;
  width: number;
  height: number;
}
export interface UiElement {
  /**
   * Stable testID or generated per-snapshot ref
   */
  id: string;
  role: string;
  label?: string;
  value?: string;
  state?: ElementState;
  bounds?: Bounds;
  actions?: string[];
  children?: UiElement[];
  redacted?: boolean;
}
export interface Snapshot {
  snapshotId: string;
  screen?: string;
  route?: string;
  elements: UiElement[];
  capturedAt: number;
  tokenEstimate?: number;
}
export interface Command {
  callId: string;
  action: CommandAction;
  snapshotId?: string;
  idempotencyKey: string;
  deadline: number;
  elementId?: string;
  text?: string;
  direction?: "up" | "down" | "left" | "right";
  amount?: number;
  screenId?: string;
  params?: {
    [k: string]: unknown;
  };
  maxDestinations?: number;
  waitCondition?: {
    elementId?: string;
    labelContains?: string;
    timeoutMs?: number;
  };
}
export interface CommandResult {
  callId: string;
  ok: boolean;
  errorCode?: ErrorCode;
  errorMessage?: string;
  snapshot?: Snapshot;
  appContext?: AppContext;
}
export interface Handshake {
  type: "handshake";
  protocolVersion: ProtocolVersion;
  sessionId: string;
  capabilities: string[];
  clientInfo?: {
    platform?: string;
    appVersion?: string;
  };
}

