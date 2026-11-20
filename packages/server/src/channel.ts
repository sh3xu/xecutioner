import {
  type Command,
  type CommandResult,
  PROTOCOL_VERSION,
  validateCommandResult,
  validateHandshake,
  type WireMessage,
} from "@xecutioner/protocol";
import { WebSocket, WebSocketServer } from "ws";
import type { PendingCommandTracker } from "./pending-tracker.js";
import type { SessionRouter } from "./session-router.js";

export type ChannelListenOptions = {
  port?: number;
  host?: string;
  path?: string;
  heartbeatIntervalMs?: number;
};

export type ChannelEvents = {
  onSessionConnected?: (sessionId: string) => void;
  onSessionDisconnected?: (sessionId: string, reason?: string) => void;
};

function parseMessage(raw: string): WireMessage | null {
  try {
    return JSON.parse(raw) as WireMessage;
  } catch {
    return null;
  }
}

function send(socket: WebSocket, message: WireMessage): void {
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(message));
  }
}

/**
 * WebSocket channel that binds sessions and routes command results.
 */
export class WsChannel {
  private wss: WebSocketServer | null = null;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private readonly socketSessions = new WeakMap<WebSocket, string>();

  constructor(
    private readonly router: SessionRouter,
    private readonly pending: PendingCommandTracker,
    private readonly events: ChannelEvents = {},
  ) {}

  listen(options?: ChannelListenOptions): Promise<{ port: number; host: string }> {
    const port = options?.port ?? 8787;
    const host = options?.host ?? "0.0.0.0";
    const path = options?.path ?? "/xecutioner";
    const heartbeatIntervalMs = options?.heartbeatIntervalMs ?? 15_000;

    return new Promise((resolve, reject) => {
      this.wss = new WebSocketServer({ port, host, path });

      this.wss.on("listening", () => {
        this.heartbeatTimer = setInterval(() => {
          this.wss?.clients.forEach((socket) => {
            if (socket.readyState === WebSocket.OPEN) {
              send(socket, { type: "ping" });
            }
          });
        }, heartbeatIntervalMs);
        resolve({ port, host });
      });

      this.wss.on("error", reject);

      this.wss.on("connection", (socket) => {
        socket.on("message", (data) => {
          const raw = typeof data === "string" ? data : data.toString("utf8");
          this.handleMessage(socket, raw);
        });

        socket.on("close", () => {
          const sessionId = this.socketSessions.get(socket);
          if (sessionId) {
            this.router.unregister(sessionId, socket);
            this.events.onSessionDisconnected?.(sessionId, "socket_closed");
          }
        });
      });
    });
  }

  private handleMessage(socket: WebSocket, raw: string): void {
    const message = parseMessage(raw);
    if (!message || !("type" in message)) {
      return;
    }

    if (message.type === "handshake") {
      const validated = validateHandshake(message);
      if (!validated.ok) {
        send(socket, {
          type: "client_unavailable",
          sessionId: "",
          reason: validated.error,
        });
        socket.close(4001, validated.error);
        return;
      }
      const { sessionId, capabilities } = validated.value;
      this.socketSessions.set(socket, sessionId);
      this.router.register(sessionId, socket, { capabilities });
      send(socket, {
        type: "handshake",
        protocolVersion: PROTOCOL_VERSION,
        sessionId,
        capabilities: [
          "tap",
          "scroll",
          "input",
          "read_screen",
          "wait_for",
          "get_context",
          "navigate",
          "back",
        ],
      });
      this.events.onSessionConnected?.(sessionId);
      return;
    }

    const sessionId = this.socketSessions.get(socket);
    if (sessionId) {
      this.router.touch(sessionId);
    }

    if (message.type === "pong" || message.type === "ping") {
      if (message.type === "ping") {
        send(socket, { type: "pong" });
      }
      return;
    }

    if (message.type === "result") {
      const validated = validateCommandResult(message.result);
      if (validated.ok) {
        this.pending.complete(validated.value);
      }
    }
  }

  sendCommand(sessionId: string, command: Command): boolean {
    const client = this.router.get(sessionId);
    if (!client || client.socket.readyState !== WebSocket.OPEN) {
      return false;
    }
    send(client.socket, { type: "command", command });
    return true;
  }

  async close(): Promise<void> {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
    await new Promise<void>((resolve) => {
      if (!this.wss) {
        resolve();
        return;
      }
      this.wss.close(() => resolve());
    });
    this.wss = null;
  }
}

export type { CommandResult };
