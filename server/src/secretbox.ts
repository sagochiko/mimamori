// Seals short secrets (the Gmail refresh token) before they go into D1.
// AES-256-GCM with TOKEN_ENC_KEY (32 bytes, base64). Output: base64url(iv[12] || ciphertext).

import { base64url } from "./auth";

function fromBase64(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

async function importKey(keyBase64: string): Promise<CryptoKey> {
  const raw = fromBase64(keyBase64);
  if (raw.length !== 32) throw new Error("TOKEN_ENC_KEY must be 32 bytes");
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function sealText(keyBase64: string, plaintext: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const sealed = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    await importKey(keyBase64),
    new TextEncoder().encode(plaintext),
  );
  const out = new Uint8Array(iv.length + sealed.byteLength);
  out.set(iv, 0);
  out.set(new Uint8Array(sealed), iv.length);
  return base64url(out);
}

export async function openText(keyBase64: string, sealedText: string): Promise<string> {
  const bytes = fromBase64(sealedText);
  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: bytes.slice(0, 12) },
    await importKey(keyBase64),
    bytes.slice(12),
  );
  return new TextDecoder().decode(plain);
}

const DEDUPE_KEY_INFO = new TextEncoder().encode("mimamori alerts sender_key and domain_key");

/**
 * Hex HMAC-SHA256 of the text under a key derived from TOKEN_ENC_KEY with HKDF, so one secret serves
 * both uses and neither can stand in for the other. Used for the alerts' sender_key and domain_key: a
 * plain SHA-256 of the family id and a phone number can be reversed by trying every number (#53).
 * Without a usable TOKEN_ENC_KEY it is the plain SHA-256, so the judge keeps working; deploy lists
 * TOKEN_ENC_KEY as required, so that is only for a local run without the key.
 */
export async function dedupeDigest(keyBase64: string | undefined, text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  let raw: Uint8Array | null = null;
  try {
    raw = keyBase64 ? fromBase64(keyBase64) : null;
  } catch {
    raw = null;
  }
  let digest: ArrayBuffer;
  if (raw && raw.length === 32) {
    const base = await crypto.subtle.importKey("raw", raw, "HKDF", false, ["deriveKey"]);
    const hmac = await crypto.subtle.deriveKey(
      { name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: DEDUPE_KEY_INFO },
      base,
      { name: "HMAC", hash: "SHA-256", length: 256 },
      false,
      ["sign"],
    );
    digest = await crypto.subtle.sign("HMAC", hmac, data);
  } else {
    console.warn("dedupe key unkeyed", "no_token_enc_key");
    digest = await crypto.subtle.digest("SHA-256", data);
  }
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}
