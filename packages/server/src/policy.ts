import type { Command } from "@xecutioner/protocol";

export type PolicyDecision = { allow: true } | { allow: false; reason: string };

export type PolicyEngine = {
  authorize(sessionId: string, command: Command): PolicyDecision | Promise<PolicyDecision>;
};

/**
 * MVP stub: allow all. Phase 3 replaces with real allow/deny rules.
 */
export function createAllowAllPolicy(): PolicyEngine {
  return {
    authorize: () => ({ allow: true }),
  };
}
