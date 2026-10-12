// Private named coordinates for ZFxF · Our Little Universe.
// Home / school / familiar walk stops belong to a private VPS file only.
// No background GPS or third-party geocoding from the server.
import { randomUUID } from "node:crypto";
import { existsSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MAX_PLACES = 60;
const KINDS = new Set(["home", "school", "outing", "walk", "other"]);

function cleanLabel(value) {
  if (typeof value !== "string") throw new Error("地点名称不能为空");
  const label = value.trim();
  if (label.length < 1 || label.length > 48 || /[\\/\n\r\t]/.test(label))
    throw new Error("地点名称应为 1～48 个字，不含换行或斜杠");
  return label;
}
const sameLabel = (a, b) => a.normalize("NFKC").toLocaleLowerCase("zh-CN") ===
  b.normalize("NFKC").toLocaleLowerCase("zh-CN");

export function normalizeSavedPlace(body, { id = randomUUID(), createdAt = new Date().toISOString() } = {}) {
  if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error("地点信息格式不正确");
  if (typeof body.lat !== "number" || !Number.isFinite(body.lat) ||
      typeof body.lon !== "number" || !Number.isFinite(body.lon) ||
      Math.abs(body.lat) > 90 || Math.abs(body.lon) > 180)
    throw new Error("经纬度不正确");
  const label = cleanLabel(body.label);
  const kind = body.kind ?? "other";
  if (!KINDS.has(kind)) throw new Error("地点类型不正确");
  const note = body.note ?? "";
  if (typeof note !== "string" || note.length > 180) throw new Error("备注不能超过 180 字");
  return {
    id, label, kind, lat: body.lat, lon: body.lon,
    note: note.trim(), createdAt,
  };
}

export function registerSavedPlacesRoutes(app, dataDir) {
  const file = join(dataDir, "private-places.json");
  const read = () => {
    if (!existsSync(file)) return [];
    const json = JSON.parse(readFileSync(file, "utf8"));
    if (!Array.isArray(json)) throw new Error("地点数据格式不正确");
    return json;
  };
  const save = places => {
    const tmp = file + "." + randomUUID() + ".tmp";
    try {
      writeFileSync(tmp, JSON.stringify(places, null, 2) + "\n", { mode: 0o600, flag: "wx" });
      renameSync(tmp, file);
    } finally {
      rmSync(tmp, { force: true });
    }
  };

  app.use("/api/places", (_req, res, next) => {
    res.set("Cache-Control", "private, no-store");
    next();
  });
  app.get("/api/places", (_req, res) => {
    try { res.json({ places: read() }); }
    catch { res.status(500).json({ error: "读取私人地点失败" }); }
  });
  app.post("/api/places", (req, res) => {
    try {
      const places = read();
      if (places.length >= MAX_PLACES) return res.status(409).json({ error: "最多保存 60 个地点" });
      const place = normalizeSavedPlace(req.body);
      if (places.some(x => sameLabel(x.label, place.label)))
        return res.status(409).json({ error: "这个地点名称已经保存过了，可以编辑原地点" });
      places.push(place);
      save(places);
      return res.status(201).json({ ok: true, place });
    } catch(e) {
      return res.status(/地点|经纬|备注/.test(e.message)?400:500).json({ error: /地点|经纬|备注/.test(e.message) ? e.message : "保存私人地点失败" });
    }
  });
  app.put("/api/places/:id", (req, res) => {
    try {
      const places = read();
      const index = places.findIndex(x => x.id === req.params.id);
      if (index < 0) return res.status(404).json({ error: "找不到这个地点" });
      const place = normalizeSavedPlace(req.body, { id: places[index].id, createdAt: places[index].createdAt });
      if (places.some((x,i) => i !== index && sameLabel(x.label,place.label)))
        return res.status(409).json({ error: "这个名称已经被其他地点使用" });
      places[index] = place;
      save(places);
      return res.json({ ok: true, place });
    } catch(e) {
      return res.status(/地点|经纬|备注/.test(e.message)?400:500).json({ error: /地点|经纬|备注/.test(e.message) ? e.message : "更新私人地点失败" });
    }
  });
  app.delete("/api/places/:id", (req, res) => {
    try {
      const places = read();
      const left = places.filter(x => x.id !== req.params.id);
      if (left.length === places.length) return res.status(404).json({ error: "找不到这个地点" });
      save(left);
      return res.json({ ok: true });
    } catch {
      return res.status(500).json({ error: "删除私人地点失败" });
    }
  });
}
