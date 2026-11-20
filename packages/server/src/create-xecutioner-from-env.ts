import {
  type CreateXecutionerOptions,
  createXecutioner,
  type XecutionerInstance,
} from "./create-xecutioner.js";

export type CreateXecutionerFromEnvOptions = Omit<
  CreateXecutionerOptions,
  "enabled" | "port" | "host" | "path"
> & {
  prefix?: string;
  env?: NodeJS.ProcessEnv;
};

function readBool(value: string | undefined, fallback: boolean): boolean {
  if (value === undefined || value === "") {
    return fallback;
  }
  const normalized = value.trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) {
    return true;
  }
  if (["0", "false", "no", "off"].includes(normalized)) {
    return false;
  }
  return fallback;
}

function readInt(value: string | undefined): number | undefined {
  if (value === undefined || value === "") {
    return undefined;
  }
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : undefined;
}

/**
 * Build createXecutioner options from process env (XECUTIONER_* by default).
 */
export function createXecutionerFromEnv(
  options: CreateXecutionerFromEnvOptions = {},
): XecutionerInstance {
  const prefix = options.prefix ?? "XECUTIONER_";
  const env = options.env ?? process.env;

  return createXecutioner({
    ...options,
    enabled: readBool(env[`${prefix}ENABLED`], true),
    port: readInt(env[`${prefix}PORT`]),
    host: env[`${prefix}HOST`] || undefined,
    path: env[`${prefix}PATH`] || undefined,
  });
}
