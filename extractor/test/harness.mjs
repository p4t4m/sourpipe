// Loads extractor.js the way the iOS app does: an empty JavaScriptCore global plus only the
// host functions listed here. Run with Bun (which is JavaScriptCore), not Node.
//   bun test/harness.mjs [path/to/extractor.js] [testName ...]
import vm from "node:vm";
import { readFileSync } from "node:fs";

const verbose = !!process.env.VERBOSE;
const bundlePath = (import.meta.main ? process.argv[2] : null) ?? new URL("../build/generated/teavm/js/extractor.js", import.meta.url).pathname;
const only = process.argv.slice(3);

if (typeof Bun === "undefined") throw new Error("Run with Bun: harness must use JavaScriptCore");

// Same default as ExtractorEngine.swift, which is the default of NewPipe's own downloader.
const USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0";
const decodeB64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

const host = {
  log: (m) => verbose && console.error("[bundle]", m),
  http(method, url, headersJson, bodyBase64, callback) {
    if (host.rateLimited) {
      const sorry = "https://www.google.com/sorry/index?continue=" + encodeURIComponent(url);
      return callback(JSON.stringify({ status: 429, url: method === "GET" ? sorry : url, headers: {}, body: "" }), null);
    }
    const headers = {};
    for (const [k, v] of Object.entries(JSON.parse(headersJson))) headers[k] = v.join(", ");
    if (verbose) console.error("[http]", method, url.slice(0, 110));
    fetch(url, {
      method, headers: { "User-Agent": USER_AGENT, ...headers }, redirect: "follow",
      body: bodyBase64 == null ? undefined : decodeB64(bodyBase64),
    }).then(async (r) => {
      const outHeaders = {};
      r.headers.forEach((v, k) => { (outHeaders[k] ??= []).push(v); });
      const body = method === "HEAD" ? "" : await r.text();
      callback(JSON.stringify({ status: r.status, url: r.url, headers: outHeaders, body }), null);
    }).catch((e) => callback(null, String(e)));
  },
};

export function load() {
  const ctx = vm.createContext({
    __sourpipeHost: host,
    setTimeout: (f, ms) => setTimeout(f, ms),
    clearTimeout: (t) => clearTimeout(t),
  });
  // TeaVM's stdout/stderr goes through console if it exists; JSContext has none.
  vm.runInContext(readFileSync(bundlePath, "utf8") + "\n;main([]);", ctx, { filename: "extractor.js" });
  return (method, args = {}) => new Promise((resolve, reject) => {
    const started = Date.now();
    const finish = () => {
      if (!ctx.__sourpipeCall) return setTimeout(finish, 5);
      ctx.__sourpipeCall(method, JSON.stringify(args), (result, error) => {
        if (error != null) { const e = JSON.parse(error); reject(Object.assign(new Error(e.message), { kind: e.kind, url: e.url })); }
        else resolve(Object.assign(JSON.parse(result), { __ms: Date.now() - started }));
      });
    };
    finish();
  });
}

const call = load();
const YT = 0, SC = 1, MCCC = 2, PT = 3, BC = 4;
const results = [];
const check = (cond, msg) => { if (!cond) throw new Error("assert failed: " + msg); };
const firstOf = (items, type) => items.find((i) => i.type === type);

const tests = {
  services: async () => {
    const r = await call("services");
    check(r.services.length >= 5, "5 services");
    return r.services.map((s) => `${s.id}:${s.name}[${s.kiosks.length}]`).join(" ");
  },
  resolve: async () => {
    const r = await call("resolve", { url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ" });
    check(r.serviceId === YT && r.linkType === "stream", JSON.stringify(r));
    return r.linkType;
  },
  ytSuggest: async () => {
    const r = await call("suggestions", { serviceId: YT, query: "linux" });
    check(r.suggestions.length > 0, "suggestions");
    return r.suggestions.slice(0, 3).join(", ");
  },
  ytSearch: async () => {
    const r = await call("search", { serviceId: YT, query: "big buck bunny" });
    const s = firstOf(r.items, "stream");
    check(s && s.url && s.name, "stream result");
    globalThis.ytStream = s.url;
    const more = await call("more", { serviceId: YT, kind: "search", query: "big buck bunny", page: r.nextPage });
    check(more.items.length > 0, "second page");
    return `${r.items.length}+${more.items.length} items; first="${s.name}" date=${s.textualUploadDate} ${r.__ms}ms`;
  },
  ytStream: async () => {
    const r = await call("stream", { serviceId: YT, url: globalThis.ytStream ?? "https://www.youtube.com/watch?v=aqz-KE-bpKQ" });
    globalThis.ytInfo = r;
    check(r.videoStreams.length + r.videoOnlyStreams.length + (r.hlsUrl ? 1 : 0) > 0, "playable: " + r.errors);
    return `${r.name} v=${r.videoStreams.length} vo=${r.videoOnlyStreams.length} a=${r.audioStreams.length} hls=${!!r.hlsUrl} dur=${r.duration} rel=${r.relatedItems.length} err=${r.errors.length} ${r.__ms}ms`;
  },
  ytPlayable: async () => {
    const r = globalThis.ytInfo; check(r, "needs ytStream");
    const s = r.videoStreams.find((v) => v.url) ?? r.videoOnlyStreams.find((v) => v.url);
    check(s, "direct url");
    const res = await fetch(s.url, { headers: { Range: "bytes=0-1023" } });
    check(res.status === 206 || res.status === 200, `media status ${res.status} ${s.url.slice(0, 80)}`);
    const mp4 = r.videoStreams.filter((v) => v.format === "MPEG-4").map((v) => v.resolution);
    return `itag=${s.itag} ${s.resolution} ${s.format} HTTP ${res.status}; progressive mp4: ${mp4}`;
  },
  ytHlsSegments: async () => {
    const r = globalThis.ytInfo; check(r?.hlsUrl, "hls url");
    const master = await (await fetch(r.hlsUrl)).text();
    const variants = master.split("\n").filter((l) => l.startsWith("#EXT-X-STREAM-INF"));
    const avc = variants.filter((l) => /avc1/.test(l)).length;
    const media = master.split("\n").find((l) => l.startsWith("http"));
    const playlist = await (await fetch(media)).text();
    const segment = playlist.split("\n").find((l) => l.startsWith("http"));
    const res = await fetch(segment, { headers: { Range: "bytes=0-1023" } });
    check(res.ok, `segment ${res.status}`);
    return `${variants.length} variants (${avc} AVC), segment HTTP ${res.status}`;
  },
  ytCaptions: async () => {
    const r = await call("stream", { serviceId: YT, url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ" });
    return `subtitles=${r.subtitles.length} first=${r.subtitles[0]?.languageTag}`;
  },
  ytComments: async () => {
    const r = await call("comments", { serviceId: YT, url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ" });
    check(r.items.length > 0 || r.disabled, "comments");
    return `${r.items.length} comments, first by ${r.items[0]?.uploaderName}`;
  },
  ytChannel: async () => {
    const r = await call("channel", { serviceId: YT, url: "https://www.youtube.com/channel/UCSMOQeBJ2RAnuFungnQOxLg" });
    check(r.name && r.tabs.length, "channel");
    const tab = await call("channelTab", { serviceId: YT, token: r.tabs[0].token });
    check(tab.items.length > 0, "tab items");
    return `${r.name} tabs=${r.tabs.map((t) => t.name)} items=${tab.items.length}`;
  },
  ytPlaylist: async () => {
    // Needs >100 videos: the first page is built with the hand-written protobuf encoder.
    const found = await call("search", { serviceId: YT, query: "full course lectures", filter: "playlists" });
    const list = found.items.filter((i) => i.type === "playlist").sort((a, b) => b.streamCount - a.streamCount)[0];
    check(list, "found a playlist");
    const r = await call("playlist", { serviceId: YT, url: list.url });
    check(r.items.length > 0, "playlist items");
    let more = "no second page";
    if (r.nextPage) more = (await call("more", { serviceId: YT, kind: "playlist", url: list.url, page: r.nextPage })).items.length;
    return `${r.name} (${r.streamCount}) ${r.items.length}+${more}`;
  },
  ytKiosk: async () => {
    const svc = (await call("services")).services[YT];
    check(!svc.kiosks.includes("Trending") && svc.defaultKiosk !== "Trending", "Trending hidden");
    const out = [];
    for (const id of svc.kiosks) {
      try { const r = await call("kiosk", { serviceId: YT, id }); out.push(`${id}:${r.items.length}`); }
      catch (e) { out.push(`${id}:ERR(${e.message.slice(0, 60)})`); }
    }
    check(!out.some((o) => o.includes(":ERR(")), "every kiosk loads");
    return out.join(" ") + " default=" + svc.defaultKiosk;
  },
  soundcloud: async () => {
    const r = await call("search", { serviceId: SC, query: "ambient", filter: "tracks" });
    const s = firstOf(r.items, "stream"); check(s, "track");
    const i = await call("stream", { serviceId: SC, url: s.url });
    check(i.audioStreams.length > 0, "audio");
    return `${i.name} audio=${i.audioStreams.map((a) => a.delivery + "/" + a.format)} date=${i.uploadDate}`;
  },
  peertube: async () => {
    const svc = (await call("services")).services[PT];
    const r = await call("kiosk", { serviceId: PT, id: svc.defaultKiosk });
    const s = firstOf(r.items, "stream"); check(s, "video");
    const i = await call("stream", { serviceId: PT, url: s.url });
    return `${i.name} v=${i.videoStreams.length} hls=${!!i.hlsUrl} date=${i.uploadDate}`;
  },
  bandcamp: async () => {
    const r = await call("kiosk", { serviceId: BC, id: "Radio" });
    const s = firstOf(r.items, "stream"); check(s, "show");
    const i = await call("stream", { serviceId: BC, url: s.url });
    return `${i.name} audio=${i.audioStreams.length} date=${i.uploadDate}`;
  },
  captcha: async () => {
    // A 429 must surface as "recaptcha" with a page the user can open to solve it.
    host.rateLimited = true;
    try {
      const page = "https://www.youtube.com/channel/UCSMOQeBJ2RAnuFungnQOxLg";
      const error = await call("channel", { serviceId: YT, url: page }).then(() => null, (e) => e);
      check(error && error.kind === "recaptcha", "kind " + error?.kind);
      check(error.url && /^https:\/\/(www\.youtube\.com|www\.google\.com\/sorry)/.test(error.url), "url " + error.url);
      return error.url.slice(0, 80);
    } finally {
      host.rateLimited = false;
    }
  },
  mediaccc: async () => {
    const r = await call("kiosk", { serviceId: MCCC, id: "recent" });
    const s = firstOf(r.items, "stream"); check(s, "talk");
    const i = await call("stream", { serviceId: MCCC, url: s.url });
    return `${i.name} v=${i.videoStreams.length} date=${s.uploadDate}`;
  },
};

if (import.meta.main) {
let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
  if (only.length && !only.includes(name)) continue;
  try {
    console.log(`PASS ${name}: ${await fn()}`);
  } catch (e) {
    failed++;
    console.log(`FAIL ${name}: [${e.kind ?? "?"}] ${String(e.message).slice(0, 700)}`);
  }
}
console.log(failed ? `${failed} FAILED` : "ALL PASSED");
process.exit(failed ? 1 : 0);
}
