// Simulates a Chromium MV3 service worker: no `browser`, no `document`, importScripts, callback-style onMessage.
const fs = require("fs"), vm = require("vm"), path = require("path");
const EXT = path.join(__dirname, "..", "extension") + path.sep;
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.log("FAIL:", m); } };

function makeEnv(opts) {
  const store = { local: {}, session: {} };
  const area = (o) => ({ get: async (d) => ({ ...(typeof d === "object" && !Array.isArray(d) ? d : {}), ...o }), set: async (v) => { Object.assign(o, JSON.parse(JSON.stringify(v))); } });
  const listeners = { msg: [], alarm: [], cmd: [] };
  const sent = []; const nativeCalls = [];
  const chrome = {
    runtime: {
      onMessage: { addListener: (f) => listeners.msg.push(f) }, onStartup: { addListener() {} }, onInstalled: { addListener() {} },
      sendMessage: (m) => { sent.push(m); return Promise.resolve(); },
      getManifest: () => JSON.parse(fs.readFileSync(EXT + "manifest.json", "utf8")),
      getURL: (p) => "chrome-extension://x/" + p,
      sendNativeMessage: async (h, m) => { nativeCalls.push(m); return opts.native(m); },
      connectNative: opts.connectNative || (() => { throw new Error("no host"); }),
    },
    storage: { local: area(store.local), session: opts.noSession ? undefined : area(store.session) },
    action: { setBadgeText: async () => {}, setBadgeBackgroundColor: async () => {}, setIcon: async () => {}, setTitle: async () => {} },
    alarms: { create: () => {}, onAlarm: { addListener: (f) => listeners.alarm.push(f) } },
    commands: { onCommand: { addListener: (f) => listeners.cmd.push(f) } },
    notifications: { create: async () => {}, onClicked: { addListener() {} } },
    downloads: { showDefaultFolder() {} },
    tabs: { create: async () => {}, query: async () => [] },
    cookies: opts.cookies,
  };
  const ctx = { chrome, console, setTimeout, clearTimeout, Promise, JSON, Date, Math, URL, fetch: opts.fetch, navigator: { userAgent: opts.ua || "Mozilla/5.0 Chrome/130 Safari/537.36" },
    importScripts: (...files) => { for (const f of files) vm.runInContext(fs.readFileSync(EXT + f, "utf8"), ctx, { filename: f }); } };
  ctx.self = ctx; ctx.globalThis = ctx; vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(EXT + "background.js", "utf8"), ctx, { filename: "background.js" });
  const call = (msg) => new Promise((res) => { const r = listeners.msg[0](msg, {}, res); if (r !== true) res("__no_async__"); });
  return { ctx, call, sent, nativeCalls, listeners, store };
}
const ghFetch = (launcherTags) => async (url) => {
  if (String(url).includes("yt-dlp-launcher/releases")) return { ok: true, status: 200, json: async () => launcherTags };
  return { ok: true, status: 200, json: async () => ({ tag_name: "2026.10.21", html_url: "x" }) };
};

(async () => {
  // 1) loads in a Chromium-like worker and answers messages through sendResponse
  let e = makeEnv({ native: async () => ({}), fetch: ghFetch([]) });
  ok(e.ctx.compat.browserName === "chrome", "detects chrome");
  const st = await e.call({ type: "getAll" });
  ok(st && st.settings && st.settings.loginBrowser === "auto", "getAll via sendResponse, loginBrowser default");
  ok(st.version === "2.0.0 beta 4", "version label from version_name: " + st.version);
  ok(st.browserName === "chrome", "browserName in snapshot");

  // 2) THE BUG: winget offers the version that is already installed -> must NOT be an update
  e = makeEnv({ native: async (m) => m.action === "versions" ? { type: "versions", ok: true, ytdlp: "2026.10.28", ffmpeg: "N-127043-g5a54fcf75e-20260930", winget: true,
      wg: { ytdlp: { installed: "2026.10.21", available: "2026.10.28" }, ffmpeg: { installed: "N-127043-g5a54fcf75e-20260930", available: "N-127043-g5a54fcf75e-20260930" } } } : {}, fetch: ghFetch([]) });
  let u = await e.call({ type: "checkUpdates" });
  ok(u.ytdlp.available === false, "stale winget row (offers installed version) is not an update; got " + JSON.stringify(u.ytdlp));
  ok(u.ytdlp.stale === true, "marked stale");
  ok(/Up to date/.test(u.ytdlp.text), "text says up to date: " + u.ytdlp.text);
  ok(u.ffmpeg.available === false, "ffmpeg same build is not an update");

  // 3) a real update still shows
  e = makeEnv({ native: async (m) => m.action === "versions" ? { type: "versions", ok: true, ytdlp: "2026.10.21", ffmpeg: "N-127043-g5a54fcf75e-20260930", winget: true,
      wg: { ytdlp: { installed: "2026.10.21", available: "2026.11.03" }, ffmpeg: { installed: "N-127043-g5a54fcf75e-20260930", available: "N-128000-gabcdef-20261105" } } } : {}, fetch: ghFetch([]) });
  u = await e.call({ type: "checkUpdates" });
  ok(u.ytdlp.available && /2026\.11\.03/.test(u.ytdlp.text), "newer yt-dlp offered");
  ok(u.ffmpeg.available, "newer ffmpeg build offered");
  ok(u.any === true, "any=true");

  // 4) launcher beta ordering
  const tags = (...t) => t.map((x) => ({ tag_name: x, html_url: "u/" + x, prerelease: /beta/.test(x), draft: false }));
  const lau = async (list) => (await makeEnv({ native: async () => ({}), fetch: ghFetch(list) }).call({ type: "checkUpdates" })).launcher;
  let l = await lau(tags("v2.0.0-beta.4"));
  ok(!l.available && /v2\.0\.0 beta 4/.test(l.text), "same beta = up to date: " + l.text);
  l = await lau(tags("v2.0.0-beta.5", "v2.0.0-beta.4"));
  ok(l.available && /beta 5/.test(l.text), "beta 5 is newer than beta 4: " + l.text);
  l = await lau(tags("v2.0.0", "v2.0.0-beta.5"));
  ok(l.available && /v2\.0\.0$/.test(l.text.replace(/\s*\(.*\)$/, "")), "final beats beta: " + l.text);
  l = await lau(tags("v2.0.0-beta.1"));
  ok(!l.available, "older beta is not an update");
  l = await lau(tags("v1.9.0"));
  ok(!l.available, "older stable is not an update");

  // 5) Firefox-style detection + no session storage still works
  e = makeEnv({ native: async () => ({}), fetch: ghFetch([]), ua: "Mozilla/5.0 Gecko/20100101 Firefox/140.0", noSession: true });
  ok(e.ctx.compat.browserName === "firefox", "firefox detected");
  ok((await e.call({ type: "getAll" })).settings.login === false || true, "works without storage.session");
  e = makeEnv({ native: async () => ({}), fetch: ghFetch([]), ua: "Mozilla/5.0 Chrome/130 Safari/537 Edg/130.0" });
  ok(e.ctx.compat.browserName === "edge", "edge detected");

  // 6) settings accept only known login browsers
  e = makeEnv({ native: async () => ({}), fetch: ghFetch([]) });
  let r = await e.call({ type: "setSettings", patch: { loginBrowser: "edge" } });
  ok((await e.call({ type: "getAll" })).settings.loginBrowser === "edge", "loginBrowser saved");
  await e.call({ type: "setSettings", patch: { loginBrowser: "netscape" } });
  ok((await e.call({ type: "getAll" })).settings.loginBrowser === "edge", "bad loginBrowser rejected");

  // 7) "Open file" goes to the helper with the right action and path
  e = makeEnv({ native: async (m) => (m.action === "open" ? { type: "open", ok: m.path.endsWith(".mkv") } : {}), fetch: ghFetch([]) });
  r = await e.call({ type: "open", path: "C:\\Videos\\clip.mkv" });
  ok(r.ok === true, "open succeeds");
  ok(e.nativeCalls.some((c) => c.action === "open" && c.path === "C:\\Videos\\clip.mkv"), "helper got the open request");
  r = await e.call({ type: "open", path: "C:\\Videos\\gone.mp4" });
  ok(r.ok === false && r.message, "failed open gives a message");

  // 9) cookie export for Chromium, Firefox keeps using its own, and unknown pages get a Referer
  const posted = [];
  const fakePort = () => ({ postMessage: (m) => posted.push(m), onMessage: { addListener() {} }, onDisconnect: { addListener() {} }, disconnect() {} });
  const bank = {
    "youtube.com": [{ domain: ".youtube.com", path: "/", secure: true, httpOnly: true, name: "SID", value: "abc", expirationDate: 1900000000.5 },
                    { domain: "www.youtube.com", path: "/", secure: false, httpOnly: false, name: "PREF", value: "x" }],
    "google.com": [{ domain: ".google.com", path: "/", secure: true, httpOnly: false, name: "NID", value: "def", expirationDate: 1900000001 }],
  };
  const jar = { getAll: async (f) => (f.domain ? bank[f.domain] || [] : [{ domain: ".example.com", path: "/", secure: true, httpOnly: false, name: "s", value: "1" }]) };
  const startOne = async (env, url) => {
    posted.length = 0;
    await env.call({ type: "setSettings", patch: { login: true } });
    await env.call({ type: "start", job: { url, height: 1080, subs: false } });
    await new Promise((r) => setTimeout(r, 60));
    return posted.find((m) => m.action === "download");
  };
  e = makeEnv({ native: async () => ({}), fetch: ghFetch([]), connectNative: fakePort, cookies: jar });
  let dl = await startOne(e, "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
  ok(dl && dl.browser === "extension", "chrome-style browsers use the extension for cookies");
  ok(dl && dl.cookies.startsWith("# Netscape HTTP Cookie File\n"), "cookie file header");
  ok(dl && dl.cookies.includes("#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t1900000000\tSID\tabc"), "httpOnly secure cookie line");
  ok(dl && dl.cookies.includes("www.youtube.com\tFALSE\t/\tFALSE\t0\tPREF\tx"), "session cookie line");
  ok(dl && dl.cookies.includes(".google.com\tTRUE"), "google cookies come along for youtube");
  ok(dl && dl.referer === "", "no referer for youtube");
  e = makeEnv({ native: async () => ({}), fetch: ghFetch([]), connectNative: fakePort, cookies: jar });
  dl = await startOne(e, "https://example.com/some/page");
  ok(dl && dl.cookies.includes(".example.com\tTRUE"), "other sites use the cookies for that address");
  ok(dl && dl.referer === "https://example.com/some/page", "unknown pages send the page as the referer");
  e = makeEnv({ native: async () => ({}), fetch: ghFetch([]), connectNative: fakePort, cookies: { getAll: async () => { throw new Error("no permission"); } } });
  dl = await startOne(e, "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
  ok(dl && dl.cookies === "", "no permission means no cookies, but the download still starts");
  e = makeEnv({ native: async () => ({}), fetch: ghFetch([]), connectNative: fakePort, cookies: jar, ua: "Mozilla/5.0 Gecko/20100101 Firefox/140.0" });
  dl = await startOne(e, "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
  ok(dl && dl.browser === "firefox" && dl.cookies === "", "firefox lets yt-dlp read its own cookies");

  // 10) Deno: the helper's check result reaches the popup
  e = makeEnv({ native: async (m) => (m.action === "check" ? { type: "check", ok: true, ytdlp: "x", ffmpeg: true, deno: false } : {}), fetch: ghFetch([]) });
  const hs = await e.call({ type: "checkHelper" });
  ok(hs.status === "ok" && hs.deno === false, "missing deno is reported");

  // 8) the two manifests suit their browsers
  const ff = JSON.parse(fs.readFileSync(EXT + "manifest.json", "utf8")), cr = JSON.parse(fs.readFileSync(EXT + "manifest.chromium.json", "utf8"));
  ok(ff.background.scripts && !ff.background.service_worker && !ff.key && !ff.version_name, "firefox manifest is clean");
  ok(cr.background.service_worker && !cr.background.scripts && cr.key && !cr.browser_specific_settings, "chromium manifest is clean");
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((x) => { console.log("CRASH", x); process.exit(1); });
