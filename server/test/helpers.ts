import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import worker from "../src/index";

export const HOST = "https://mimamori.test";

// The handler expects an incoming request type; tests build plain requests.
const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

export async function call(
  method: string,
  path: string,
  options: { deviceKey?: string; body?: unknown; env?: Env } = {},
): Promise<Response> {
  const headers = new Headers();
  if (options.deviceKey !== undefined) headers.set("Authorization", `Bearer ${options.deviceKey}`);
  if (options.body !== undefined) headers.set("Content-Type", "application/json");
  const request = new IncomingRequest(`${HOST}${path}`, {
    method,
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, options.env ?? env, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

export interface Created {
  familyId: string;
  memberId: string;
  deviceKey: string;
  familyToken: string;
  role: string;
}

export async function createFamily(displayName = "作者"): Promise<Created> {
  const res = await call("POST", "/families", { body: { display_name: displayName } });
  if (res.status !== 201) throw new Error(`createFamily: ${res.status}`);
  return (await res.json()) as Created;
}

export async function invite(deviceKey: string): Promise<{ code: string; expiresAt: string }> {
  const res = await call("POST", "/invites", { deviceKey });
  if (res.status !== 201) throw new Error(`invite: ${res.status}`);
  return (await res.json()) as { code: string; expiresAt: string };
}

export async function join(
  code: string,
  role: "protected" | "family",
  displayName: string,
): Promise<Response> {
  return call("POST", `/invites/${code}/join`, { body: { role, display_name: displayName } });
}
