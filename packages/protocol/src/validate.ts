import { COMMAND_ACTIONS, PROTOCOL_VERSION } from "./constants.js";
import type { Command, CommandResult, Handshake, Snapshot } from "./generated/types.js";

export type ValidationResult<T> = { ok: true; value: T } | { ok: false; error: string };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Lightweight structural validation for wire messages.
 * Optional `strictVersion` rejects mismatched protocol versions.
 */
export function validateHandshake(
  value: unknown,
  options?: { strictVersion?: boolean },
): ValidationResult<Handshake> {
  if (!isRecord(value) || value.type !== "handshake") {
    return { ok: false, error: "Expected handshake message" };
  }
  if (typeof value.sessionId !== "string" || !value.sessionId) {
    return { ok: false, error: "handshake.sessionId is required" };
  }
  if (!Array.isArray(value.capabilities)) {
    return { ok: false, error: "handshake.capabilities must be an array" };
  }
  if (options?.strictVersion !== false && value.protocolVersion !== PROTOCOL_VERSION) {
    return {
      ok: false,
      error: `Unsupported protocolVersion: ${String(value.protocolVersion)}`,
    };
  }
  return { ok: true, value: value as unknown as Handshake };
}

export function validateCommand(value: unknown): ValidationResult<Command> {
  if (!isRecord(value)) {
    return { ok: false, error: "Command must be an object" };
  }
  const required = ["callId", "action", "idempotencyKey", "deadline"] as const;
  for (const key of required) {
    if (value[key] === undefined || value[key] === null || value[key] === "") {
      return { ok: false, error: `command.${key} is required` };
    }
  }
  if (!(COMMAND_ACTIONS as readonly string[]).includes(String(value.action))) {
    return { ok: false, error: `Unknown action: ${String(value.action)}` };
  }

  if (typeof value.deadline !== "number") {
    return { ok: false, error: "command.deadline must be a number" };
  }
  return { ok: true, value: value as unknown as Command };
}

export function validateCommandResult(value: unknown): ValidationResult<CommandResult> {
  if (!isRecord(value)) {
    return { ok: false, error: "CommandResult must be an object" };
  }
  if (typeof value.callId !== "string" || !value.callId) {
    return { ok: false, error: "result.callId is required" };
  }
  if (typeof value.ok !== "boolean") {
    return { ok: false, error: "result.ok must be a boolean" };
  }
  return { ok: true, value: value as unknown as CommandResult };
}

export function validateSnapshot(value: unknown): ValidationResult<Snapshot> {
  if (!isRecord(value)) {
    return { ok: false, error: "Snapshot must be an object" };
  }
  if (typeof value.snapshotId !== "string" || !value.snapshotId) {
    return { ok: false, error: "snapshot.snapshotId is required" };
  }
  if (!Array.isArray(value.elements)) {
    return { ok: false, error: "snapshot.elements must be an array" };
  }
  if (typeof value.capturedAt !== "number") {
    return { ok: false, error: "snapshot.capturedAt must be a number" };
  }
  return { ok: true, value: value as unknown as Snapshot };
}
