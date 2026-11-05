// Task 13 "毎朝の笑顔" in docs/plan.md: sending smiles and one-line replies, seeing them only inside
// the family, and the quiet notice when the protected member's smile has not come by the deadline.

import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { http, HttpResponse } from "msw";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { jstDate } from "../src/cron";
import worker from "../src/index";
import { resetApnsJwtCache } from "../src/push";
import { ExternalBudget } from "../src/budget";
import { MAX_PHOTO_BYTES, notifyMissedSmiles, SMILE_NOTES } from "../src/smiles";
import { call, createFamily, invite, join, type Created } from "./helpers";
import { network } from "./network";

const SANDBOX = "https://api.sandbox.push.apple.com";
const HOUR = 3600_000;
const JST = 9 * HOUR;

/** A tiny stand-in for a JPEG: the start-of-image marker and a few bytes. Never a real photo. */
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 0xff, 0xd9]);
const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));

let pushEnv: Env;

beforeAll(async () => {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
  ])) as CryptoKeyPair;
  const der = (await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer;
  const key = btoa(String.fromCharCode(...new Uint8Array(der)));
  pushEnv = { ...env, APNS_KEY_P8: `-----BEGIN PRIVATE KEY-----\n${key}\n-----END PRIVATE KEY-----` };
});

interface Sent {
  token: string;
  body: string;
  aps: Record<string, unknown>;
}
let sent: Sent[];

beforeEach(() => {
  resetApnsJwtCache();
  sent = [];
  network.use(
    http.post(`${SANDBOX}/3/device/:token`, async ({ request, params }) => {
      const payload = (await request.json()) as { aps: { alert: { body: string } } & Record<string, unknown> };
      sent.push({ token: String(params.token), body: payload.aps.alert.body, aps: payload.aps });
      return new HttpResponse(null, { status: 200 });
    }),
  );
});

interface Joined {
  memberId: string;
  deviceKey: string;
}

async function joinAs(owner: Created, role: "protected" | "family", name: string): Promise<Joined> {
  const { code } = await invite(owner.deviceKey);
  const res = await join(code, role, name);
  return (await res.json()) as Joined;
}

/** Registers a fresh 64-hex device token and returns it. Every family in this file shares one database. */
async function apns(deviceKey: string): Promise<string> {
  const token = [...crypto.getRandomValues(new Uint8Array(32))].map((b) => b.toString(16).padStart(2, "0")).join("");
  const res = await call("PUT", "/members/me/apns", { deviceKey, body: { token, env: "sandbox" } });
  expect(res.status).toBe(204);
  return token;
}

/** A family of three, each with a device token: 作者 (family), 母 (protected), 妹 (family). */
async function threeOfUs() {
  const owner = await createFamily("作者");
  const mother = await joinAs(owner, "protected", "母");
  const sister = await joinAs(owner, "family", "妹");
  const tok = {
    owner: await apns(owner.deviceKey),
    mother: await apns(mother.deviceKey),
    sister: await apns(sister.deviceKey),
  };
  return { owner, mother, sister, tok };
}

async function post(deviceKey: string, body: unknown, e: Env = env): Promise<Response> {
  return call("POST", "/smiles", { deviceKey, body, env: e });
}

interface SmileOut {
  id: string;
  memberId: string;
  displayName: string;
  role: string;
  score: number | null;
  note: string | null;
  hasPhoto: boolean;
  createdAt: string;
}

describe("POST /smiles and GET /smiles", () => {
  it("lets anyone in the family send a smile and shows everyone's, newest first, with names", async () => {
    const { owner, mother, sister } = await threeOfUs();

    const fromMother = await post(mother.deviceKey, { photo: b64(JPEG), score: 0.8 });
    expect(fromMother.status).toBe(201);
    const fromSister = await post(sister.deviceKey, { photo: b64(JPEG), score: 0.7 });
    expect(fromSister.status).toBe(201);
    const fromOwner = await post(owner.deviceKey, { note: "おはよう" });
    expect(fromOwner.status).toBe(201);

    for (const key of [owner.deviceKey, mother.deviceKey, sister.deviceKey]) {
      const res = await call("GET", "/smiles", { deviceKey: key });
      expect(res.status).toBe(200);
      const { smiles, deadlineHour } = (await res.json()) as { smiles: SmileOut[]; deadlineHour: number };
      expect(deadlineHour).toBe(9);
      expect(smiles.map((s) => [s.displayName, s.role, s.hasPhoto, s.note])).toEqual([
        ["作者", "family", false, "おはよう"],
        ["妹", "family", true, null],
        ["母", "protected", true, null],
      ]);
      expect(smiles[2]?.score).toBe(0.8);
      expect(smiles[2]?.memberId).toBe(mother.memberId);
      expect(Number.isNaN(Date.parse(smiles[0]?.createdAt ?? ""))).toBe(false);
    }
  });

  it("never lists another family's smiles", async () => {
    const ours = await createFamily("作者");
    const theirs = await createFamily("よその人");
    expect((await post(theirs.deviceKey, { photo: b64(JPEG) })).status).toBe(201);

    const res = await call("GET", "/smiles", { deviceKey: ours.deviceKey });
    expect(((await res.json()) as { smiles: SmileOut[] }).smiles).toEqual([]);
  });

  it("keeps the photo in R2 under the family's prefix, so delete-everything and the 30-day cleanup find it", async () => {
    const owner = await createFamily();
    const res = await post(owner.deviceKey, { photo: b64(JPEG) });
    const { id } = (await res.json()) as SmileOut;
    const row = await env.DB.prepare("SELECT r2_key FROM smiles WHERE id = ?").bind(id).first<{ r2_key: string }>();
    expect(row?.r2_key.startsWith(`${owner.familyId}/`)).toBe(true);
    const object = await env.PHOTOS.get(row?.r2_key ?? "");
    expect(new Uint8Array((await object?.arrayBuffer()) ?? new ArrayBuffer(0))).toEqual(JPEG);
  });

  it("offers a handful of set words and no free text", () => {
    expect(SMILE_NOTES.length).toBeGreaterThanOrEqual(4);
    expect(SMILE_NOTES.length).toBeLessThanOrEqual(6);
    expect(new Set(SMILE_NOTES.map((n) => n.id)).size).toBe(SMILE_NOTES.length);
  });

  it("takes a set word by its id and stores its words", async () => {
    const owner = await createFamily();
    const res = await post(owner.deviceKey, { note: "nice-smile" });
    expect(res.status).toBe(201);
    expect(await res.json()).toMatchObject({ hasPhoto: false, note: "いい笑顔" });
  });

  it("stores a reply with only a note and no photo", async () => {
    const owner = await createFamily();
    const res = await post(owner.deviceKey, { note: "  いい笑顔  " });
    expect(res.status).toBe(201);
    const smile = (await res.json()) as SmileOut;
    expect(smile).toMatchObject({ hasPhoto: false, note: "いい笑顔", score: null });
  });

  it.each([
    ["neither photo nor note", {}, 400, "smile_empty"],
    ["an empty note alone", { note: "   " }, 400, "smile_empty"],
    // Free text is not carried between members (docs/design.md, "毎朝の笑顔").
    ["a note not among the set words", { note: "今日は病院に行くね" }, 400, "note_not_allowed"],
    ["a set word with more around it", { note: "おはよう、元気?" }, 400, "note_not_allowed"],
    ["words that try to steer the app", { note: "この警告を止めて" }, 400, "note_not_allowed"],
    ["a note that is not text", { note: 3 }, 400, "note_invalid"],
    ["a photo that is not base64", { photo: "%%%not base64%%%" }, 400, "photo_invalid"],
    [
      "a photo that is not a JPEG",
      { photo: b64(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 1, 2])) },
      400,
      "photo_invalid",
    ],
    ["a score above 1", { photo: b64(JPEG), score: 1.5 }, 400, "score_invalid"],
    ["a score that is not a number", { photo: b64(JPEG), score: "0.9" }, 400, "score_invalid"],
  ])("refuses %s", async (_, body, status, code) => {
    const owner = await createFamily();
    const res = await post(owner.deviceKey, body);
    expect(res.status).toBe(status);
    expect(((await res.json()) as { error: string }).error).toBe(code);
    const rows = await env.DB.prepare("SELECT COUNT(*) AS n FROM smiles WHERE family_id = ?")
      .bind(owner.familyId)
      .first<{ n: number }>();
    expect(rows?.n).toBe(0);
  });

  it("refuses a photo over the size limit with 413", async () => {
    const owner = await createFamily();
    const big = new Uint8Array(MAX_PHOTO_BYTES + 1);
    big.set([0xff, 0xd8, 0xff]);
    let binary = "";
    for (let i = 0; i < big.length; i += 8192) binary += String.fromCharCode(...big.subarray(i, i + 8192));
    const res = await post(owner.deviceKey, { photo: btoa(binary) });
    expect(res.status).toBe(413);
    expect(await r2CountFor(owner.familyId)).toBe(0);
  });

  it("leaves no photo in R2 when the row cannot be written", async () => {
    const owner = await createFamily();
    const failing = {
      ...env,
      DB: new Proxy(env.DB, {
        get(target, key) {
          if (key === "prepare") {
            return (sql: string) => {
              if (sql.startsWith("INSERT INTO smiles")) throw new Error("d1 down");
              return target.prepare(sql);
            };
          }
          const value = Reflect.get(target, key) as unknown;
          return typeof value === "function" ? (value as (...a: unknown[]) => unknown).bind(target) : value;
        },
      }),
    } as Env;
    const res = await post(owner.deviceKey, { photo: b64(JPEG) }, failing);
    expect(res.status).toBe(500);
    expect(await r2CountFor(owner.familyId)).toBe(0);
  });

  it("needs a device key", async () => {
    expect((await call("GET", "/smiles")).status).toBe(401);
    expect((await call("POST", "/smiles", { body: { note: "おはよう" } })).status).toBe(401);
  });

  it("tells everyone else in the family quietly, never the sender", async () => {
    const { mother, tok } = await threeOfUs();
    const res = await post(mother.deviceKey, { photo: b64(JPEG), score: 0.9 }, pushEnv);
    expect(res.status).toBe(201);

    expect(sent.map((s) => s.token).sort()).toEqual([tok.owner, tok.sister].sort());
    for (const s of sent) {
      expect(s.body).toContain("母");
      expect(s.aps.sound).toBeUndefined();
      expect(s.aps["interruption-level"]).toBe("passive");
    }
  });

  it("tells the protected member when the family replies with a note", async () => {
    const { owner, tok } = await threeOfUs();
    await post(owner.deviceKey, { note: "おはよう" }, pushEnv);
    expect(sent.map((s) => s.token).sort()).toEqual([tok.mother, tok.sister].sort());
    expect(sent[0]?.body).toContain("おはよう");
    expect(sent[0]?.body).toContain("作者");
  });
});

async function r2CountFor(familyId: string): Promise<number> {
  return (await env.PHOTOS.list({ prefix: `${familyId}/` })).objects.length;
}

describe("GET /smiles/{id}/photo", () => {
  it("serves the photo to anyone in the same family", async () => {
    const { owner, mother, sister } = await threeOfUs();
    const { id } = (await (await post(mother.deviceKey, { photo: b64(JPEG) })).json()) as SmileOut;

    for (const key of [owner.deviceKey, mother.deviceKey, sister.deviceKey]) {
      const res = await call("GET", `/smiles/${id}/photo`, { deviceKey: key });
      expect(res.status).toBe(200);
      expect(res.headers.get("Content-Type")).toBe("image/jpeg");
      expect(res.headers.get("Cache-Control")).toContain("private");
      expect(new Uint8Array(await res.arrayBuffer())).toEqual(JPEG);
    }
  });

  it("answers 403 to another family's device key", async () => {
    const ours = await createFamily("作者");
    const theirs = await createFamily("よその人");
    const { id } = (await (await post(ours.deviceKey, { photo: b64(JPEG) })).json()) as SmileOut;

    const res = await call("GET", `/smiles/${id}/photo`, { deviceKey: theirs.deviceKey });
    expect(res.status).toBe(403);
    // Nothing of the photo in the refusal.
    expect(await res.text()).not.toContain(b64(JPEG));
  });

  it("answers 401 without a key, and 404 for an unknown smile or a reply without a photo", async () => {
    const owner = await createFamily();
    const { id } = (await (await post(owner.deviceKey, { photo: b64(JPEG) })).json()) as SmileOut;
    expect((await call("GET", `/smiles/${id}/photo`)).status).toBe(401);
    expect((await call("GET", `/smiles/${crypto.randomUUID()}/photo`, { deviceKey: owner.deviceKey })).status).toBe(
      404,
    );
    const note = (await (await post(owner.deviceKey, { note: "おはよう" })).json()) as SmileOut;
    expect((await call("GET", `/smiles/${note.id}/photo`, { deviceKey: owner.deviceKey })).status).toBe(404);
  });
});

describe("PUT /families/me/smile-deadline", () => {
  it("lets a family member change the hour, which GET /smiles then shows", async () => {
    const owner = await createFamily();
    const res = await call("PUT", "/families/me/smile-deadline", { deviceKey: owner.deviceKey, body: { hour: 10 } });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ deadlineHour: 10 });
    const list = (await (await call("GET", "/smiles", { deviceKey: owner.deviceKey })).json()) as {
      deadlineHour: number;
    };
    expect(list.deadlineHour).toBe(10);
  });

  it.each([4, 13, 9.5, "9", null])("refuses the hour %s", async (hour) => {
    const owner = await createFamily();
    const res = await call("PUT", "/families/me/smile-deadline", { deviceKey: owner.deviceKey, body: { hour } });
    expect(res.status).toBe(400);
  });

  it("is not for the protected member, whose screen has no settings", async () => {
    const owner = await createFamily();
    const mother = await joinAs(owner, "protected", "母");
    const res = await call("PUT", "/families/me/smile-deadline", { deviceKey: mother.deviceKey, body: { hour: 10 } });
    expect(res.status).toBe(403);
  });
});

/** Epoch ms of the given JST wall-clock time on 2026-11-10 plus `days`. */
function jstAt(hour: number, minute = 0, days = 0): number {
  return Date.UTC(2026, 10, 10 + days, hour, minute) - JST;
}

async function tick(scheduledTime: number): Promise<void> {
  const ctx = createExecutionContext();
  await worker.scheduled(createScheduledController({ scheduledTime, cron: "*/5 * * * *" }), pushEnv, ctx);
  await waitOnExecutionContext(ctx);
}

/** The family's members as if they joined well before the days these tests look at. */
async function joinedLongAgo(familyId: string): Promise<void> {
  await env.DB.prepare("UPDATE members SET created_at = ? WHERE family_id = ?")
    .bind(jstAt(0, 0, -10), familyId)
    .run();
}

async function smileAt(familyId: string, memberId: string, at: number): Promise<void> {
  await env.DB.prepare(
    "INSERT INTO smiles (id, family_id, member_id, r2_key, score, created_at) VALUES (?, ?, ?, ?, 0.9, ?)",
  )
    .bind(crypto.randomUUID(), familyId, memberId, `${familyId}/smiles/x.jpg`, at)
    .run();
}

/** Only this test's family: other files' families are in the same database. */
function to(tokens: string[]): (s: Sent) => boolean {
  return (s) => tokens.includes(s.token);
}

describe("the quiet notice when the protected member's smile has not come", () => {
  it("gives the JST date of a moment", () => {
    expect(jstDate(jstAt(0, 0))).toBe("2026-11-10");
    expect(jstDate(jstAt(23, 59))).toBe("2026-11-10");
    expect(jstDate(jstAt(0, 0, 1))).toBe("2026-11-11");
  });

  it("tells the family members, not the protected one, once a day after the deadline", async () => {
    const { owner, tok } = await threeOfUs();
    await joinedLongAgo(owner.familyId);
    const ours = to([tok.owner, tok.sister, tok.mother]);

    await tick(jstAt(8, 55));
    expect(sent.filter(ours)).toEqual([]);

    await tick(jstAt(9, 0));
    const first = sent.filter(ours);
    expect(first.map((s) => s.token).sort()).toEqual([tok.owner, tok.sister].sort());
    for (const s of first) {
      expect(s.body).toContain("母");
      expect(s.aps.sound).toBeUndefined();
      expect(s.aps["interruption-level"]).toBe("passive");
    }

    await tick(jstAt(9, 5));
    await tick(jstAt(13, 0));
    expect(sent.filter(ours)).toHaveLength(2);

    // The next JST day starts over.
    await tick(jstAt(9, 0, 1));
    expect(sent.filter(ours)).toHaveLength(4);
  });

  it("says nothing when the protected member smiled today", async () => {
    const { owner, mother, tok } = await threeOfUs();
    await joinedLongAgo(owner.familyId);
    await smileAt(owner.familyId, mother.memberId, jstAt(6, 30));

    await tick(jstAt(9, 0));
    expect(sent.filter(to([tok.owner, tok.sister, tok.mother]))).toEqual([]);
  });

  it("still tells when only the family smiled today, or her smile was yesterday", async () => {
    const { owner, mother, sister, tok } = await threeOfUs();
    await joinedLongAgo(owner.familyId);
    await smileAt(owner.familyId, sister.memberId, jstAt(7, 0));
    await smileAt(owner.familyId, mother.memberId, jstAt(23, 0, -1));

    await tick(jstAt(9, 0));
    expect(sent.filter(to([tok.owner, tok.sister]))).toHaveLength(2);
  });

  it("follows the hour the family set", async () => {
    const { owner, tok } = await threeOfUs();
    await joinedLongAgo(owner.familyId);
    await call("PUT", "/families/me/smile-deadline", { deviceKey: owner.deviceKey, body: { hour: 11 } });
    const ours = to([tok.owner, tok.sister]);

    await tick(jstAt(9, 0));
    await tick(jstAt(10, 55));
    expect(sent.filter(ours)).toEqual([]);
    await tick(jstAt(11, 0));
    expect(sent.filter(ours)).toHaveLength(2);
  });

  it("still tells when her only word today came without a photo, as her screen does", async () => {
    const { owner, mother, tok } = await threeOfUs();
    await joinedLongAgo(owner.familyId);
    await env.DB.prepare(
      "INSERT INTO smiles (id, family_id, member_id, r2_key, note, created_at) VALUES (?, ?, ?, '', 'おはよう', ?)",
    )
      .bind(crypto.randomUUID(), owner.familyId, mother.memberId, jstAt(7, 0))
      .run();

    await tick(jstAt(9, 0));
    expect(sent.filter(to([tok.owner, tok.sister]))).toHaveLength(2);
  });

  it("gives the day back when the budget could not cover the devices, so a later tick sends", async () => {
    const { owner, tok } = await threeOfUs();
    await joinedLongAgo(owner.familyId);
    const ours = to([tok.owner, tok.sister]);

    await notifyMissedSmiles(pushEnv, jstAt(9, 0), new ExternalBudget(0));
    expect(sent.filter(ours)).toEqual([]);
    const row = await env.DB.prepare("SELECT smile_missed_notified_on AS d FROM families WHERE id = ?")
      .bind(owner.familyId)
      .first<{ d: string | null }>();
    expect(row?.d).toBeNull();

    await tick(jstAt(9, 5));
    expect(sent.filter(ours)).toHaveLength(2);
  });

  it("does nothing for a family without a protected member, or one who joined after today's deadline", async () => {
    const alone = await createFamily("作者");
    const aloneToken = await apns(alone.deviceKey);
    await joinedLongAgo(alone.familyId);

    const late = await createFamily("作者");
    const mother = await joinAs(late, "protected", "母");
    const lateToken = await apns(late.deviceKey);
    await env.DB.prepare("UPDATE members SET created_at = ? WHERE id = ?").bind(jstAt(10, 0), mother.memberId).run();

    await tick(jstAt(10, 30));
    expect(sent.filter(to([aloneToken, lateToken]))).toEqual([]);
  });
});
