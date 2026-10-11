// ZFxF: intentional, one-time sharing of the latest location, not background tracking.
// Independent of the legacy /api/location route (which records tracks and unlocks letters).
import { randomUUID } from "node:crypto";
import { existsSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export const SHARE_TTL_MS = 24 * 60 * 60 * 1000;

export function normalizeManualShare(body = {}, now = new Date()) {
  if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error("定位数据格式不正确");
  // Do not Number(null), Number("") or other coercions into valid zero coordinates.
  const valid = x => typeof x === "number" && Number.isFinite(x);
  if (!valid(body.lat) || !valid(body.lon) || Math.abs(body.lat) > 90 || Math.abs(body.lon) > 180) {
    throw new Error("位置坐标不正确");
  }
  const acc = body.acc;
  if (!valid(acc) || acc < 0 || acc > 10000) throw new Error("定位精度不正确");
  const nowMs = now.getTime();
  if (!Number.isFinite(nowMs)) throw new Error("服务器时间不正确");
  return {
    lat: body.lat, lon: body.lon, acc: Math.round(acc),
    at: new Date(nowMs).toISOString(),
    expiresAt: new Date(nowMs + SHARE_TTL_MS).toISOString(),
    source: "zfxf-manual-share",
  };
}

export function registerManualLocationRoutes(app, dataDir, clock = () => new Date()) {
  const file = join(dataDir, "manual-location.json");

  const active = () => {
    if (!existsSync(file)) return null;
    const saved = JSON.parse(readFileSync(file, "utf8"));
    return saved && Number.isFinite(Date.parse(saved.expiresAt)) &&
      Date.parse(saved.expiresAt) > clock().getTime() ? saved : null;
  };

  const save = (value) => {
    const tmp = file + "." + randomUUID() + ".tmp";
    try {
      writeFileSync(tmp, JSON.stringify(value) + "\n", { flag: "wx", mode: 0o600 });
      renameSync(tmp, file);
    } finally {
      rmSync(tmp, { force: true });
    }
  };

  app.use("/api/location/share", (_req, res, next) => {
    res.set("Cache-Control", "private, no-store");
    next();
  });

  // A location only appears here if the person explicitly pressed Share in the native app.
  app.get("/api/location/share", (_req, res) => {
    try { return res.json({ shared: active() }); }
    catch { return res.status(500).json({ error: "读取位置分享失败" }); }
  });

  // Updates ONLY the most recent shared point; neither tracking nor triggering visits.
  app.post("/api/location/share", (req, res) => {
    try {
      const shared = normalizeManualShare(req.body, clock());
      save(shared);
      return res.status(201).json({ ok: true, shared });
    } catch (e) {
      return res.status(400).json({ error: e.message || "分享失败" });
    }
  });

  // Immediate revocation; expired points are not returned by GET even before deletion.
  app.delete("/api/location/share", (_req, res) => {
    try {
      rmSync(file, { force: true });
      return res.json({ ok: true, shared: null });
    } catch {
      return res.status(500).json({ error: "撤回分享失败" });
    }
  });
}
