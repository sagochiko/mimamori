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
