import type { HostUiNode, NavigationAdapter, RuntimeNavState } from "@xecutioner/react-native";

export type DemoScreen = "list" | "detail" | "checkout";

const SCREEN_IDS: Record<DemoScreen, string> = {
  list: "orders",
  detail: "order_detail",
  checkout: "checkout",
};

export type DemoHost = {
  getRoot: () => HostUiNode;
  getScreen: () => DemoScreen;
  getScreenId: () => string;
  navigate: (screen: DemoScreen) => void;
  navigateById: (screenId: string, params?: Record<string, unknown>) => void;
  back: () => void;
  setEmail: (email: string) => void;
  getEmail: () => string;
  getNavState: () => RuntimeNavState;
  createNavigationAdapter: () => NavigationAdapter;
};

/**
 * Minimal multi-screen host tree used by the demo (simulates RN screens).
 */
export function createDemoHost(): DemoHost {
  let screen: DemoScreen = "list";
  let email = "";
  let stack: DemoScreen[] = ["list"];
  let orderId: string | undefined;

  function listTree(): HostUiNode {
    return {
      testID: "screen-list",
      accessibilityRole: "summary",
      accessibilityLabel: "Orders",
      children: [
        {
          testID: "order-1",
          accessibilityRole: "button",
          accessibilityLabel: "Order 1001 — Blue sneakers",
        },
        {
          testID: "order-2",
          accessibilityRole: "button",
          accessibilityLabel: "Order 1002 — Red jacket",
        },
      ],
    };
  }

  function detailTree(): HostUiNode {
    return {
      testID: "screen-detail",
      accessibilityRole: "summary",
      accessibilityLabel: "Order 1001",
      children: [
        {
          testID: "order-title",
          accessibilityRole: "header",
          accessibilityLabel: "Blue sneakers",
        },
        {
          testID: "buy-button",
          accessibilityRole: "button",
          accessibilityLabel: "Buy now",
        },
        {
          testID: "back-button",
          accessibilityRole: "button",
          accessibilityLabel: "Back to list",
        },
      ],
    };
  }

  function checkoutTree(): HostUiNode {
    return {
      testID: "screen-checkout",
      accessibilityRole: "summary",
      accessibilityLabel: "Checkout",
      children: [
        {
          testID: "email-input",
          accessibilityRole: "textbox",
          accessibilityLabel: "Email",
          props: { value: email },
          accessibilityValue: { text: email },
        },
        {
          testID: "submit-order",
          accessibilityRole: "button",
          accessibilityLabel: "Submit order",
        },
      ],
    };
  }

  const host: DemoHost = {
    getScreen: () => screen,
    getScreenId: () => SCREEN_IDS[screen],
    getEmail: () => email,
    setEmail: (value) => {
      email = value;
    },
    navigate: (next) => {
      screen = next;
      stack = [...stack, next];
    },
    navigateById: (screenId, params) => {
      if (screenId === "orders") {
        screen = "list";
        stack = ["list"];
        orderId = undefined;
        return;
      }
      if (screenId === "order_detail") {
        screen = "detail";
        stack = ["list", "detail"];
        orderId = typeof params?.orderId === "string" ? params.orderId : "1001";
        return;
      }
      if (screenId === "checkout") {
        screen = "checkout";
        stack = ["list", "detail", "checkout"];
      }
    },
    back: () => {
      if (stack.length <= 1) return;
      stack = stack.slice(0, -1);
      screen = stack[stack.length - 1] ?? "list";
    },
    getNavState: () => ({
      screenId: SCREEN_IDS[screen],
      stack: stack.map((s) => SCREEN_IDS[s]),
      params: orderId ? { orderId } : undefined,
      tabs: ["orders", "profile"],
    }),
    createNavigationAdapter: () => ({
      getState: () => host.getNavState(),
      getKnownRoutes: () => ["orders", "order_detail", "checkout", "profile"],
      navigate: async (screenId, params) => {
        host.navigateById(screenId, params);
      },
      back: async () => {
        host.back();
      },
    }),
    getRoot: () => {
      if (screen === "detail") return detailTree();
      if (screen === "checkout") return checkoutTree();
      return listTree();
    },
  };

  return host;
}

/**
 * Wire performAction navigation for the demo host.
 */
export function createDemoPerformAction(host: DemoHost) {
  return async (request: {
    action: "tap" | "scroll" | "input";
    elementId: string;
    text?: string;
  }) => {
    if (request.action === "tap") {
      if (request.elementId === "order-1") host.navigate("detail");
      if (request.elementId === "buy-button") host.navigate("checkout");
      if (request.elementId === "back-button") host.navigate("list");
    }
    if (request.action === "input" && request.elementId === "email-input") {
      host.setEmail(request.text ?? "");
    }
  };
}
