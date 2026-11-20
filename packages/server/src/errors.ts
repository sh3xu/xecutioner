export type XecutionerErrorCode =
  | "CLIENT_UNAVAILABLE"
  | "NOT_STARTED"
  | "TIMEOUT"
  | "POLICY_DENIED"
  | "UNKNOWN_TOOL"
  | "PLUGIN_CLOSED";

export class XecutionerError extends Error {
  readonly code: XecutionerErrorCode;

  constructor(code: XecutionerErrorCode, message: string, options?: { cause?: unknown }) {
    super(message, options?.cause !== undefined ? { cause: options.cause } : undefined);
    this.name = "XecutionerError";
    this.code = code;
  }

  static is(error: unknown): error is XecutionerError {
    return error instanceof XecutionerError;
  }

  static fromUnknown(
    error: unknown,
    fallback: XecutionerErrorCode = "CLIENT_UNAVAILABLE",
  ): XecutionerError {
    if (error instanceof XecutionerError) {
      return error;
    }
    const message = error instanceof Error ? error.message : String(error);
    if (message === "plugin_closed" || message.startsWith("plugin_closed")) {
      return new XecutionerError("PLUGIN_CLOSED", message, { cause: error });
    }
    if (message.startsWith("Command timed out") || message.includes("timed out")) {
      return new XecutionerError("TIMEOUT", message, { cause: error });
    }
    if (message.startsWith("Unknown tool:")) {
      return new XecutionerError("UNKNOWN_TOOL", message, { cause: error });
    }
    if (message.startsWith("client_unavailable")) {
      return new XecutionerError("CLIENT_UNAVAILABLE", message, { cause: error });
    }
    return new XecutionerError(fallback, message, { cause: error });
  }
}
