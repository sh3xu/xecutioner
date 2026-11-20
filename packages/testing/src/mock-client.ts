import { createUiClient, type HostUiNode, type UiClient } from "@xecutioner/react-native";

export type MockClientOptions = {
  url: string;
  sessionId: string;
  root: HostUiNode;
  screen?: string;
  WebSocketImpl?: typeof WebSocket;
};

/**
 * In-memory host tree wired to a UI client for tests and demos.
 */
export function createMockUiClient(options: MockClientOptions): {
  client: UiClient;
  root: HostUiNode;
  taps: string[];
} {
  const taps: string[] = [];
  const root = options.root;

  const client = createUiClient({
    url: options.url,
    sessionId: options.sessionId,
    WebSocketImpl: options.WebSocketImpl,
    hooks: {
      getRootNode: () => root,
      getScreenMeta: () => ({ screen: options.screen ?? "Mock" }),
      performAction: async ({ action, elementId, text }) => {
        if (action === "tap") {
          taps.push(elementId);
        }
        if (action === "input") {
          const stack: HostUiNode[] = [root];
          while (stack.length) {
            const node = stack.pop();
            if (!node) continue;
            if (node.testID === elementId) {
              node.props = { ...node.props, value: text ?? "" };
              node.accessibilityValue = { text: text ?? "" };
              break;
            }
            if (node.children) stack.push(...node.children);
          }
        }
      },
    },
  });

  return { client, root, taps };
}
