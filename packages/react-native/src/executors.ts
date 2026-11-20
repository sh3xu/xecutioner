import {
  type AppContext,
  buildCommandResult,
  type Command,
  type CommandResult,
  findElementById,
  isElementActionable,
  type Snapshot,
} from "@xecutioner/protocol";
import { createAppContextReader } from "./navigation/context-reader.js";
import type { AppContextReader } from "./navigation/types.js";
import { captureSnapshot } from "./snapshot.js";
import type { HostHooks, HostUiNode } from "./types.js";

export type ExecuteContext = {
  hooks: HostHooks;
  lastSnapshot: Snapshot | null;
  setLastSnapshot: (snapshot: Snapshot) => void;
};

function resolveContextReader(hooks: HostHooks): AppContextReader | undefined {
  if (hooks.contextReader) {
    return hooks.contextReader;
  }
  if (hooks.navigation) {
    return createAppContextReader({
      app: { name: "app", description: "Host application" },
      navigation: hooks.navigation,
    });
  }
  return undefined;
}

function readFreshSnapshot(ctx: ExecuteContext, tokenBudget?: number): Snapshot {
  const reader = resolveContextReader(ctx.hooks);
  const nav = reader?.read();
  const meta = ctx.hooks.getScreenMeta?.() ?? {};
  const root = ctx.hooks.getRootNode();
  const snapshot = captureSnapshot(root, {
    screen: nav?.current.screenId ?? meta.screen,
    route: meta.route ?? nav?.current.screenId,
    tokenBudget,
  });
  ctx.setLastSnapshot(snapshot);
  return snapshot;
}

function assertSnapshotFresh(
  command: Command,
  lastSnapshot: Snapshot | null,
): CommandResult | null {
  if (!command.snapshotId) {
    return null;
  }
  if (!lastSnapshot || lastSnapshot.snapshotId !== command.snapshotId) {
    return buildCommandResult(command.callId, {
      errorCode: "stale_snapshot",
      errorMessage: "snapshotId does not match the latest client snapshot",
      snapshot: lastSnapshot ?? undefined,
    });
  }
  return null;
}

function findInTree(
  root: HostUiNode | null | undefined,
  elementId: string,
): HostUiNode | undefined {
  if (!root) {
    return undefined;
  }
  const stack: HostUiNode[] = [root];
  while (stack.length) {
    const node = stack.pop();
    if (!node) {
      continue;
    }
    const id =
      node.testID ?? (typeof node.props?.testID === "string" ? node.props.testID : undefined);
    if (id === elementId) {
      return node;
    }
    if (node.children?.length) {
      stack.push(...node.children);
    }
  }
  return undefined;
}

function readContext(
  ctx: ExecuteContext,
  options?: { maxDestinations?: number },
): AppContext | null {
  const reader = resolveContextReader(ctx.hooks);
  if (!reader) {
    return null;
  }
  return reader.read(options);
}

/**
 * Execute a single UI command against the host tree / navigation adapter.
 */
export async function executeCommand(
  command: Command,
  ctx: ExecuteContext,
): Promise<CommandResult> {
  ctx.hooks.onAiActing?.(true);
  try {
    if (command.action === "get_context") {
      const appContext = readContext(ctx, {
        maxDestinations: command.maxDestinations,
      });
      if (!appContext) {
        return buildCommandResult(command.callId, {
          errorCode: "navigation_unavailable",
          errorMessage: "No contextReader or navigation adapter configured on the client",
        });
      }
      const snapshot = readFreshSnapshot(ctx);
      return buildCommandResult(command.callId, { snapshot, appContext });
    }

    if (command.action === "navigate" || command.action === "back") {
      const reader = resolveContextReader(ctx.hooks);
      const navigation = reader?.getNavigation() ?? ctx.hooks.navigation;
      if (!navigation) {
        return buildCommandResult(command.callId, {
          errorCode: "navigation_unavailable",
          errorMessage: "No navigation adapter configured on the client",
        });
      }

      if (command.action === "navigate") {
        const screenId = command.screenId;
        if (!screenId) {
          return buildCommandResult(command.callId, {
            errorCode: "invalid_arguments",
            errorMessage: "screenId is required for navigate",
          });
        }

        const appContext = reader?.read();
        const known = appContext?.destinations.some((d) => d.id === screenId);
        const autoKnown = navigation.getKnownRoutes?.().includes(screenId);
        if (appContext && !known && !autoKnown) {
          return buildCommandResult(command.callId, {
            errorCode: "unknown_screen",
            errorMessage: `Unknown screenId: ${screenId}`,
            appContext,
          });
        }

        const destination = appContext?.destinations.find((d) => d.id === screenId);
        if (destination?.policy === "deny") {
          return buildCommandResult(command.callId, {
            errorCode: "blocked_by_policy",
            errorMessage: `Screen ${screenId} is denied by screen map policy`,
            appContext,
          });
        }

        if (ctx.hooks.onApprovalRequest && destination?.policy === "approval") {
          const approved = await ctx.hooks.onApprovalRequest({
            callId: command.callId,
            action: "navigate",
            screenId,
          });
          if (!approved) {
            return buildCommandResult(command.callId, {
              errorCode: "blocked_by_policy",
              errorMessage: "Host denied navigation approval",
              appContext,
            });
          }
        }

        await navigation.navigate(screenId, command.params);
      } else {
        await navigation.back();
      }

      const snapshot = readFreshSnapshot(ctx);
      const nextContext = readContext(ctx) ?? undefined;
      return buildCommandResult(command.callId, {
        snapshot,
        appContext: nextContext,
      });
    }

    if (command.action === "read_screen") {
      const snapshot = readFreshSnapshot(ctx);
      return buildCommandResult(command.callId, { snapshot });
    }

    const stale = assertSnapshotFresh(command, ctx.lastSnapshot);
    if (stale) {
      return stale;
    }

    if (command.action === "wait_for") {
      const timeoutMs = command.waitCondition?.timeoutMs ?? 5_000;
      const started = Date.now();
      while (Date.now() - started < timeoutMs) {
        const snapshot = readFreshSnapshot(ctx);
        const elementId = command.waitCondition?.elementId;
        const labelContains = command.waitCondition?.labelContains;
        if (elementId && findElementById(snapshot.elements, elementId)) {
          return buildCommandResult(command.callId, { snapshot });
        }
        if (labelContains && JSON.stringify(snapshot.elements).includes(labelContains)) {
          return buildCommandResult(command.callId, { snapshot });
        }
        await new Promise((r) => setTimeout(r, 100));
      }
      return buildCommandResult(command.callId, {
        errorCode: "timeout",
        errorMessage: "wait_for condition not met",
        snapshot: ctx.lastSnapshot ?? undefined,
      });
    }

    const elementId = command.elementId;
    if (!elementId) {
      return buildCommandResult(command.callId, {
        errorCode: "invalid_arguments",
        errorMessage: "elementId is required",
      });
    }

    const snapshot = ctx.lastSnapshot ?? readFreshSnapshot(ctx);
    const element = findElementById(snapshot.elements, elementId, {
      allowSuffixMatch: true,
    });
    if (!element) {
      return buildCommandResult(command.callId, {
        errorCode: "element_not_found",
        errorMessage: `Element not found: ${elementId}`,
        snapshot,
      });
    }

    if (
      (command.action === "tap" || command.action === "scroll" || command.action === "input") &&
      !isElementActionable(element, command.action)
    ) {
      return buildCommandResult(command.callId, {
        errorCode: "not_actionable",
        errorMessage: `Element ${elementId} is not actionable for ${command.action}`,
        snapshot,
      });
    }

    if (ctx.hooks.onApprovalRequest) {
      const approved = await ctx.hooks.onApprovalRequest({
        callId: command.callId,
        action: command.action,
        elementId,
      });
      if (!approved) {
        return buildCommandResult(command.callId, {
          errorCode: "blocked_by_policy",
          errorMessage: "Host denied approval",
          snapshot,
        });
      }
    }

    const root = ctx.hooks.getRootNode();
    const hostNode = findInTree(root, elementId);
    if (!hostNode && !ctx.hooks.performAction) {
      return buildCommandResult(command.callId, {
        errorCode: "element_not_found",
        errorMessage: `Host node not found: ${elementId}`,
        snapshot,
      });
    }

    if (ctx.hooks.performAction) {
      await ctx.hooks.performAction({
        action: command.action as "tap" | "scroll" | "input",
        elementId,
        text: command.text,
        direction: command.direction,
        amount: command.amount,
      });
    } else if (command.action === "input" && hostNode) {
      hostNode.props = { ...hostNode.props, value: command.text ?? "" };
      if (hostNode.accessibilityValue) {
        hostNode.accessibilityValue = { text: command.text ?? "" };
      }
    }

    const next = readFreshSnapshot(ctx);
    return buildCommandResult(command.callId, { snapshot: next });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const errorCode = message.startsWith("navigation_unavailable")
      ? "navigation_unavailable"
      : "internal_error";
    return buildCommandResult(command.callId, {
      errorCode,
      errorMessage: message,
      snapshot: ctx.lastSnapshot ?? undefined,
    });
  } finally {
    ctx.hooks.onAiActing?.(false);
  }
}
