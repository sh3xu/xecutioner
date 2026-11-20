import type { Snapshot } from "@xecutioner/protocol";
import { describe, expect, it } from "vitest";
import { executeCommand } from "./executors.js";
import type { HostUiNode } from "./types.js";

function makeTree(): HostUiNode {
  return {
    testID: "root",
    children: [
      {
        testID: "buy",
        accessibilityRole: "button",
        accessibilityLabel: "Buy",
      },
      {
        testID: "email",
        accessibilityRole: "textbox",
        accessibilityLabel: "Email",
        props: { value: "" },
      },
    ],
  };
}

describe("executeCommand", () => {
  it("reads the screen", async () => {
    const root = makeTree();
    let last: Snapshot | null = null;
    const result = await executeCommand(
      {
        callId: "c1",
        action: "read_screen",
        idempotencyKey: "i1",
        deadline: Date.now() + 5_000,
      },
      {
        hooks: {
          getRootNode: () => root,
          getScreenMeta: () => ({ screen: "Home" }),
        },
        lastSnapshot: null,
        setLastSnapshot: (s) => {
          last = s;
        },
      },
    );
    expect(result.ok).toBe(true);
    expect(result.snapshot?.screen).toBe("Home");
    expect(last?.snapshotId).toBe(result.snapshot?.snapshotId);
  });

  it("taps an element via performAction", async () => {
    const root = makeTree();
    const taps: string[] = [];
    let lastSnapshot: Snapshot | null = null;
    const read = await executeCommand(
      {
        callId: "r1",
        action: "read_screen",
        idempotencyKey: "ir",
        deadline: Date.now() + 5_000,
      },
      {
        hooks: { getRootNode: () => root },
        lastSnapshot: null,
        setLastSnapshot: (s) => {
          lastSnapshot = s;
        },
      },
    );
    expect(read.ok).toBe(true);
    if (!lastSnapshot) {
      throw new Error("Expected snapshot after read_screen");
    }
    const snapshotId = lastSnapshot.snapshotId;

    const result = await executeCommand(
      {
        callId: "c2",
        action: "tap",
        elementId: "buy",
        snapshotId,
        idempotencyKey: "i2",
        deadline: Date.now() + 5_000,
      },
      {
        hooks: {
          getRootNode: () => root,
          performAction: async ({ elementId }) => {
            taps.push(elementId);
          },
        },
        lastSnapshot,
        setLastSnapshot: (s) => {
          lastSnapshot = s;
        },
      },
    );

    expect(result.ok).toBe(true);
    expect(taps).toEqual(["buy"]);
  });

  it("rejects stale snapshots", async () => {
    const root = makeTree();
    const result = await executeCommand(
      {
        callId: "c3",
        action: "tap",
        elementId: "buy",
        snapshotId: "old",
        idempotencyKey: "i3",
        deadline: Date.now() + 5_000,
      },
      {
        hooks: { getRootNode: () => root },
        lastSnapshot: {
          snapshotId: "new",
          capturedAt: Date.now(),
          elements: [],
        },
        setLastSnapshot: () => undefined,
      },
    );
    expect(result.ok).toBe(false);
    expect(result.errorCode).toBe("stale_snapshot");
  });
});
