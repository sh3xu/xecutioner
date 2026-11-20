# @xecutioner/adapters

Tool exporters and optional UI-tool agent runners for Xecutioner.

## Tool binding

```ts
import { createVercelAiUiTools } from "@xecutioner/adapters/vercel-ai";
import { toOpenAiTools } from "@xecutioner/adapters/openai";
import { toAnthropicTools } from "@xecutioner/adapters/anthropic";

const tools = createVercelAiUiTools(plugin, sessionId);
const { tools: openAiTools, execute } = toOpenAiTools(plugin, sessionId);
```

## Agent runners

```ts
import { createOpenAiAgent } from "@xecutioner/adapters/openai";
import { createAnthropicAgent } from "@xecutioner/adapters/anthropic";
import { runWithTools } from "@xecutioner/adapters";

const agent = createOpenAiAgent(plugin, {
  apiKey: process.env.OPENAI_API_KEY!,
  model: "gpt-4o-mini",
});

const result = await agent.run({
  goal: "Enable dark mode",
  sessionId,
  maxSteps: 12,
  waitTimeoutMs: 10_000,
  onToolCall: (name, args, toolResult) => console.log(name, args, toolResult),
});
```

Uses `UI_CONTROL_SYSTEM_PROMPT` from `@xecutioner/protocol` by default (overridable). Fetch-based; no hard `openai` / Anthropic SDK dependency.

See [docs/backend.md](../../docs/backend.md).
