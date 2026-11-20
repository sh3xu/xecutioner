import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { validateCommand, validateCommandResult, validateHandshake } from "@xecutioner/protocol";

const fixturesDir = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "../fixtures/conformance",
);

export function loadFixture(name: string): unknown {
  const raw = readFileSync(path.join(fixturesDir, name), "utf8");
  return JSON.parse(raw);
}

export function runConformanceFixtures(): { name: string; ok: boolean; error?: string }[] {
  const results: { name: string; ok: boolean; error?: string }[] = [];

  const handshake = loadFixture("handshake.valid.json");
  const h = validateHandshake(handshake);
  results.push({
    name: "handshake.valid",
    ok: h.ok,
    error: h.ok ? undefined : h.error,
  });

  const commandMsg = loadFixture("command.tap.json") as { command: unknown };
  const c = validateCommand(commandMsg.command);
  results.push({
    name: "command.tap",
    ok: c.ok,
    error: c.ok ? undefined : c.error,
  });

  const resultMsg = loadFixture("result.ok.json") as { result: unknown };
  const r = validateCommandResult(resultMsg.result);
  results.push({
    name: "result.ok",
    ok: r.ok,
    error: r.ok ? undefined : r.error,
  });

  return results;
}
