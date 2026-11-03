// Gmail. Task 7 adds the grant flow and the watch; this file starts with what
// "delete everything" needs: taking the grant back.

import { openText } from "./secretbox";

// https://developers.google.com/identity/protocols/oauth2/web-server (Token revocation):
// POST the token as a form parameter. 200 means revoked, 400 comes with an error code.
const REVOKE_URL = "https://oauth2.googleapis.com/revoke";

/**
 * Revokes one family's Gmail grant from its sealed refresh token.
 * Returns true when Google no longer holds the grant, including when it was already revoked or expired.
 */
export async function revokeGmailGrant(env: Env, refreshTokenEnc: string): Promise<boolean> {
  const token = await openText(env.TOKEN_ENC_KEY, refreshTokenEnc);
  let res: Response;
  try {
    res = await fetch(REVOKE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ token }).toString(),
    });
  } catch {
    return false;
  }
  if (res.ok) return true;
  if (res.status === 400) {
    const body = (await res.json().catch(() => ({}))) as { error?: string };
    return body.error === "invalid_token";
  }
  return false;
}
