import { describe, expect, it } from "vitest";
import { captureSnapshot, serializeHostNode } from "./snapshot.js";
import type { HostUiNode } from "./types.js";

const tree: HostUiNode = {
  testID: "root",
  accessibilityRole: "summary",
  children: [
    {
      testID: "order-1",
      accessibilityRole: "button",
      accessibilityLabel: "Order 1",
    },
    {
      testID: "password",
      accessibilityRole: "textbox",
      accessibilityLabel: "Password",
      xecutionerRedact: true,
      accessibilityValue: { text: "secret" },
    },
  ],
};

describe("serializeHostNode", () => {
  it("prefers stable testIDs and redacts sensitive fields", () => {
    const el = serializeHostNode(tree);
    expect(el?.id).toBe("root");
    expect(el?.children?.[0]?.id).toBe("order-1");
    expect(el?.children?.[1]?.label).toBe("[redacted]");
    expect(el?.children?.[1]?.value).toBeUndefined();
  });

  it("generates refs when testID is missing", () => {
    const el = serializeHostNode({ accessibilityRole: "button" });
    expect(el?.id.startsWith("ref_")).toBe(true);
  });
});

describe("captureSnapshot", () => {
  it("returns a trimmed snapshot", () => {
    const snap = captureSnapshot(tree, { screen: "Orders", tokenBudget: 500 });
    expect(snap.snapshotId).toBeTruthy();
    expect(snap.screen).toBe("Orders");
    expect(snap.elements.length).toBeGreaterThan(0);
  });
});
