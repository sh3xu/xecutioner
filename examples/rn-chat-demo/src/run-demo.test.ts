import { describe, expect, it } from "vitest";
import { createDemoHost, createDemoPerformAction } from "./host-app.js";

describe("demo host", () => {
  it("navigates list -> detail -> checkout and accepts email", async () => {
    const host = createDemoHost();
    const perform = createDemoPerformAction(host);

    await perform({ action: "tap", elementId: "order-1" });
    expect(host.getScreen()).toBe("detail");

    await perform({ action: "tap", elementId: "buy-button" });
    expect(host.getScreen()).toBe("checkout");

    await perform({
      action: "input",
      elementId: "email-input",
      text: "a@b.com",
    });
    expect(host.getEmail()).toBe("a@b.com");
  });

  it("supports navigate-by-id via the navigation adapter", async () => {
    const host = createDemoHost();
    const nav = host.createNavigationAdapter();
    await nav.navigate("order_detail", { orderId: "1001" });
    expect(host.getScreenId()).toBe("order_detail");
    expect(nav.getState()?.params).toEqual({ orderId: "1001" });
    await nav.navigate("checkout");
    expect(host.getScreenId()).toBe("checkout");
  });
});
