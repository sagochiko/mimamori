// The judges' tour (#100) plays the fake-police consultation on the iPhone instead of calling
// POST /consult. Its lines are copied into ios/Core/Sources/MimamoriCore/DemoTour.swift; this test
// reads that file and runs her words through the server's own judgment, so the tour cannot drift
// from what her phone and the family's would really show.

import { describe, expect, it } from "vitest";
import swift from "../../ios/Core/Sources/MimamoriCore/DemoTour.swift?raw";
import { judgeConsult } from "../src/consult-judge";

/** The string literal assigned to `public static let <name>`. */
function literal(name: string): string {
  const match = new RegExp(`public static let ${name} = "([^"]*)"`).exec(swift);
  if (!match?.[1]) throw new Error(`DemoTour.${name} not found`);
  return match[1];
}

/** The array of string literals assigned to `public static let <name>`. */
function literals(name: string): string[] {
  const match = new RegExp(`public static let ${name} = \\[([^\\]]*)\\]`).exec(swift);
  if (!match?.[1]) throw new Error(`DemoTour.${name} not found`);
  return [...match[1].matchAll(/"([^"]*)"/g)].map((m) => m[1] ?? "");
}

describe("DemoTour.swift matches the server's fake-police judgment", () => {
  it("has her words judged as the fake-police script, with the same answer, line, and reasons", async () => {
    const judged = await judgeConsult(literal("herWords"), [], async () => null);
    expect(judged.script).toBe(true);
    expect(judged.level).toBe(1);
    expect(judged.reply).toBe(literal("answer"));
    expect(judged.summary).toBe(literal("topic"));
    expect(judged.reasons).toEqual(literals("reasons"));
    expect(judged.toFamily).toBe(true);
  });
});
