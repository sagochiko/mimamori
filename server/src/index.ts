// Routing. Each route lives in its own module; this file only matches method and path.

import { listCases, resolveRoute } from "./cases";
import { consultRoute } from "./consult";
import { runScheduled } from "./cron";
import { createFamily, createInvite, deleteEverything, joinInvite, leaveFamily, registerApns } from "./families";
import { callbackRoute, connectRoute } from "./gmail";
import { errorResponse, HttpError } from "./http";
import { handleJudgeBatch } from "./judge";
import { siteAssociation } from "./site-association";
import { listSmiles, postSmile, setSmileDeadline, smilePhoto } from "./smiles";
import { smsRoute } from "./sms";

type Handler = (request: Request, env: Env, params: string[], ctx: ExecutionContext) => Promise<Response>;

const routes: Array<[method: string, pattern: RegExp, handler: Handler]> = [
  ["POST", /^\/families$/, (req, env) => createFamily(req, env)],
  ["POST", /^\/invites$/, (req, env) => createInvite(req, env)],
  ["POST", /^\/invites\/([^/]+)\/join$/, (req, env, [code], ctx) => joinInvite(req, env, ctx, code ?? "")],
  ["PUT", /^\/members\/me\/apns$/, (req, env) => registerApns(req, env)],
  ["DELETE", /^\/members\/([^/]+)$/, (req, env, [id]) => leaveFamily(req, env, id ?? "")],
  ["DELETE", /^\/families\/me$/, (req, env) => deleteEverything(req, env)],
  ["POST", /^\/sms\/([^/]+)$/, (req, env, [token], ctx) => smsRoute(req, env, ctx, token ?? "")],
  ["GET", /^\/\.well-known\/apple-app-site-association$/, async () => siteAssociation()],
  ["POST", /^\/consult$/, (req, env) => consultRoute(req, env)],
  ["GET", /^\/cases$/, (req, env) => listCases(req, env)],
  ["POST", /^\/cases\/([^/]+)\/resolve$/, (req, env, [id]) => resolveRoute(req, env, id ?? "")],
  ["POST", /^\/smiles$/, (req, env, _, ctx) => postSmile(req, env, ctx)],
  ["GET", /^\/smiles$/, (req, env) => listSmiles(req, env)],
  ["GET", /^\/smiles\/([^/]+)\/photo$/, (req, env, [id]) => smilePhoto(req, env, id ?? "")],
  ["PUT", /^\/families\/me\/smile-deadline$/, (req, env) => setSmileDeadline(req, env)],
  ["GET", /^\/gmail\/connect$/, (req, env) => connectRoute(req, env)],
  ["GET", /^\/gmail\/callback$/, (req, env) => callbackRoute(req, env)],
];

export async function route(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const { pathname } = new URL(request.url);
  let pathMatched = false;
  for (const [method, pattern, handler] of routes) {
    const match = pattern.exec(pathname);
    if (!match) continue;
    pathMatched = true;
    if (method === request.method) return handler(request, env, match.slice(1), ctx);
  }
  return pathMatched ? errorResponse(405, "method_not_allowed") : errorResponse(404, "not_found");
}

export default {
  async fetch(request, env, ctx): Promise<Response> {
    try {
      return await route(request, env, ctx);
    } catch (error) {
      if (error instanceof HttpError) return errorResponse(error.status, error.code, error.extra);
      // Only the error name: messages could carry request content, which must not reach the logs.
      console.error("unhandled", error instanceof Error ? error.name : typeof error);
      return errorResponse(500, "internal_error");
    }
  },

  async scheduled(controller, env, _ctx): Promise<void> {
    await runScheduled(env, controller.scheduledTime);
  },

  // JUDGE_QUEUE: Claude's judgment over the rule result, then the alert and the pushes (src/judge.ts).
  async queue(batch, env): Promise<void> {
    await handleJudgeBatch(batch, env);
  },
} satisfies ExportedHandler<Env>;
