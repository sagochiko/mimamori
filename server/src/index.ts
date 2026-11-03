// Routing. Each route lives in its own module; this file only matches method and path.

import { createFamily, createInvite, joinInvite, registerApns } from "./families";
import { errorResponse, HttpError } from "./http";

type Handler = (request: Request, env: Env, params: string[]) => Promise<Response>;

const routes: Array<[method: string, pattern: RegExp, handler: Handler]> = [
  ["POST", /^\/families$/, (req, env) => createFamily(req, env)],
  ["POST", /^\/invites$/, (req, env) => createInvite(req, env)],
  ["POST", /^\/invites\/([^/]+)\/join$/, (req, env, [code]) => joinInvite(req, env, code ?? "")],
  ["PUT", /^\/members\/me\/apns$/, (req, env) => registerApns(req, env)],
];

export async function route(request: Request, env: Env): Promise<Response> {
  const { pathname } = new URL(request.url);
  let pathMatched = false;
  for (const [method, pattern, handler] of routes) {
    const match = pattern.exec(pathname);
    if (!match) continue;
    pathMatched = true;
    if (method === request.method) return handler(request, env, match.slice(1));
  }
  return pathMatched ? errorResponse(405, "method_not_allowed") : errorResponse(404, "not_found");
}

export default {
  async fetch(request, env, _ctx): Promise<Response> {
    try {
      return await route(request, env);
    } catch (error) {
      if (error instanceof HttpError) return errorResponse(error.status, error.code);
      // Only the error name: messages could carry request content, which must not reach the logs.
      console.error("unhandled", error instanceof Error ? error.name : typeof error);
      return errorResponse(500, "internal_error");
    }
  },
} satisfies ExportedHandler<Env>;
