import {
  buildCommandResult,
  type Command,
  type CommandResult,
  type UiToolName,
} from "@xecutioner/protocol";
import { type ChannelListenInfo, type ChannelListenOptions, WsChannel } from "./channel.js";
import { XecutionerError } from "./errors.js";
import { PendingCommandTracker } from "./pending-tracker.js";
import { createAllowAllPolicy, isRateLimitPolicy, type PolicyEngine } from "./policy.js";
import { SessionRouter } from "./session-router.js";
import {
  formatToolResultForModel,
  invokeUiTool,
  listToolDefinitions,
  type ToolInvokeArgs,
  type ToolInvokeResult,
} from "./tools.js";

export type UiPluginOptions = {
  policy?: PolicyEngine;
  defaultSessionId?: string;
  onSessionConnected?: (sessionId: string) => void;
  onSessionDisconnected?: (sessionId: string, reason?: string) => void;
};

export type UiPlugin = {
  listen: (options?: ChannelListenOptions) => Promise<ChannelListenInfo>;
  close: () => Promise<void>;
  isStarted: () => boolean;
  getListenInfo: () => ChannelListenInfo | null;
  isOnline: (sessionId: string) => boolean;
  listOnlineSessions: () => string[];
  requireOnlineSession: (sessionId?: string) => string;
  waitForClient: (sessionId: string, timeoutMs?: number) => Promise<void>;
  dispatch: (sessionId: string, command: Command) => Promise<CommandResult>;
  invokeTool: (
    sessionId: string,
    name: UiToolName,
    args: ToolInvokeArgs,
    options?: { timeoutMs?: number },
  ) => Promise<ToolInvokeResult>;
  listTools: typeof listToolDefinitions;
  formatResult: typeof formatToolResultForModel;
  defaultSessionId?: string;
  router: SessionRouter;
  pending: PendingCommandTracker;
};

type SessionWaiter = {
  sessionId: string;
  resolve: () => void;
  reject: (error: XecutionerError) => void;
  timer: ReturnType<typeof setTimeout>;
};

/**
 * Create the backend UI control plugin.
 */
export function createUiPlugin(options?: UiPluginOptions): UiPlugin {
  const router = new SessionRouter();
  const pending = new PendingCommandTracker();
  const policy = options?.policy ?? createAllowAllPolicy();
  const waiters = new Set<SessionWaiter>();
  const defaultSessionId = options?.defaultSessionId;

  const notifyConnected = (sessionId: string) => {
    for (const waiter of [...waiters]) {
      if (waiter.sessionId === sessionId) {
        clearTimeout(waiter.timer);
        waiters.delete(waiter);
        waiter.resolve();
      }
    }
    options?.onSessionConnected?.(sessionId);
  };

  const channel = new WsChannel(router, pending, {
    onSessionConnected: notifyConnected,
    onSessionDisconnected: (sessionId, reason) => {
      pending.failAll(
        new XecutionerError(
          "CLIENT_UNAVAILABLE",
          `client_unavailable:${sessionId}:${reason ?? ""}`,
        ),
      );
      options?.onSessionDisconnected?.(sessionId, reason);
    },
  });

  const plugin: UiPlugin = {
    router,
    pending,
    defaultSessionId,
    listTools: listToolDefinitions,
    formatResult: formatToolResultForModel,

    listen(listenOptions) {
      return channel.listen(listenOptions);
    },

    close() {
      for (const waiter of waiters) {
        clearTimeout(waiter.timer);
        waiter.reject(new XecutionerError("PLUGIN_CLOSED", "plugin_closed"));
      }
      waiters.clear();
      pending.failAll(new XecutionerError("PLUGIN_CLOSED", "plugin_closed"));
      return channel.close();
    },

    isStarted() {
      return channel.isStarted();
    },

    getListenInfo() {
      return channel.getListenInfo();
    },

    isOnline(sessionId) {
      return router.isOnline(sessionId);
    },

    listOnlineSessions() {
      return router
        .list()
        .filter((client) => router.isOnline(client.sessionId))
        .map((c) => c.sessionId);
    },

    requireOnlineSession(sessionId) {
      const id = sessionId ?? defaultSessionId;
      if (!id) {
        throw new XecutionerError(
          "CLIENT_UNAVAILABLE",
          "sessionId is required when defaultSessionId is not set",
        );
      }
      if (!router.isOnline(id)) {
        throw new XecutionerError("CLIENT_UNAVAILABLE", `No connected client for session ${id}`);
      }
      return id;
    },

    waitForClient(sessionId, timeoutMs = 10_000) {
      if (router.isOnline(sessionId)) {
        return Promise.resolve();
      }

      return new Promise<void>((resolve, reject) => {
        const waiter: SessionWaiter = {
          sessionId,
          resolve,
          reject,
          timer: setTimeout(() => {
            waiters.delete(waiter);
            reject(
              new XecutionerError(
                "TIMEOUT",
                `Timed out waiting for client session ${sessionId} after ${timeoutMs}ms`,
              ),
            );
          }, timeoutMs),
        };
        waiters.add(waiter);

        // NOTE: client may have connected between the isOnline check and waiter registration
        if (router.isOnline(sessionId)) {
          clearTimeout(waiter.timer);
          waiters.delete(waiter);
          resolve();
        }
      });
    },

    async dispatch(sessionId, command) {
      const decision = await policy.authorize(sessionId, command);
      const rateLimited = isRateLimitPolicy(policy);
      if (!decision.allow) {
        return buildCommandResult(command.callId, {
          errorCode: "blocked_by_policy",
          errorMessage: decision.reason,
        });
      }

      if (!router.isOnline(sessionId)) {
        if (rateLimited) {
          policy.end(sessionId);
        }
        return buildCommandResult(command.callId, {
          errorCode: "client_unavailable",
          errorMessage: `No connected client for session ${sessionId}`,
        });
      }

      const resultPromise = pending.track(command);

      const sent = channel.sendCommand(sessionId, command);
      if (!sent) {
        if (rateLimited) {
          policy.end(sessionId);
        }
        pending.fail(
          command.callId,
          new XecutionerError(
            "CLIENT_UNAVAILABLE",
            `Failed to send command to session ${sessionId}`,
          ),
        );
        return buildCommandResult(command.callId, {
          errorCode: "client_unavailable",
          errorMessage: `Failed to send command to session ${sessionId}`,
        });
      }

      try {
        return await resultPromise;
      } catch (error) {
        const typed = XecutionerError.fromUnknown(error);
        const errorCode = typed.code === "TIMEOUT" ? "timeout" : "client_unavailable";
        return buildCommandResult(command.callId, {
          errorCode,
          errorMessage: typed.message,
        });
      } finally {
        if (rateLimited) {
          policy.end(sessionId);
        }
      }
    },

    invokeTool(sessionId, name, args, invokeOptions) {
      return invokeUiTool(plugin, sessionId, name, args, invokeOptions);
    },
  };

  return plugin;
}
