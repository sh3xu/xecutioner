import {
  CLIENT_CAPABILITIES,
  type Command,
  type CommandResult,
  PROTOCOL_VERSION,
  type Snapshot,
  validateCommand,
  type WireMessage,
} from "@xecutioner/protocol";
import { executeCommand } from "./executors.js";
import type { HostHooks } from "./types.js";

export type UiClientOptions = {
  url: string;
  sessionId: string;
  hooks: HostHooks;
  /** NOTE: Inject WebSocket for tests / React Native polyfills. */
  WebSocketImpl?: typeof WebSocket;
  protocols?: string | string[];
};

export type UiClient = {
  connect: () => Promise<void>;
  disconnect: () => void;
  isConnected: () => boolean;
  getLastSnapshot: () => Snapshot | null;
  /** Execute locally without the network (useful for demos/tests). */
  executeLocal: (command: Command) => Promise<CommandResult>;
};

/**
 * Thin React Native / JS client: handshake, receive commands, return results.
 */
export function createUiClient(options: UiClientOptions): UiClient {
  const WS = options.WebSocketImpl ?? WebSocket;
  let socket: WebSocket | null = null;
  let lastSnapshot: Snapshot | null = null;
  let connected = false;

  const ctx = {
    hooks: options.hooks,
    get lastSnapshot() {
      return lastSnapshot;
    },
    setLastSnapshot(snapshot: Snapshot) {
      lastSnapshot = snapshot;
    },
  };

  async function handleCommand(command: Command): Promise<void> {
    const result = await executeCommand(command, ctx);
    send({ type: "result", result });
  }

  function send(message: WireMessage): void {
    if (socket && socket.readyState === WS.OPEN) {
      socket.send(JSON.stringify(message));
    }
  }

  function onMessage(raw: string): void {
    let message: WireMessage;
    try {
      message = JSON.parse(raw) as WireMessage;
    } catch {
      return;
    }

    if (message.type === "ping") {
      send({ type: "pong" });
      return;
    }

    if (message.type === "command") {
      const validated = validateCommand(message.command);
      if (validated.ok) {
        void handleCommand(validated.value);
      }
    }
  }

  return {
    getLastSnapshot: () => lastSnapshot,

    executeLocal: (command) => executeCommand(command, ctx),

    isConnected: () => connected && !!socket && socket.readyState === WS.OPEN,

    connect: () =>
      new Promise<void>((resolve, reject) => {
        socket = new WS(options.url, options.protocols);

        socket.addEventListener("open", () => {
          send({
            type: "handshake",
            protocolVersion: PROTOCOL_VERSION,
            sessionId: options.sessionId,
            capabilities: [...CLIENT_CAPABILITIES],
            clientInfo: { platform: "react-native" },
          });
        });

        socket.addEventListener("message", (event) => {
          const data =
            typeof event.data === "string" ? event.data : (event.data?.toString?.() ?? "");
          let message: WireMessage | null = null;
          try {
            message = JSON.parse(data) as WireMessage;
          } catch {
            return;
          }
          if (message.type === "handshake") {
            connected = true;
            resolve();
            return;
          }
          onMessage(data);
        });

        socket.addEventListener("error", () => {
          if (!connected) {
            reject(new Error("WebSocket connection failed"));
          }
        });

        socket.addEventListener("close", () => {
          connected = false;
        });
      }),

    disconnect: () => {
      connected = false;
      socket?.close();
      socket = null;
    },
  };
}
