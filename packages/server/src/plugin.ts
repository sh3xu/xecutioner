import {
  buildCommandResult,
  type Command,
  type CommandResult,
  type UiToolName,
} from "@xecutioner/protocol";
import { type ChannelListenOptions, WsChannel } from "./channel.js";
import { PendingCommandTracker } from "./pending-tracker.js";
import { createAllowAllPolicy, type PolicyEngine } from "./policy.js";
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
  onSessionConnected?: (sessionId: string) => void;
  onSessionDisconnected?: (sessionId: string, reason?: string) => void;
};

export type UiPlugin = {
  listen: (options?: ChannelListenOptions) => Promise<{ port: number; host: string }>;
  close: () => Promise<void>;
  isOnline: (sessionId: string) => boolean;
  dispatch: (sessionId: string, command: Command) => Promise<CommandResult>;
  invokeTool: (
    sessionId: string,
    name: UiToolName,
    args: ToolInvokeArgs,
    options?: { timeoutMs?: number },
  ) => Promise<ToolInvokeResult>;
  listTools: typeof listToolDefinitions;
  formatResult: typeof formatToolResultForModel;
  router: SessionRouter;
  pending: PendingCommandTracker;
};

/**
 * Create the backend UI control plugin.
 */
export function createUiPlugin(options?: UiPluginOptions): UiPlugin {
  const router = new SessionRouter();
  const pending = new PendingCommandTracker();
  const policy = options?.policy ?? createAllowAllPolicy();
  const channel = new WsChannel(router, pending, {
    onSessionConnected: options?.onSessionConnected,
    onSessionDisconnected: (sessionId, reason) => {
      pending.failAll(new Error(`client_unavailable:${sessionId}:${reason ?? ""}`));
      options?.onSessionDisconnected?.(sessionId, reason);
    },
  });

  const plugin: UiPlugin = {
    router,
    pending,
    listTools: listToolDefinitions,
    formatResult: formatToolResultForModel,

    listen(listenOptions) {
      return channel.listen(listenOptions);
    },

    close() {
      pending.failAll(new Error("plugin_closed"));
      return channel.close();
    },

    isOnline(sessionId) {
      return router.isOnline(sessionId);
    },

    async dispatch(sessionId, command) {
      const decision = await policy.authorize(sessionId, command);
      if (!decision.allow) {
        return buildCommandResult(command.callId, {
          errorCode: "blocked_by_policy",
          errorMessage: decision.reason,
        });
      }

      if (!router.isOnline(sessionId)) {
        return buildCommandResult(command.callId, {
          errorCode: "client_unavailable",
          errorMessage: `No connected client for session ${sessionId}`,
        });
      }

      const resultPromise = pending.track(command);

      const sent = channel.sendCommand(sessionId, command);
      if (!sent) {
        pending.fail(command.callId, new Error(`Failed to send command to session ${sessionId}`));
        return buildCommandResult(command.callId, {
          errorCode: "client_unavailable",
          errorMessage: `Failed to send command to session ${sessionId}`,
        });
      }

      try {
        return await resultPromise;
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        const errorCode = message.startsWith("Command timed out")
          ? "timeout"
          : "client_unavailable";
        return buildCommandResult(command.callId, {
          errorCode,
          errorMessage: message,
        });
      }
    },

    invokeTool(sessionId, name, args, invokeOptions) {
      return invokeUiTool(plugin, sessionId, name, args, invokeOptions);
    },
  };

  return plugin;
}
