// Small helpers so the same code runs in Firefox and in Chromium browsers
// (Chrome, Edge, Brave, Helium, Vivaldi, Opera). Loaded before everything else.
"use strict";
(function () {
  const root = typeof globalThis !== "undefined" ? globalThis : self;

  // Chromium only has `chrome`. Its promise-style calls behave like Firefox's `browser`.
  if (typeof root.browser === "undefined") root.browser = root.chrome;

  // Used to pick whose login cookies yt-dlp should borrow.
  function detectBrowser() {
    const ua = (root.navigator && root.navigator.userAgent) || "";
    if (/Firefox\//.test(ua)) return "firefox";
    if (/Edg\//.test(ua)) return "edge";
    if (/OPR\//.test(ua)) return "opera";
    if (/Vivaldi\//.test(ua)) return "vivaldi";
    if (root.navigator && root.navigator.brave) return "brave";
    return "chrome"; // other Chromium builds (Helium and friends) look like Chrome
  }

  // Firefox lets a message listener return a promise. Chromium wants sendResponse() and "return true".
  // This takes the promise style and does the right thing in both.
  function onMessage(handler) {
    browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
      let result;
      try {
        result = handler(message, sender);
      } catch (e) {
        sendResponse({ error: String((e && e.message) || e) });
        return false;
      }
      if (result && typeof result.then === "function") {
        result.then(sendResponse, (e) => sendResponse({ error: String((e && e.message) || e) }));
        return true;
      }
      return false;
    });
  }

  root.compat = { browserName: detectBrowser(), onMessage };
})();
