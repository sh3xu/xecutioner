import { describe, expect, it } from "vitest";
import { createAppContextReader } from "./context-reader.js";
import type { NavigationAdapter } from "./types.js";

function mockNav(overrides?: Partial<NavigationAdapter>): NavigationAdapter {
  return {
    getState: () => ({
      screenId: "orders",
      stack: ["tabs", "orders"],
      tabs: ["orders", "profile"],
      params: { filter: "open" },
    }),
    getKnownRoutes: () => ["orders", "order_detail", "profile", "login"],
    navigate: async () => undefined,
    back: async () => undefined,
    ...overrides,
  };
}

describe("createAppContextReader", () => {
  it("merges runtime, auto, and declared destinations with declared winning", () => {
    const reader = createAppContextReader({
      app: { name: "Shop", description: "Demo shop app" },
      navigation: mockNav(),
      screens: [
        {
          id: "order_detail",
          title: "Order detail",
          description: "One order: items, status, tracking",
          params: { orderId: "string" },
        },
      ],
    });

    const ctx = reader.read();
    expect(ctx.app.name).toBe("Shop");
    expect(ctx.current.screenId).toBe("orders");
    expect(ctx.current.stack).toEqual(["tabs", "orders"]);
    expect(ctx.current.params).toEqual({ filter: "open" });

    const detail = ctx.destinations.find((d) => d.id === "order_detail");
    expect(detail?.source).toBe("declared");
    expect(detail?.description).toContain("One order");

    const orders = ctx.destinations.find((d) => d.id === "orders");
    expect(orders).toBeTruthy();
  });

  it("defineScreens updates the declared map", () => {
    const reader = createAppContextReader({
      app: { name: "Shop", description: "Demo" },
      navigation: mockNav({ getKnownRoutes: () => [] }),
    });
    reader.defineScreens([{ id: "checkout", title: "Checkout", description: "Pay for the cart" }]);
    expect(reader.read().destinations.some((d) => d.id === "checkout")).toBe(true);
  });

  it("returns unknown current when no navigation adapter is present", () => {
    const reader = createAppContextReader({
      app: { name: "Shop", description: "Demo" },
      screens: [{ id: "home", title: "Home", description: "Home screen" }],
    });
    const ctx = reader.read();
    expect(ctx.current.screenId).toBe("unknown");
    expect(ctx.destinations[0]?.id).toBe("home");
  });
});
