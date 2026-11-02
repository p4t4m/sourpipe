// Writes live bridge output as JSON so the Swift models can be tested against it:
//   bun extractor/test/dump-fixtures.mjs <dir>
//   FIXTURE_DIR=<dir> swift test     (in ios/)
// Do not commit the output: its stream URLs embed the requesting IP address.
import { mkdirSync, writeFileSync } from "node:fs";
import { load } from "./harness.mjs";

const dir = process.argv[2];
if (!dir) throw new Error("usage: dump-fixtures.mjs <dir>");
mkdirSync(dir, { recursive: true });
const call = load();
const save = (name, value) => writeFileSync(`${dir}/${name}.json`, JSON.stringify(value));
const stream = (items) => items.find((i) => i.type === "stream").url;

save("services", await call("services"));
const search = await call("search", { serviceId: 0, query: "big buck bunny" });
save("search", search);
save("streamYoutube", await call("stream", { serviceId: 0, url: stream(search.items) }));
save("kiosk", await call("kiosk", { serviceId: 0, id: "live" }));
const channel = await call("channel", { serviceId: 0, url: "https://www.youtube.com/channel/UCSMOQeBJ2RAnuFungnQOxLg" });
save("channel", channel);
save("channelTab", await call("channelTab", { serviceId: 0, token: channel.tabs[0].token }));
const lists = await call("search", { serviceId: 0, query: "full course lectures", filter: "playlists" });
save("playlist", await call("playlist", { serviceId: 0, url: lists.items.find((i) => i.type === "playlist").url }));
save("comments", await call("comments", { serviceId: 0, url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ" }));
const sc = await call("search", { serviceId: 1, query: "ambient", filter: "tracks" });
save("streamSoundcloud", await call("stream", { serviceId: 1, url: stream(sc.items) }));
const pt = await call("kiosk", { serviceId: 3, id: "Trending" });
save("streamPeertube", await call("stream", { serviceId: 3, url: stream(pt.items) }));
const bc = await call("kiosk", { serviceId: 4, id: "Radio" });
save("streamBandcamp", await call("stream", { serviceId: 4, url: stream(bc.items) }));
const cc = await call("kiosk", { serviceId: 2, id: "recent" });
save("streamMediaccc", await call("stream", { serviceId: 2, url: stream(cc.items) }));
console.log("wrote fixtures to", dir);
process.exit(0);
