// Task 17 "見守りの自己点検" in docs/plan.md (#19): the protected member's iPhone says it is still
// watching, and the family hears when it stops, or when notifications or background refresh are off.

import { env } from "cloudflare:workers";
import { http, HttpResponse } from "msw";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { ExternalBudget } from "../src/budget";
import { JOBS } from "../src/cron";
import { HEARTBEAT_LAPSE_MS, LAPSE_TEXT, watchHeartbeats } from "../src/heartbeat";
import { resetApnsJwtCache } from "../src/push";
import { call, createFamily, invite, join, type Created } from "./helpers";
import { network } from "./network";

const SANDBOX = "https://api.sandbox.push.apple.com";
const HOUR = 3600_000;

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
  return (await (await join(code, role, name)).json()) as Joined;
}

async function apns(deviceKey: string): Promise<string> {
  const token = [...crypto.getRandomValues(new Uint8Array(32))].map((b) => b.toString(16).padStart(2, "0")).join("");
  const res = await call("PUT", "/members/me/apns", { deviceKey, body: { token, env: "sandbox" } });
  expect(res.status).toBe(204);
  return token;
}

/** 作者 (family), 母 (protected), 妹 (family), each with a device token. */
async function threeOfUs() {
  const owner = await createFamily("作者");
  const mother = await joinAs(owner, "protected", "母");
  const sister = await joinAs(owner, "family", "妹");
  const tok = {
    owner: await apns(owner.deviceKey),
    mother: await apns(mother.deviceKey),
    sister: await apns(sister.deviceKey),
  };
  sent = []; // "(名前)が入りました" from the joins
  return { owner, mother, sister, tok };
}

const on = { notifications: true, backgroundRefresh: true };

async function beat(deviceKey: string, body: unknown = on, e: Env = pushEnv): Promise<Response> {
  return call("POST", "/heartbeat", { deviceKey, body, env: e });
}

async function row(memberId: string) {
  return env.DB.prepare(
    `SELECT heartbeat_at, heartbeat_lapse_notified_at, notifications_off, background_refresh_off
       FROM members WHERE id = ?`,
  )
    .bind(memberId)
    .first<Record<string, number | null>>();
}

/** Moves her last heartbeat back by `ms`, as if the iPhone had gone quiet that long ago. */
async function quietFor(memberId: string, ms: number): Promise<number> {
  const at = Date.now() - ms;
  await env.DB.prepare("UPDATE members SET heartbeat_at = ? WHERE id = ?").bind(at, memberId).run();
  return at;
}

describe("POST /heartbeat", () => {
  it("takes the protected member's key and keeps only the server's time", async () => {
    const { mother } = await threeOfUs();
    const before = Date.now();
    const res = await beat(mother.deviceKey);
    expect(res.status).toBe(204);
    const r = await row(mother.memberId);
    expect(r?.heartbeat_at).toBeGreaterThanOrEqual(before);
    expect(r?.heartbeat_at).toBeLessThanOrEqual(Date.now());
    expect(r?.notifications_off).toBe(0);
    expect(r?.background_refresh_off).toBe(0);
    expect(sent).toEqual([]);
  });

  it("ignores a time the device sends: a wrong clock cannot hide a lapse", async () => {
    const { mother } = await threeOfUs();
    const future = Date.now() + 365 * 24 * HOUR;
    expect((await beat(mother.deviceKey, { ...on, at: future })).status).toBe(204);
    expect((await row(mother.memberId))?.heartbeat_at).toBeLessThanOrEqual(Date.now());
  });

  it("keeps nothing else the body carries, such as a free-space number", async () => {
    const { mother } = await threeOfUs();
    expect((await beat(mother.deviceKey, { ...on, freeBytes: 123_456_789 })).status).toBe(204);
    const member = await env.DB.prepare("SELECT * FROM members WHERE id = ?")
      .bind(mother.memberId)
      .first<Record<string, unknown>>();
    expect(Object.values(member ?? {})).not.toContain(123_456_789);
    expect(JSON.stringify(member)).not.toContain("123456789");
  });

  it("refuses a family member's key, a missing key, and bodies that are not two booleans", async () => {
    const { owner, mother } = await threeOfUs();
    expect((await beat(owner.deviceKey)).status).toBe(403);
    expect(((await (await beat(owner.deviceKey)).json()) as { error: string }).error).toBe("protected_only");
    expect((await call("POST", "/heartbeat", { body: on })).status).toBe(401);
    for (const body of [{}, { notifications: true }, { notifications: "yes", backgroundRefresh: true }, { ...on, backgroundRefresh: 1 }]) {
      const res = await beat(mother.deviceKey, body);
      expect(res.status).toBe(400);
      expect(((await res.json()) as { error: string }).error).toBe("heartbeat_invalid");
    }
    expect((await row(mother.memberId))?.heartbeat_at).toBeNull();
  });

  it("tells the family once when notifications are turned off, and again only after they came back on", async () => {
    const { mother, tok } = await threeOfUs();
    await beat(mother.deviceKey);
    await beat(mother.deviceKey, { notifications: false, backgroundRefresh: true });
    await beat(mother.deviceKey, { notifications: false, backgroundRefresh: true });
    expect(sent.map((s) => [s.token, s.body]).sort()).toEqual(
      [
        [tok.owner, "母のiPhoneで、みまもりの通知が切られています"],
        [tok.sister, "母のiPhoneで、みまもりの通知が切られています"],
      ].sort(),
    );
    expect(sent.some((s) => s.token === tok.mother)).toBe(false);

    sent = [];
    await beat(mother.deviceKey);
    expect(sent).toEqual([]);
    expect((await row(mother.memberId))?.notifications_off).toBe(0);
    await beat(mother.deviceKey, { notifications: false, backgroundRefresh: true });
    expect(sent).toHaveLength(2);
  });

  it("tells the family when background refresh is off, apart from notifications", async () => {
    const { mother } = await threeOfUs();
    await beat(mother.deviceKey, { notifications: false, backgroundRefresh: false });
    expect(sent.map((s) => s.body).sort()).toEqual([
      "母のiPhoneで、みまもりの「アプリのバックグラウンド更新」が切られています",
      "母のiPhoneで、みまもりの「アプリのバックグラウンド更新」が切られています",
      "母のiPhoneで、みまもりの通知が切られています",
      "母のiPhoneで、みまもりの通知が切られています",
    ]);
    const r = await row(mother.memberId);
    expect(r?.notifications_off).toBe(1);
    expect(r?.background_refresh_off).toBe(1);
  });

  it("tells the family on the first heartbeat too, when it already says off", async () => {
    const { mother } = await threeOfUs();
    await beat(mother.deviceKey, { notifications: true, backgroundRefresh: false });
    expect(sent).toHaveLength(2);
  });

  it("tries the notice again on the next heartbeat when the budget ran out", async () => {
    const { mother } = await threeOfUs();
    const { recordHeartbeat } = await import("../src/heartbeat");
    const me = { id: mother.memberId, familyId: "", role: "protected" as const, displayName: "母" };
    const fam = await env.DB.prepare("SELECT family_id FROM members WHERE id = ?")
      .bind(mother.memberId)
      .first<{ family_id: string }>();
    me.familyId = fam?.family_id ?? "";
    await recordHeartbeat(pushEnv, me, { notifications: false, backgroundRefresh: true }, Date.now(), new ExternalBudget(0));
    expect(sent).toEqual([]);
    expect((await row(mother.memberId))?.notifications_off).not.toBe(1);
    await beat(mother.deviceKey, { notifications: false, backgroundRefresh: true });
    expect(sent).toHaveLength(2);
  });

  it("is a quiet notice that names no Claude text", async () => {
    const { mother } = await threeOfUs();
    await beat(mother.deviceKey, { notifications: false, backgroundRefresh: true });
    expect(sent[0]?.aps["interruption-level"]).toBe("passive");
    expect(sent[0]?.aps.sound).toBeUndefined();
  });
});

describe("watchHeartbeats", () => {
  it("runs from the 5-minute tick", () => {
    expect(JOBS.find((j) => j.name === "heartbeat-watch")).toMatchObject({ everyMinutes: 5 });
  });

  it("tells the family once after 48 hours without a heartbeat", async () => {
    const { mother, tok } = await threeOfUs();
    await beat(mother.deviceKey);
    await quietFor(mother.memberId, HEARTBEAT_LAPSE_MS - HOUR);
    await watchHeartbeats(pushEnv, Date.now(), new ExternalBudget());
    expect(sent.filter((s) => [tok.owner, tok.sister].includes(s.token))).toEqual([]);

    await quietFor(mother.memberId, HEARTBEAT_LAPSE_MS);
    await watchHeartbeats(pushEnv, Date.now(), new ExternalBudget());
    await watchHeartbeats(pushEnv, Date.now() + HOUR, new ExternalBudget());
    const ours = sent.filter((s) => [tok.owner, tok.sister, tok.mother].includes(s.token));
    expect(ours.map((s) => [s.token, s.body]).sort()).toEqual(
      [
        [tok.owner, "母の見守りが止まっています"],
        [tok.sister, "母の見守りが止まっています"],
      ].sort(),
    );
    expect(LAPSE_TEXT("母")).toBe("母の見守りが止まっています");
  });

  it("stays quiet once she is back, until the next 48-hour gap", async () => {
    const { mother, tok } = await threeOfUs();
    const ours = () => sent.filter((s) => [tok.owner, tok.sister].includes(s.token));
    await beat(mother.deviceKey);
    await quietFor(mother.memberId, HEARTBEAT_LAPSE_MS + HOUR);
    await watchHeartbeats(pushEnv, Date.now(), new ExternalBudget());
    expect(ours()).toHaveLength(2);

    await beat(mother.deviceKey);
    expect((await row(mother.memberId))?.heartbeat_lapse_notified_at).toBeNull();
    await watchHeartbeats(pushEnv, Date.now() + HOUR, new ExternalBudget());
    expect(ours()).toHaveLength(2);

    await quietFor(mother.memberId, HEARTBEAT_LAPSE_MS + HOUR);
    await watchHeartbeats(pushEnv, Date.now(), new ExternalBudget());
    expect(ours()).toHaveLength(4);
  });

  it("never counts a member that has not sent one yet, so older builds do not set it off", async () => {
    const { tok } = await threeOfUs();
    await watchHeartbeats(pushEnv, Date.now() + 365 * 24 * HOUR, new ExternalBudget());
    expect(sent.filter((s) => [tok.owner, tok.sister].includes(s.token))).toEqual([]);
  });

  it("gives the claim back when the budget ran out, so the next tick tells them", async () => {
    const { mother, tok } = await threeOfUs();
    const ours = () => sent.filter((s) => [tok.owner, tok.sister].includes(s.token));
    await beat(mother.deviceKey);
    await quietFor(mother.memberId, HEARTBEAT_LAPSE_MS + HOUR);
    await watchHeartbeats(pushEnv, Date.now(), new ExternalBudget(0));
    expect(ours()).toEqual([]);
    expect((await row(mother.memberId))?.heartbeat_lapse_notified_at).toBeNull();
    await watchHeartbeats(pushEnv, Date.now(), new ExternalBudget());
    expect(ours()).toHaveLength(2);
  });
});
