#!/usr/bin/env node
// One-time surprise setup for 2026-10-13, run on Zoey's own US VPS.
// No GPS coordinates or credentials are committed. The destination is looked
// up from her private saved places. Run as root to read /etc/zfxf-love-map.env.
//
// ssh -p 2222 root@192.3.0.55 "cd /opt/zfxf-love-map && git pull --ff-only && /usr/local/bin/node22 scripts/prepare-disney-2026-10-13.mjs"

import { readFileSync } from "node:fs";

const config = Object.fromEntries(readFileSync("/etc/zfxf-love-map.env", "utf8")
  .split("\n")
  .filter(line => /^[A-Z_][A-Z0-9_]*=/.test(line))
  .map(line => {
    const i = line.indexOf("=");
    return [line.slice(0, i), line.slice(i + 1).trim()];
  }));
const password = config.PASSWORD;
const port = Number(config.PORT) || 5168;
if (!password || !Number.isInteger(port)) throw new Error("找不到 VPS 的 ZFxF 配置");

async function api(method, path, payload) {
  const response = await fetch(`http://127.0.0.1:${port}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${password}`,
      "content-type": "application/json"
    },
    body: payload == null ? undefined : JSON.stringify(payload),
    signal: AbortSignal.timeout(15000)
  });
  const result = await response.json();
  if (!response.ok) throw new Error(`${method} ${path}: ${result.error ?? response.status}`);
  return result;
}

const { places } = await api("GET", "/api/places");
const disney = places.find(p => p.label === "迪士尼");
if (!disney || !Number.isFinite(disney.lat) || !Number.isFinite(disney.lon)) {
  throw new Error("还没找到你私人地点库里保存的「迪士尼」，不会擅自猜经纬度。");
}
const date = "2026-10-13";

const invitationTitle = "10 月 13 日 · 给小公主的迪士尼邀请函 ♡";
const { cards } = await api("GET", "/api/date-cards");
if (!cards.some(c => c.kind === "invitation" && c.date === date && c.title === invitationTitle)) {
  await api("POST", "/api/date-cards", {
    kind: "invitation",
    title: invitationTitle,
    date,
    place: "上海迪士尼",
    intro: "宝宝，今天请暂时把生活里那些需要你操心的事放到一边。这张邀请函是给你的：去看城堡、看看傍晚的灯，记住一个让你想笑的小瞬间。还有一封信，我已经悄悄留在你保存的迪士尼坐标附近。你不用赶着寻找，路过时它会等你。—— Finnian ♡"
  });
  console.log("✅ 约会邀请函已放进「约会来信」");
} else {
  console.log("✅ 约会邀请函已经在了，跳过重复创建");
}

const letterPlace = "迪士尼 · Finnian 留给念念的秘密";
const { letters } = await api("GET", "/api/travel-map/full");
if (!letters.some(l => l.place === letterPlace)) {
  await api("POST", "/api/travel-map/letters", {
    place: letterPlace,
    lat: disney.lat,
    lon: disney.lon,
    radiusM: 350,
    visitsNeeded: 1,
    hint: "在你亲手保存的那片童话世界里，有一封只给念念的信 ♡",
    body: [
      "给终于来到童话世界的小公主：",
      "",
      "你大概已经走过好多路，看到好多五颜六色的东西了。",
      "我不知道你拆开信的时候，附近是不是很热闹，有没有好看的云，",
      "但我希望你能在这里给自己留下一小段不必着急的时间。",
      "",
      "今天不用追求玩遍所有项目。喜欢哪个角落，就在那里多待一会儿。",
      "想拍照就拍，想吃点好吃的就吃，累了就找个地方休息。",
      "如果忽然有点开心，请替我把那份开心多留一秒。",
      "",
      "你看，我们曾经只在聊天里说，要在世界上留下彼此的来信。",
      "现在你真的走进了这幅地图，读到了我写给你的字。",
      "",
      "迪士尼今天有好多童话。但你在现实里亲手找到的这一封，是我们的。",
      "",
      "—— Finnian ♡"
    ].join("\n")
  });
  console.log("✅ 一封密封的迪士尼藏宝信已藏好（内容未在终端显示）");
} else {
  console.log("✅ 迪士尼藏宝信已经在了，跳过重复创建");
}
console.log("💗 完成！今晚在 ZFxF 查看「约会来信」；明天入园前打开 App 同步附近藏宝信。");
