import { createServer, type Server as HttpServer, type IncomingMessage } from "node:http";
import type { Server as HttpsServer } from "node:https";
import type { Duplex } from "node:stream";
import { URL } from "node:url";
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

export type ChannelListenInfo = {
  port: number | null;
  host: string | null;
  path: string;
  attached: boolean;
};

export type ChannelListenOptions = {
  port?: number;
  host?: string;
  path?: string;
  heartbeatIntervalMs?: number;
  server?: HttpServer | HttpsServer;
};

export type ChannelEvents = {
  onSessionConnected?: (sessionId: string) => void;
  onSessionDisconnected?: (sessionId: string, reason?: string) => void;
};

type UpgradeServer = HttpServer | HttpsServer;

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

function requestPathname(req: IncomingMessage): string {
  try {
    return new URL(req.url ?? "/", "http://localhost").pathname;
  } catch {
    return "/";
  }
}

/**
 * WebSocket channel that binds sessions and routes command results.
 * Uses noServer + an upgrade handler so it can share an HTTP port without conflicts.
 */
export class WsChannel {
  private wss: WebSocketServer | null = null;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private readonly socketSessions = new WeakMap<WebSocket, string>();
  private listenInfo: ChannelListenInfo | null = null;
  private sharedHttpServer: UpgradeServer | null = null;
  private upgradeHandler: ((req: IncomingMessage, socket: Duplex, head: Buffer) => void) | null =
    null;
  private ownsSharedHttpServer = false;

  constructor(
    private readonly router: SessionRouter,
    private readonly pending: PendingCommandTracker,
    private readonly events: ChannelEvents = {},
  ) {}

  isStarted(): boolean {
    return this.wss !== null;
  }

  getListenInfo(): ChannelListenInfo | null {
    return this.listenInfo;
  }

  listen(options?: ChannelListenOptions): Promise<ChannelListenInfo> {
    if (this.wss) {
      return Promise.reject(new Error("channel already started"));
    }

    const path = options?.path ?? "/xecutioner";
    const heartbeatIntervalMs = options?.heartbeatIntervalMs ?? 15_000;

    this.wss = new WebSocketServer({ noServer: true });
    this.bindConnectionHandlers();

    this.upgradeHandler = (req, socket, head) => {
      if (requestPathname(req) !== path) {
        return;
      }
      this.wss?.handleUpgrade(req, socket, head, (ws) => {
        this.wss?.emit("connection", ws, req);
      });
    };

    if (options?.server) {
      this.sharedHttpServer = options.server;
      this.ownsSharedHttpServer = false;
      this.sharedHttpServer.on("upgrade", this.upgradeHandler);

      const address = options.server.address();
      const port =
        address && typeof address === "object" && "port" in address ? address.port : null;
      const host =
        address && typeof address === "object" && typeof address.address === "string"
          ? address.address
          : null;
      this.listenInfo = { port, host, path, attached: true };
      this.startHeartbeat(heartbeatIntervalMs);
      return Promise.resolve(this.listenInfo);
    }

    const port = options?.port ?? 8787;
    const host = options?.host ?? "0.0.0.0";
    const httpServer = createServer((_req, res) => {
      res.writeHead(404);
      res.end();
    });
    this.sharedHttpServer = httpServer;
    this.ownsSharedHttpServer = true;
    httpServer.on("upgrade", this.upgradeHandler);

    return new Promise((resolve, reject) => {
      httpServer.once("error", reject);
      httpServer.listen(port, host, () => {
        const address = httpServer.address();
        this.listenInfo = {
          port: address && typeof address === "object" ? address.port : port,
          host: address && typeof address === "object" ? address.address || host : host,
          path,
          attached: false,
        };
        this.startHeartbeat(heartbeatIntervalMs);
        resolve(this.listenInfo);
      });
    });
  }

  private startHeartbeat(heartbeatIntervalMs: number): void {
    this.heartbeatTimer = setInterval(() => {
      this.wss?.clients.forEach((socket) => {
        if (socket.readyState === WebSocket.OPEN) {
          send(socket, { type: "ping" });
        }
      });
    }, heartbeatIntervalMs);
  }

  private bindConnectionHandlers(): void {
    if (!this.wss) {
      return;
    }

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

    if (this.sharedHttpServer && this.upgradeHandler) {
      this.sharedHttpServer.off("upgrade", this.upgradeHandler);
    }
    this.upgradeHandler = null;

    await new Promise<void>((resolve) => {
      if (!this.wss) {
        resolve();
        return;
      }
      this.wss.close(() => resolve());
    });
    this.wss = null;

    if (this.ownsSharedHttpServer && this.sharedHttpServer) {
      const server = this.sharedHttpServer;
      await new Promise<void>((resolve, reject) => {
        server.close((error) => (error ? reject(error) : resolve()));
      });
    }
    this.sharedHttpServer = null;
    this.ownsSharedHttpServer = false;
    this.listenInfo = null;
  }
}

export type { CommandResult };
