import { describe, expect, it } from "vitest";
import { runConformanceFixtures } from "./conformance.js";

describe("conformance fixtures", () => {
  it("validates all fixtures", () => {
    const results = runConformanceFixtures();
    expect(results.every((r) => r.ok)).toBe(true);
  });
});
