import type { Command } from "@xecutioner/protocol";
import { describe, expect, it } from "vitest";
import { PendingCommandTracker } from "./pending-tracker.js";

function cmd(overrides?: Partial<Command>): Command {
  return {
    callId: "c1",
    action: "tap",
    idempotencyKey: "i1",
    deadline: Date.now() + 5_000,
    elementId: "btn",
    ...overrides,
  };
}

describe("PendingCommandTracker", () => {
  it("resolves when completed", async () => {
    const tracker = new PendingCommandTracker();
    const promise = tracker.track(cmd());
    expect(tracker.complete({ callId: "c1", ok: true })).toBe(true);
    await expect(promise).resolves.toMatchObject({ callId: "c1", ok: true });
  });

  it("returns cached result for same idempotency key", async () => {
    const tracker = new PendingCommandTracker();
    const promise = tracker.track(cmd());
    tracker.complete({ callId: "c1", ok: true });
    await promise;
    const again = await tracker.track(cmd({ callId: "c2" }));
    expect(again.callId).toBe("c1");
  });

  it("times out", async () => {
    const tracker = new PendingCommandTracker();
    const promise = tracker.track(cmd({ deadline: Date.now() + 20 }), {
      timeoutMs: 20,
    });
    await expect(promise).rejects.toThrow(/timed out/);
  });
});
