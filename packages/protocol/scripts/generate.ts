import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { compile } from "json-schema-to-typescript";

const root = path.dirname(fileURLToPath(import.meta.url));
const schemaPath = path.join(root, "../schemas/protocol.json");
const outDir = path.join(root, "../src/generated");
const outFile = path.join(outDir, "types.ts");

const schema = JSON.parse(await readFile(schemaPath, "utf8"));

const bundle = {
  $schema: schema.$schema,
  $id: schema.$id,
  title: "XecutionerWire",
  description: schema.description,
  $defs: schema.$defs,
  oneOf: Object.keys(schema.$defs).map((name) => ({
    $ref: `#/$defs/${name}`,
  })),
};

const generated = await compile(bundle, "XecutionerWire", {
  bannerComment: [
    "/* eslint-disable */",
    "/**",
    " * NOTE: Generated from schemas/protocol.json — do not edit by hand.",
    " * Run `pnpm generate` in @xecutioner/protocol to regenerate.",
    " */",
  ].join("\n"),
  additionalProperties: false,
  unreachableDefinitions: true,
  style: { semi: true, singleQuote: false },
});

await mkdir(outDir, { recursive: true });
await writeFile(outFile, `${generated}\n`, "utf8");
console.log(`Generated ${outFile}`);
