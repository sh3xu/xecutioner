import { describe, expect, it } from "vitest";
import {
  collectRouteNames,
  createReactNavigationAdapter,
  parseReactNavigationState,
} from "./react-navigation.js";

const sampleState = {
  type: "tab",
  index: 0,
  routeNames: ["orders", "profile"],
  routes: [
    {
      name: "orders",
      state: {
        index: 1,
        routes: [{ name: "orders_list" }, { name: "order_detail", params: { orderId: "1001" } }],
      },
    },
    { name: "profile" },
  ],
};

describe("parseReactNavigationState", () => {
  it("reads the leaf route, stack, params, and tabs", () => {
    const parsed = parseReactNavigationState(sampleState);
    expect(parsed).toEqual({
      screenId: "order_detail",
      params: { orderId: "1001" },
      stack: ["orders", "order_detail"],
      tabs: ["orders", "profile"],
    });
  });
});

describe("collectRouteNames", () => {
  it("flattens route names from the tree", () => {
    expect(collectRouteNames(sampleState).sort()).toEqual(
      ["order_detail", "orders", "orders_list", "profile"].sort(),
    );
  });
});

describe("createReactNavigationAdapter", () => {
  it("navigates and goes back through the ref", async () => {
    const calls: string[] = [];
    const adapter = createReactNavigationAdapter({
      getRef: () => ({
        getRootState: () => sampleState,
        navigate: (name, params) => {
          calls.push(`nav:${name}:${JSON.stringify(params ?? {})}`);
        },
        goBack: () => {
          calls.push("back");
        },
        canGoBack: () => true,
      }),
    });

    expect(adapter.getState()?.screenId).toBe("order_detail");
    await adapter.navigate("checkout", { cartId: "c1" });
    await adapter.back();
    expect(calls).toEqual(['nav:checkout:{"cartId":"c1"}', "back"]);
  });
});
