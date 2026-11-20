import {
  createSnapshotId,
  type Snapshot,
  trimSnapshot,
  type UiElement,
} from "@xecutioner/protocol";
import type { HostUiNode, SnapshotContext } from "./types.js";

function roleOf(node: HostUiNode): string {
  if (node.accessibilityRole) {
    return String(node.accessibilityRole).toLowerCase();
  }
  const propsRole = node.props?.accessibilityRole ?? node.props?.role;
  if (typeof propsRole === "string") {
    return propsRole.toLowerCase();
  }
  return "view";
}

function labelOf(node: HostUiNode): string | undefined {
  return (
    node.accessibilityLabel ??
    (typeof node.props?.accessibilityLabel === "string"
      ? node.props.accessibilityLabel
      : undefined) ??
    (typeof node.props?.label === "string" ? node.props.label : undefined)
  );
}

function elementValue(node: HostUiNode): string | undefined {
  if (node.accessibilityValue?.text) {
    return node.accessibilityValue.text;
  }
  const v = node.props?.value ?? node.props?.placeholder;
  return typeof v === "string" ? v : undefined;
}

function inferActions(role: string, explicit?: string[]): string[] {
  if (explicit?.length) {
    return explicit;
  }
  if (["button", "link", "pressable", "checkbox", "switch", "tab"].includes(role)) {
    return ["tap"];
  }
  if (["textbox", "search", "textinput", "input"].includes(role)) {
    return ["input", "tap"];
  }
  if (["scrollview", "list", "scroll"].includes(role)) {
    return ["scroll"];
  }
  return [];
}

export type SerializeOptions = SnapshotContext & {
  /** NOTE: Counter for generated refs when stable ids are missing. */
  refCounter?: { value: number };
};

/**
 * Convert a host UI node tree into protocol UiElements.
 */
export function serializeHostNode(node: HostUiNode, options?: SerializeOptions): UiElement | null {
  const counter = options?.refCounter ?? { value: 0 };
  const stableId =
    node.testID ?? (typeof node.props?.testID === "string" ? node.props.testID : undefined);

  const id = stableId ?? `ref_${counter.value++}`;
  const role = roleOf(node);
  const redacted = Boolean(node.xecutionerRedact || node.props?.xecutionerRedact);

  const children = (node.children ?? [])
    .map((child) => serializeHostNode(child, { ...options, refCounter: counter }))
    .filter((c): c is UiElement => c !== null);

  const element: UiElement = {
    id,
    role,
    label: redacted ? "[redacted]" : labelOf(node),
    value: redacted ? undefined : elementValue(node),

    state: {
      enabled: !(node.accessibilityState?.disabled ?? false),
      focused: false,
      checked:
        node.accessibilityState?.checked === true
          ? true
          : node.accessibilityState?.checked === false
            ? false
            : undefined,
      visible: true,
    },
    bounds: node.bounds,
    actions: inferActions(role, node.actions),
    children: children.length ? children : undefined,
    redacted: redacted || undefined,
  };

  return element;
}

/**
 * Build a protocol Snapshot from a host root node.
 */
export function captureSnapshot(
  root: HostUiNode | null | undefined,
  options?: SerializeOptions,
): Snapshot {
  const elements: UiElement[] = [];
  if (root) {
    const serialized = serializeHostNode(root, options);
    if (serialized) {
      elements.push(serialized);
    }
  }

  const snapshot: Snapshot = {
    snapshotId: createSnapshotId(),
    screen: options?.screen,
    route: options?.route,
    elements,
    capturedAt: Date.now(),
  };

  return trimSnapshot(snapshot, { tokenBudget: options?.tokenBudget });
}
