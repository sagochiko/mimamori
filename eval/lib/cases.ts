// One test case per JSONL line, in the shape fixed by task 4 of docs/plan.md:
// { id, source, sender, domain, text, url, expected_level, is_scam, note }
// The text is data under test. Nothing here acts on what it says.
// No Node APIs here, so the server's Vitest (in workerd) can import this file.

export const SOURCES = ["sms", "gmail", "page", "consult", "document"] as const;
export type CaseSource = (typeof SOURCES)[number];

export interface EvalCase {
  id: string;
  source: CaseSource;
  sender: string | null;
  domain: string | null;
  text: string | null;
  url: string | null;
  expected_level: 1 | 2 | 3 | null;
  is_scam: boolean;
  note: string;
}

function fail(where: string, message: string): never {
  throw new Error(`${where}: ${message}`);
}

function optionalString(value: unknown, field: string, where: string): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") fail(where, `${field} must be a string or null`);
  return value;
}

export function parseCase(value: unknown, where: string): EvalCase {
  if (typeof value !== "object" || value === null || Array.isArray(value)) fail(where, "a case must be a JSON object");
  const v = value as Record<string, unknown>;
  if (typeof v.id !== "string" || v.id.trim() === "") fail(where, "id must be a non-empty string");
  if (!SOURCES.includes(v.source as CaseSource)) fail(where, `source must be one of ${SOURCES.join(", ")}`);
  // Levels are 1, 2, 3 or null. There is no "safe".
  if (![1, 2, 3, null].includes(v.expected_level as never)) fail(where, "expected_level must be 1, 2, 3 or null");
  if (typeof v.is_scam !== "boolean") fail(where, "is_scam must be true or false");
  if (typeof v.note !== "string" || v.note.trim() === "") fail(where, "note must name the source URL or self-written");
  return {
    id: v.id,
    source: v.source as CaseSource,
    sender: optionalString(v.sender, "sender", where),
    domain: optionalString(v.domain, "domain", where),
    text: optionalString(v.text, "text", where),
    url: optionalString(v.url, "url", where),
    expected_level: v.expected_level as EvalCase["expected_level"],
    is_scam: v.is_scam,
    note: v.note,
  };
}

/** The cases in one JSONL file. Errors name the file and line, never the case text. */
export function parseCases(content: string, fileName: string): EvalCase[] {
  const cases: EvalCase[] = [];
  content.split("\n").forEach((raw, index) => {
    if (raw.trim() === "") return;
    const where = `${fileName}:${index + 1}`;
    let value: unknown;
    try {
      value = JSON.parse(raw);
    } catch {
      fail(where, "not valid JSON");
    }
    cases.push(parseCase(value, where));
  });
  return cases;
}
