import type { Command, CommandAction, UiToolName } from "@xecutioner/protocol";
import { UI_TOOL_DEFINITIONS } from "@xecutioner/protocol";

export type PolicyDecision = { allow: true } | { allow: false; reason: string };

export type PolicyEngine = {
  authorize(sessionId: string, command: Command): PolicyDecision | Promise<PolicyDecision>;
};

const TOOL_BY_ACTION = new Map<CommandAction, UiToolName>(
  UI_TOOL_DEFINITIONS.map((def) => [def.action, def.name]),
);

function toolNameForCommand(command: Command): UiToolName | undefined {
  return TOOL_BY_ACTION.get(command.action);
}

/**
 * Allow every command. Suitable for local demos only.
 */
export function createAllowAllPolicy(): PolicyEngine {
  return {
    authorize: () => ({ allow: true }),
  };
}

export type ToolActionPolicyOptions = {
  tools?: UiToolName[];
  actions?: CommandAction[];
};

/**
 * Only listed tools / actions are allowed.
 */
export function createAllowlistPolicy(options: ToolActionPolicyOptions): PolicyEngine {
  const tools = new Set(options.tools ?? []);
  const actions = new Set(options.actions ?? []);

  return {
    authorize(_sessionId, command) {
      const tool = toolNameForCommand(command);
      const toolAllowed = tools.size === 0 || (tool !== undefined && tools.has(tool));
      const actionAllowed = actions.size === 0 || actions.has(command.action);
      if (tools.size === 0 && actions.size === 0) {
        return { allow: false, reason: "allowlist is empty" };
      }
      if (toolAllowed && actionAllowed) {
        return { allow: true };
      }
      return {
        allow: false,
        reason: `action ${command.action} is not on the allowlist`,
      };
    },
  };
}

/**
 * Listed tools / actions are denied; everything else is allowed.
 */
export function createDenyListPolicy(options: ToolActionPolicyOptions): PolicyEngine {
  const tools = new Set(options.tools ?? []);
  const actions = new Set(options.actions ?? []);

  return {
    authorize(_sessionId, command) {
      const tool = toolNameForCommand(command);
      if (tool && tools.has(tool)) {
        return { allow: false, reason: `tool ${tool} is denied` };
      }
      if (actions.has(command.action)) {
        return { allow: false, reason: `action ${command.action} is denied` };
      }
      return { allow: true };
    },
  };
}

export type RateLimitPolicyOptions = {
  maxConcurrentPerSession: number;
  maxCommandsPerMinute?: number;
  inner?: PolicyEngine;
};

type SessionRateState = {
  inFlight: number;
  windowStartedAt: number;
  windowCount: number;
};

/**
 * Limit concurrent and/or per-minute commands per session.
 * Call `begin` before dispatch and `end` when the command settles.
 */
export function createRateLimitPolicy(options: RateLimitPolicyOptions): PolicyEngine & {
  begin(sessionId: string): PolicyDecision;
  end(sessionId: string): void;
} {
  const inner = options.inner ?? createAllowAllPolicy();
  const states = new Map<string, SessionRateState>();

  function getState(sessionId: string): SessionRateState {
    let state = states.get(sessionId);
    if (!state) {
      state = { inFlight: 0, windowStartedAt: Date.now(), windowCount: 0 };
      states.set(sessionId, state);
    }
    return state;
  }

  function begin(sessionId: string): PolicyDecision {
    const state = getState(sessionId);
    if (state.inFlight >= options.maxConcurrentPerSession) {
      return {
        allow: false,
        reason: `max concurrent commands (${options.maxConcurrentPerSession}) exceeded`,
      };
    }
    if (options.maxCommandsPerMinute !== undefined) {
      const now = Date.now();
      if (now - state.windowStartedAt >= 60_000) {
        state.windowStartedAt = now;
        state.windowCount = 0;
      }
      if (state.windowCount >= options.maxCommandsPerMinute) {
        return {
          allow: false,
          reason: `max commands per minute (${options.maxCommandsPerMinute}) exceeded`,
        };
      }
      state.windowCount += 1;
    }
    state.inFlight += 1;
    return { allow: true };
  }

  function end(sessionId: string): void {
    const state = states.get(sessionId);
    if (!state) {
      return;
    }
    state.inFlight = Math.max(0, state.inFlight - 1);
  }

  return {
    begin,
    end,
    async authorize(sessionId, command) {
      const decision = await inner.authorize(sessionId, command);
      if (!decision.allow) {
        return decision;
      }
      return begin(sessionId);
    },
  };
}

export function isRateLimitPolicy(policy: PolicyEngine): policy is PolicyEngine & {
  begin: (sessionId: string) => PolicyDecision;
  end: (sessionId: string) => void;
} {
  return (
    typeof (policy as { begin?: unknown }).begin === "function" &&
    typeof (policy as { end?: unknown }).end === "function"
  );
}
