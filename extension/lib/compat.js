// Aurora Downloader 2.0.0 beta 2 - lets the same code run in Firefox and in Chromium browsers
// (Chrome, Edge, Brave, Vivaldi, Opera). Loaded first by the background script and the popup.
"use strict";
(function (g) {
  if (typeof g.browser === "undefined" && typeof g.chrome !== "undefined") g.browser = g.chrome;

  // Which browser is this? Used to pick whose login cookies yt-dlp should borrow.
  const ua = (g.navigator && g.navigator.userAgent) || "";
  let name = "chrome";
  if (/Firefox\//.test(ua)) name = "firefox";
  else if (/Edg\//.test(ua)) name = "edge";
  else if (/OPR\//.test(ua)) name = "opera";
  else if (/Vivaldi\//.test(ua)) name = "vivaldi";
  else if (g.navigator && g.navigator.brave) name = "brave";
  g.YTL_ENV = { name, firefox: name === "firefox" };

  // Firefox lets a message listener return a promise; Chromium needs sendResponse + "return true".
  // This works in both.
  g.YTL_onMessage = function (fn) {
    g.browser.runtime.onMessage.addListener((msg, sender, sendResponse) => {
      let r;
      try { r = fn(msg, sender); } catch (e) { sendResponse({ error: String((e && e.message) || e) }); return false; }
      if (r && typeof r.then === "function") {
        r.then((v) => sendResponse(v), (e) => sendResponse({ error: String((e && e.message) || e) }));
        return true;
      }
      return false;
    });
  };
})(typeof globalThis !== "undefined" ? globalThis : self);
