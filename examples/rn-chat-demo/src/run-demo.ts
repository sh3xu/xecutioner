import { toVercelAiTools } from "@xecutioner/adapters/vercel-ai";
import { createAppContextReader, createUiClient } from "@xecutioner/react-native";
import { createUiPlugin } from "@xecutioner/server";
import { computeEvalMetrics, runScriptedAgent, SAMPLE_EVAL_TASKS } from "@xecutioner/testing";
import WebSocket from "ws";
import { createDemoHost, createDemoPerformAction } from "./host-app.js";

const SESSION_ID = "demo-session";
const PORT = 8787;

async function waitForOnline(
  isOnline: () => boolean,
  options?: { timeoutMs?: number },
): Promise<void> {
  const timeoutMs = options?.timeoutMs ?? 5_000;
  const started = Date.now();
  while (!isOnline()) {
    if (Date.now() - started > timeoutMs) {
      throw new Error("Client did not connect in time");
    }
    await new Promise((r) => setTimeout(r, 50));
  }
}

async function main(): Promise<void> {
  const host = createDemoHost();
  const contextReader = createAppContextReader({
    app: {
      name: "Shop",
      description: "Demo commerce app for Xecutioner UI control",
    },
    navigation: host.createNavigationAdapter(),
    screens: [
      {
        id: "orders",
        title: "Orders",
        description: "List of the user's past orders",
      },
      {
        id: "order_detail",
        title: "Order detail",
        description: "One order: items, status, tracking, buy button",
        params: { orderId: "string" },
        reachableFrom: ["orders"],
      },
      {
        id: "checkout",
        title: "Checkout",
        description: "Enter email and submit the order",
        reachableFrom: ["order_detail"],
      },
    ],
  });

  const plugin = createUiPlugin();
  const { port } = await plugin.listen({ port: PORT, host: "127.0.0.1" });
  const url = `ws://127.0.0.1:${port}/xecutioner`;

  const client = createUiClient({
    url,
    sessionId: SESSION_ID,
    WebSocketImpl: WebSocket as unknown as typeof globalThis.WebSocket,
    hooks: {
      getRootNode: () => host.getRoot(),
      getScreenMeta: () => ({ screen: host.getScreenId() }),
      performAction: createDemoPerformAction(host),
      contextReader,
      onAiActing: (acting) => {
        console.log(acting ? "[host] AI is acting" : "[host] AI idle");
      },
    },
  });

  await client.connect();
  await waitForOnline(() => plugin.isOnline(SESSION_ID));

  const tools = toVercelAiTools(plugin, SESSION_ID);
  console.log("Registered UI tools:", Object.keys(tools).join(", "));

  const steps = await runScriptedAgent(plugin, SESSION_ID, [
    { tool: "ui_get_context", args: {} },
    {
      tool: "ui_navigate",
      args: { screenId: "order_detail", params: { orderId: "1001" } },
    },
    { tool: "ui_read_screen", args: {} },
    { tool: "ui_navigate", args: { screenId: "checkout" } },
    { tool: "ui_read_screen", args: {} },
    {
      tool: "ui_input",
      args: { elementId: "email-input", text: "buyer@example.com" },
    },
    { tool: "ui_tap", args: { elementId: "submit-order" } },
    { tool: "ui_get_context", args: {} },
  ]);

  const task = SAMPLE_EVAL_TASKS[0];
  if (!task) {
    throw new Error("SAMPLE_EVAL_TASKS is empty");
  }
  const metrics = computeEvalMetrics(task, steps);

  console.log("\n=== Demo results ===");
  for (const step of steps) {
    console.log(`- ${step.tool}: ${step.ok ? "ok" : "fail"} (${step.latencyMs}ms)`);
  }
  console.log("Final screen:", host.getScreenId());
  console.log("Email:", host.getEmail());
  console.log("Eval:", metrics);

  const success =
    metrics.success &&
    host.getScreen() === "checkout" &&
    host.getEmail() === "buyer@example.com" &&
    steps.every((s) => s.ok);

  client.disconnect();
  await plugin.close();

  if (!success) {
    console.error("Demo task failed");
    process.exitCode = 1;
    return;
  }

  console.log("\nDemo task succeeded (context + navigate path).");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
