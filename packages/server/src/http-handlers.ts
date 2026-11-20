import type { XecutionerInstance } from "./create-xecutioner.js";
import { XecutionerError } from "./errors.js";

export type StatusDto = {
  enabled: boolean;
  started: boolean;
  onlineSessions: string[];
  defaultSessionId?: string;
  listenInfo: {
    port: number | null;
    host: string | null;
    path: string;
    attached: boolean;
  } | null;
};

export type ChatRequestBody = {
  message?: string;
  goal?: string;
  sessionId?: string;
  maxSteps?: number;
  waitTimeoutMs?: number;
};

export type UiControlAgent = {
  run: (input: {
    goal: string;
    sessionId: string;
    maxSteps?: number;
    waitTimeoutMs?: number;
  }) => Promise<{
    answer: string;
    steps: number;
    sessionId: string;
    toolTrace?: Array<{ name: string; args: Record<string, unknown>; result: string }>;
  }>;
};

export type HttpHandlerResult = {
  status: number;
  body: unknown;
};

export function handleStatus(x: XecutionerInstance): HttpHandlerResult {
  const listenInfo = x.getListenInfo();
  const body: StatusDto = {
    enabled: x.enabled,
    started: x.isStarted(),
    onlineSessions: x.listOnlineSessions(),
    defaultSessionId: x.plugin.defaultSessionId,
    listenInfo,
  };
  return { status: 200, body };
}

function mapErrorStatus(error: XecutionerError): number {
  switch (error.code) {
    case "NOT_STARTED":
      return 503;
    case "CLIENT_UNAVAILABLE":
      return 409;
    case "TIMEOUT":
      return 408;
    case "POLICY_DENIED":
      return 403;
    case "UNKNOWN_TOOL":
      return 400;
    case "PLUGIN_CLOSED":
      return 503;
    default:
      return 500;
  }
}

/**
 * Framework-agnostic chat handler. Auth / i18n stay in the host.
 */
export async function handleChat(options: {
  xecutioner: XecutionerInstance;
  agent: UiControlAgent;
  body: ChatRequestBody;
}): Promise<HttpHandlerResult> {
  const { xecutioner, agent, body } = options;

  try {
    if (!xecutioner.enabled) {
      throw new XecutionerError("NOT_STARTED", "Xecutioner is disabled");
    }

    const goal = (body.goal ?? body.message ?? "").trim();
    if (!goal) {
      return {
        status: 400,
        body: { error: { code: "INVALID_BODY", message: "goal or message is required" } },
      };
    }

    const sessionId =
      body.sessionId ??
      xecutioner.plugin.defaultSessionId ??
      (() => {
        throw new XecutionerError(
          "CLIENT_UNAVAILABLE",
          "sessionId is required when defaultSessionId is not set",
        );
      })();

    const result = await agent.run({
      goal,
      sessionId,
      maxSteps: body.maxSteps,
      waitTimeoutMs: body.waitTimeoutMs,
    });

    return { status: 200, body: result };
  } catch (error) {
    if (XecutionerError.is(error)) {
      return {
        status: mapErrorStatus(error),
        body: { error: { code: error.code, message: error.message } },
      };
    }
    const message = error instanceof Error ? error.message : String(error);
    return {
      status: 500,
      body: { error: { code: "INTERNAL", message } },
    };
  }
}
