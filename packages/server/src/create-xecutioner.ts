import type { Server as HttpServer } from "node:http";
import type { Server as HttpsServer } from "node:https";
import type { ChannelListenInfo, ChannelListenOptions } from "./channel.js";
import { XecutionerError } from "./errors.js";
import { createUiPlugin, type UiPlugin, type UiPluginOptions } from "./plugin.js";
import type { PolicyEngine } from "./policy.js";

export type XecutionerLogger = (
  level: "debug" | "info" | "warn" | "error",
  message: string,
  meta?: Record<string, unknown>,
) => void;

export type CreateXecutionerOptions = UiPluginOptions & {
  enabled?: boolean;
  server?: HttpServer | HttpsServer;
  port?: number;
  host?: string;
  path?: string;
  heartbeatIntervalMs?: number;
  logger?: XecutionerLogger;
};

export type XecutionerInstance = {
  plugin: UiPlugin;
  listen: (overrides?: ChannelListenOptions) => Promise<ChannelListenInfo | null>;
  close: () => Promise<void>;
  getListenInfo: () => ChannelListenInfo | null;
  isStarted: () => boolean;
  waitForClient: (sessionId: string, timeoutMs?: number) => Promise<void>;
  listOnlineSessions: () => string[];
  requireOnlineSession: (sessionId?: string) => string;
  isOnline: (sessionId: string) => boolean;
  enabled: boolean;
};

/**
 * Lifecycle wrapper around createUiPlugin for host backends.
 */
export function createXecutioner(options: CreateXecutionerOptions = {}): XecutionerInstance {
  const enabled = options.enabled !== false;
  const logger = options.logger;
  const plugin = createUiPlugin({
    policy: options.policy,
    defaultSessionId: options.defaultSessionId,
    onSessionConnected: (sessionId) => {
      logger?.("info", "session connected", { sessionId });
      options.onSessionConnected?.(sessionId);
    },
    onSessionDisconnected: (sessionId, reason) => {
      logger?.("info", "session disconnected", { sessionId, reason });
      options.onSessionDisconnected?.(sessionId, reason);
    },
  });

  let started = false;

  const guardEnabled = () => {
    if (!enabled) {
      throw new XecutionerError("NOT_STARTED", "Xecutioner is disabled");
    }
  };

  const instance: XecutionerInstance = {
    plugin,
    enabled,

    async listen(overrides) {
      if (!enabled) {
        logger?.("info", "xecutioner disabled; listen skipped");
        return null;
      }
      if (started || plugin.isStarted()) {
        return plugin.getListenInfo();
      }

      const listenOptions: ChannelListenOptions = {
        path: overrides?.path ?? options.path ?? "/xecutioner",
        heartbeatIntervalMs: overrides?.heartbeatIntervalMs ?? options.heartbeatIntervalMs,
        server: overrides?.server ?? options.server,
        port: overrides?.port ?? options.port,
        host: overrides?.host ?? options.host,
      };

      const info = await plugin.listen(listenOptions);
      started = true;
      logger?.("info", "xecutioner listening", {
        port: info.port,
        host: info.host,
        path: info.path,
        attached: info.attached,
      });
      return info;
    },

    async close() {
      if (!plugin.isStarted() && !started) {
        return;
      }
      await plugin.close();
      started = false;
      logger?.("info", "xecutioner closed");
    },

    getListenInfo() {
      return plugin.getListenInfo();
    },

    isStarted() {
      return plugin.isStarted();
    },

    waitForClient(sessionId, timeoutMs) {
      guardEnabled();
      return plugin.waitForClient(sessionId, timeoutMs);
    },

    listOnlineSessions() {
      return plugin.listOnlineSessions();
    },

    requireOnlineSession(sessionId) {
      guardEnabled();
      return plugin.requireOnlineSession(sessionId);
    },

    isOnline(sessionId) {
      return plugin.isOnline(sessionId);
    },
  };

  return instance;
}

export type { PolicyEngine };
