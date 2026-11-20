import type { EvalStepResult } from "./mock-agent.js";

export type EvalTask = {
  id: string;
  name: string;
  description: string;
  /** NOTE: Filled in Phase 2 with richer assertions. */
  successWhen?: (steps: EvalStepResult[]) => boolean;
};

export type EvalMetrics = {
  taskId: string;
  success: boolean;
  steps: number;
  latencyMsTotal: number;
  failureCategories: string[];
};

export const SAMPLE_EVAL_TASKS: EvalTask[] = [
  {
    id: "list-to-detail",
    name: "Open order detail",
    description: "From a list screen, tap an order and land on detail",
    successWhen: (steps) => steps.length >= 2 && steps.every((s) => s.ok),
  },
  {
    id: "form-fill",
    name: "Fill checkout form",
    description: "Enter email and tap submit",
    successWhen: (steps) => steps.some((s) => s.tool === "ui_input") && steps.every((s) => s.ok),
  },
];

/**
 * Compute metrics for a task run. Extensible via optional overrides later.
 */
export function computeEvalMetrics(
  task: EvalTask,
  steps: EvalStepResult[],
  options?: { extraFailures?: string[] },
): EvalMetrics {
  const success = task.successWhen?.(steps) ?? steps.every((s) => s.ok);
  const failureCategories: string[] = steps.filter((s) => !s.ok).map((s) => s.tool);
  if (options?.extraFailures?.length) {
    failureCategories.push(...options.extraFailures);
  }

  return {
    taskId: task.id,
    success,
    steps: steps.length,
    latencyMsTotal: steps.reduce((sum, s) => sum + s.latencyMs, 0),
    failureCategories,
  };
}
