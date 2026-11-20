/**
 * NOTE: Regenerates lib/src/protocol/generated_types.g.dart from the shared
 * JSON Schema. The hand-written types.dart remains the runtime source until
 * a full codegen pass replaces it; this script emits a parity checklist file.
 */
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const schemaPath = path.join(root, "../../protocol/schemas/protocol.json");
const outDir = path.join(root, "../lib/src/protocol");
const outFile = path.join(outDir, "generated_types.g.dart");

const schema = JSON.parse(await readFile(schemaPath, "utf8"));
const defs = Object.keys(schema.$defs ?? {});

const lines = [
  "// GENERATED CODE - DO NOT MODIFY BY HAND",
  "// NOTE: Generated from packages/protocol/schemas/protocol.json",
  "// Run: node packages/flutter/scripts/generate_dart_types.mjs",
  "",
  "/// Schema definition names that must stay in sync with types.dart.",
  "const List<String> protocolSchemaDefs = [",
  ...defs.map((name) => `  '${name}',`),
  "];",
  "",
  `const String protocolSchemaVersion = '${schema.$defs?.ProtocolVersion?.const ?? "0.1.0"}';`,
  "",
];

await mkdir(outDir, { recursive: true });
await writeFile(outFile, `${lines.join("\n")}\n`, "utf8");
console.log(`Generated ${outFile} (${defs.length} defs)`);
