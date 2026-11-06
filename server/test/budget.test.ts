// #178: the tick counts its D1 calls on the shared budget (src/budget.ts).

import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { countD1, D1_CALLS_PER_TICK, ExternalBudget } from "../src/budget";

describe("countD1", () => {
  it("counts each statement once and a batch as one call", async () => {
    const budget = new ExternalBudget(40, 10);
    const db = countD1(env.DB, budget);

    await db.prepare("SELECT 1 AS one").first();
    await db.prepare("SELECT ? AS one").bind(1).all();
    expect(budget.d1Remaining).toBe(8);

    await db.batch([db.prepare("SELECT 1"), db.prepare("SELECT 2"), db.prepare("SELECT 3")]);
    expect(budget.d1Remaining).toBe(7);
  });

  it("never stops a call past the limit: the jobs look before they start, not halfway", async () => {
    const budget = new ExternalBudget(40, 1);
    const db = countD1(env.DB, budget);
    await db.prepare("SELECT 1").first();
    const row = await db.prepare("SELECT 2 AS two").first<{ two: number }>();
    expect(row?.two).toBe(2);
    expect(budget.d1Remaining).toBe(-1);
  });

  it("leaves room below D1's 50 per invocation for what the jobs do not plan for", () => {
    expect(D1_CALLS_PER_TICK).toBeLessThanOrEqual(40);
  });

  it("is unlimited outside the tick", () => {
    expect(new ExternalBudget().d1Remaining).toBe(Number.POSITIVE_INFINITY);
  });
});
