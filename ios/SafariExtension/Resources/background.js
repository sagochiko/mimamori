// Passes the content script's page check to the native handler (SafariWebExtensionHandler.swift),
// which sends POST /page with the device key. Content scripts cannot message the native side
// themselves (Apple, "Messaging between the app and JavaScript in a Safari web extension"), and the
// device key stays on the native side.
//
// The page's URL and text are data to check. Nothing here reads them beyond passing them on, and
// nothing is logged.

const CACHE_MS = 10 * 60 * 1000;
const CACHE_MAX = 50;
/** url -> { level, at }. Lost when Safari unloads the worker, which only costs one more check. */
const recent = new Map();

function remembered(url) {
  const hit = recent.get(url);
  if (!hit) return null;
  if (Date.now() - hit.at > CACHE_MS) {
    recent.delete(url);
    return null;
  }
  return hit;
}

function remember(url, level) {
  recent.delete(url);
  recent.set(url, { level, at: Date.now() });
  while (recent.size > CACHE_MAX) recent.delete(recent.keys().next().value);
}

async function check(message) {
  const hit = message.recheck ? null : remembered(message.url);
  if (hit) return { level: hit.level };
  let reply;
  try {
    reply = await browser.runtime.sendNativeMessage("application.id", {
      type: "page",
      url: message.url,
      text: message.text,
      hasSecretField: message.hasSecretField === true,
    });
  } catch {
    return {};
  }
  // `checked` is set only when the server answered. A failure ({}) is not remembered, so the next
  // visit asks again instead of showing no warning for ten minutes.
  if (!reply || reply.checked !== true) return {};
  const level = reply.level === 1 || reply.level === 2 ? reply.level : null;
  remember(message.url, level);
  return level === null ? {} : { level };
}

browser.runtime.onMessage.addListener((message, sender) => {
  // Only our own content script, in a tab.
  if (sender.id !== browser.runtime.id || !sender.tab) return undefined;
  if (!message || message.type !== "page" || typeof message.url !== "string" || typeof message.text !== "string") {
    return undefined;
  }
  return check(message);
});
