import type { Command, CommandResult } from "@xecutioner/protocol";

export type PendingEntry = {
  command: Command;
  resolve: (result: CommandResult) => void;
  reject: (error: Error) => void;
  timer: ReturnType<typeof setTimeout>;
  createdAt: number;
};

/**
 * Tracks in-flight commands by callId with idempotency and timeouts.
 */
export class PendingCommandTracker {
  private readonly byCallId = new Map<string, PendingEntry>();
  private readonly byIdempotency = new Map<string, string>();
  private readonly completed = new Map<string, CommandResult>();

  get size(): number {
    return this.byCallId.size;
  }

  has(callId: string): boolean {
    return this.byCallId.has(callId);
  }

  getCompleted(idempotencyKey: string): CommandResult | undefined {
    const callId = this.byIdempotency.get(idempotencyKey);
    if (!callId) {
      return undefined;
    }
    return this.completed.get(callId);
  }

  track(command: Command, options?: { timeoutMs?: number }): Promise<CommandResult> {
    const cached = this.getCompleted(command.idempotencyKey);
    if (cached) {
      return Promise.resolve(cached);
    }

    const existingCall = this.byIdempotency.get(command.idempotencyKey);
    if (existingCall) {
      const pending = this.byCallId.get(existingCall);
      if (pending) {
        return new Promise((resolve, reject) => {
          const prevResolve = pending.resolve;
          const prevReject = pending.reject;
          pending.resolve = (r) => {
            prevResolve(r);
            resolve(r);
          };
          pending.reject = (e) => {
            prevReject(e);
            reject(e);
          };
        });
      }
    }

    const timeoutMs = options?.timeoutMs ?? Math.max(0, command.deadline - Date.now());

    return new Promise<CommandResult>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.byCallId.delete(command.callId);
        reject(new Error(`Command timed out: ${command.callId}`));
      }, timeoutMs);

      this.byCallId.set(command.callId, {
        command,
        resolve,
        reject,
        timer,
        createdAt: Date.now(),
      });
      this.byIdempotency.set(command.idempotencyKey, command.callId);
    });
  }

  complete(result: CommandResult): boolean {
    const entry = this.byCallId.get(result.callId);
    if (!entry) {
      return false;
    }
    clearTimeout(entry.timer);
    this.byCallId.delete(result.callId);
    this.completed.set(result.callId, result);
    entry.resolve(result);
    return true;
  }

  fail(callId: string, error: Error): boolean {
    const entry = this.byCallId.get(callId);
    if (!entry) {
      return false;
    }
    clearTimeout(entry.timer);
    this.byCallId.delete(callId);
    entry.reject(error);
    return true;
  }

  failAll(error: Error): void {
    for (const callId of [...this.byCallId.keys()]) {
      this.fail(callId, error);
    }
  }

  clearCompleted(options?: { olderThanMs?: number }): void {
    const olderThanMs = options?.olderThanMs;
    if (olderThanMs === undefined) {
      this.completed.clear();
      return;
    }
    const cutoff = Date.now() - olderThanMs;
    for (const [callId, result] of this.completed) {
      const snapTime = result.snapshot?.capturedAt ?? 0;
      if (snapTime && snapTime < cutoff) {
        this.completed.delete(callId);
      }
    }
  }
}
