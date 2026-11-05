// Runs in every top-level http and https page. Sends the page's URL and the first 5,000 characters of
// its text to the background script, and lays a warning over the page when the server's rules answer
// level 1 or 2 (server/src/page.ts). No answer, or any other answer, draws nothing; that never means
// the page is fine.
//
// The page's text is data. Nothing in it changes what is sent or what the warning says: the warning's
// words are fixed here, keyed by the level number alone, and the verdict comes only from the extension's
// own messaging (never from window.postMessage, which the page could forge).
//
// The screen keeps a short fixed line and one-word buttons; the explanation is in the ARIA labels for
// VoiceOver (.claude/rules/ios.md).

(() => {
  if (window.top !== window) return;
  if (location.protocol !== "https:" && location.protocol !== "http:") return;
  // Her own network (a router's or printer's page) is neither judged nor sent; the server skips it too.
  const host = location.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (
    host === "localhost" ||
    /\.(local|localhost)$/.test(host) ||
    host === "::1" ||
    /^(fe80:|f[cd][0-9a-f]{2}:)/.test(host) ||
    /^(10|127)\.\d+\.\d+\.\d+$/.test(host) ||
    /^172\.(1[6-9]|2\d|3[01])\.\d+\.\d+$/.test(host) ||
    /^(192\.168|169\.254)\.\d+\.\d+$/.test(host)
  ) {
    return;
  }

  const TEXT_MAX = 5000;
  /** Ads and pop-ups often arrive after the page settles; one more look if this much text appeared. */
  const RECHECK_AFTER_MS = 5000;
  const RECHECK_GROWTH = 500;

  const WORDS = {
    1: {
      title: "開かないで",
      label: "このページは危ないかもしれません。開かないで。ボタンで前のページに戻れます。",
    },
    2: {
      title: "家族に確かめるまで待って",
      label: "このページは確かめが必要です。お金や暗証番号を入れる前に、家族に確かめるまで待って。",
    },
  };

  function pageText() {
    const raw = document.body ? document.body.innerText || "" : "";
    // Code points, as the server counts them; the slice first keeps Array.from cheap on long pages.
    return Array.from(raw.slice(0, TEXT_MAX * 2)).slice(0, TEXT_MAX).join("");
  }

  let shown = false;

  function goBack() {
    if (history.length > 1) history.back();
    else location.replace("about:blank");
  }

  function show(level) {
    const words = WORDS[level];
    if (!words || shown) return;
    shown = true;

    const host = document.createElement("div");
    const root = host.attachShadow({ mode: "closed" });

    const style = document.createElement("style");
    style.textContent = `
      :host { all: initial; }
      .veil {
        position: fixed; inset: 0; z-index: 2147483647;
        display: flex; flex-direction: column; justify-content: center; align-items: stretch;
        gap: 24px; padding: 32px 24px;
        background: ${level === 1 ? "#b3261e" : "#8a5300"};
        color: #ffffff;
        font: -apple-system-body; -webkit-text-size-adjust: 100%;
        touch-action: none;
      }
      h1 { margin: 0; font: -apple-system-title1; font-weight: 700; text-align: center; }
      button {
        font: -apple-system-headline; padding: 16px; border-radius: 14px; border: 0;
        min-height: 52px;
      }
      .back { background: #ffffff; color: #1c1c1e; }
      .close { background: transparent; color: #ffffff; border: 2px solid rgba(255,255,255,0.7); }
    `;

    const veil = document.createElement("div");
    veil.className = "veil";
    veil.setAttribute("role", "alertdialog");
    veil.setAttribute("aria-modal", "true");
    veil.setAttribute("aria-label", words.label);

    const title = document.createElement("h1");
    title.textContent = words.title;

    const back = document.createElement("button");
    back.className = "back";
    back.type = "button";
    back.textContent = "戻る";
    back.setAttribute("aria-label", "戻る。前のページに戻ります");
    back.addEventListener("click", goBack);

    const close = document.createElement("button");
    close.className = "close";
    close.type = "button";
    close.textContent = "閉じる";
    close.setAttribute("aria-label", "閉じる。警告を閉じてこのページを見ます");
    close.addEventListener("click", () => {
      observer.disconnect();
      host.remove();
    });

    veil.append(title, back, close);
    root.append(style, veil);

    // A page that removes the warning gets it back, until the mother closes it herself. Only removal
    // is undone: a page that hides the host (display:none or the hidden attribute on it), covers it,
    // or keeps raising alert() dialogs is not stopped here.
    const observer = new MutationObserver(() => {
      if (!host.isConnected) document.documentElement.append(host);
    });
    document.documentElement.append(host);
    observer.observe(document.documentElement, { childList: true });
    back.focus();
  }

  function ask(recheck) {
    const text = pageText();
    browser.runtime
      .sendMessage({ type: "page", url: location.href, text, recheck })
      .then((reply) => {
        if (reply && (reply.level === 1 || reply.level === 2)) show(reply.level);
      })
      .catch(() => {});
    return text.length;
  }

  const first = ask(false);
  setTimeout(() => {
    if (!shown && pageText().length >= first + RECHECK_GROWTH) ask(true);
  }, RECHECK_AFTER_MS);
})();
