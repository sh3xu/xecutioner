export const PROTOCOL_VERSION = "0.1.0" as const;

export const DEFAULT_COMMAND_TIMEOUT_MS = 15_000;

export const DEFAULT_SNAPSHOT_TOKEN_BUDGET = 2_000;

export const DEFAULT_CONTEXT_DESTINATION_LIMIT = 40;

export const UI_TOOL_NAMES = [
  "ui_tap",
  "ui_scroll",
  "ui_input",
  "ui_read_screen",
  "ui_wait_for",
  "ui_get_context",
  "ui_navigate",
  "ui_back",
] as const;

export type UiToolName = (typeof UI_TOOL_NAMES)[number];

export const CLIENT_CAPABILITIES = [
  "tap",
  "scroll",
  "input",
  "read_screen",
  "wait_for",
  "get_context",
  "navigate",
  "back",
] as const;

export const COMMAND_ACTIONS = [
  "tap",
  "scroll",
  "input",
  "read_screen",
  "wait_for",
  "get_context",
  "navigate",
  "back",
] as const;
