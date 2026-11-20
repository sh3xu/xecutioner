import { describe, expect, it } from "vitest";
import type { Snapshot, UiElement } from "./generated/types.js";
import {
  buildCommandResult,
  findElementById,
  flattenElements,
  formatAppContextForModel,
  formatSnapshotAsUntrusted,
  isElementActionable,
  mergeDestinations,
  trimSnapshot,
} from "./helpers.js";

const tree: UiElement[] = [
  {
    id: "header",
    role: "header",
    label: "Orders",
    children: [
      {
        id: "order-1",
        role: "button",
        label: "Order 1",
        state: { enabled: true, visible: true },
        actions: ["tap"],
      },
      {
        id: "search",
        role: "textbox",
        label: "Search",
        state: { enabled: true, visible: true },
        actions: ["input", "tap"],
      },
    ],
  },
];

describe("findElementById", () => {
  it("finds nested elements", () => {
    expect(findElementById(tree, "order-1")?.label).toBe("Order 1");
  });

  it("supports optional suffix match", () => {
    const withRef: UiElement[] = [{ id: "gen:order-1", role: "button" }];
    expect(findElementById(withRef, "order-1", { allowSuffixMatch: true })?.id).toBe("gen:order-1");
  });
});

describe("flattenElements and trimSnapshot", () => {
  it("flattens trees", () => {
    expect(flattenElements(tree).map((e) => e.id)).toEqual(["header", "order-1", "search"]);
  });

  it("trims under token budget", () => {
    const snapshot: Snapshot = {
      snapshotId: "s1",
      capturedAt: Date.now(),
      elements: tree,
      screen: "Orders",
    };
    const trimmed = trimSnapshot(snapshot, { tokenBudget: 20 });
    expect(trimmed.elements.length).toBeLessThanOrEqual(3);
    expect(trimmed.tokenEstimate).toBeDefined();
  });
});

describe("buildCommandResult and formatSnapshotAsUntrusted", () => {
  it("builds success and failure results", () => {
    expect(buildCommandResult("c1").ok).toBe(true);
    expect(buildCommandResult("c2", { errorCode: "element_not_found" }).errorCode).toBe(
      "element_not_found",
    );
  });

  it("labels snapshot as untrusted", () => {
    const text = formatSnapshotAsUntrusted({
      snapshotId: "s1",
      capturedAt: 1,
      elements: [],
    });
    expect(text).toContain("UNTRUSTED_UI_SNAPSHOT");
  });
});

describe("isElementActionable", () => {
  it("checks actions and state", () => {
    const btn = findElementById(tree, "order-1");
    expect(btn && isElementActionable(btn, "tap")).toBe(true);
    expect(isElementActionable({ id: "x", role: "button", state: { enabled: false } }, "tap")).toBe(
      false,
    );
  });
});

describe("mergeDestinations and formatAppContextForModel", () => {
  it("lets declared screens win over auto/runtime", () => {
    const merged = mergeDestinations({
      auto: [{ id: "orders", title: "orders", description: "auto", source: "auto" }],
      runtime: [{ id: "orders", title: "orders", description: "runtime", source: "runtime" }],
      declared: [
        {
          id: "orders",
          title: "Orders",
          description: "List of past orders",
          source: "declared",
        },
      ],
    });
    expect(merged).toHaveLength(1);
    expect(merged[0]?.description).toBe("List of past orders");
    expect(merged[0]?.source).toBe("declared");
  });

  it("formats navigation context for the model", () => {
    const text = formatAppContextForModel({
      app: { name: "Shop", description: "Demo" },
      current: { screenId: "orders", stack: ["orders"] },
      destinations: [{ id: "orders", title: "Orders", description: "List" }],
    });
    expect(text).toContain("APP_NAVIGATION_CONTEXT");
    expect(text).toContain("orders");
  });
});
