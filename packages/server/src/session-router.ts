import type { WebSocket } from "ws";

export type SessionClient = {
  sessionId: string;
  socket: WebSocket;
  capabilities: string[];
  connectedAt: number;
  lastSeenAt: number;
};

/**
 * Maps sessionId to the connected client socket.
 */
export class SessionRouter {
  private readonly sessions = new Map<string, SessionClient>();

  register(
    sessionId: string,
    socket: WebSocket,
    options?: { capabilities?: string[] },
  ): SessionClient {
    const existing = this.sessions.get(sessionId);
    if (existing && existing.socket !== socket) {
      try {
        existing.socket.close(4000, "session replaced");
      } catch {
        // NOTE: ignore close errors on stale sockets
      }
    }

    const client: SessionClient = {
      sessionId,
      socket,
      capabilities: options?.capabilities ?? [],
      connectedAt: Date.now(),
      lastSeenAt: Date.now(),
    };
    this.sessions.set(sessionId, client);
    return client;
  }

  touch(sessionId: string): void {
    const client = this.sessions.get(sessionId);
    if (client) {
      client.lastSeenAt = Date.now();
    }
  }

  get(sessionId: string): SessionClient | undefined {
    return this.sessions.get(sessionId);
  }

  isOnline(sessionId: string): boolean {
    const client = this.sessions.get(sessionId);
    if (!client) {
      return false;
    }
    return client.socket.readyState === 1;
  }

  unregister(sessionId: string, socket?: WebSocket): void {
    const client = this.sessions.get(sessionId);
    if (!client) {
      return;
    }
    if (socket && client.socket !== socket) {
      return;
    }
    this.sessions.delete(sessionId);
  }

  list(): SessionClient[] {
    return [...this.sessions.values()];
  }
}
