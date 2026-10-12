// Opt-in iOS geofences. Only the authenticated native device receives exact
// circle centers; the public treasure-map response remains intentionally fuzzy.
import { publicLetter } from "./letters.js";

export function pendingLetterRegions(letters) {
  return letters.filter(l => l.status === "sealed" && (l.visitsNeeded || 1) === 1)
    .filter(l => Number.isFinite(l.lat) && Number.isFinite(l.lon) && Math.abs(l.lat) <= 90 && Math.abs(l.lon) <= 180)
    .map(l => ({
      id: l.id, lat: l.lat, lon: l.lon,
      // iOS region monitoring is approximate and may notify late.
      radiusM: Math.min(350, Math.max(160, Number(l.radiusM) || 200)),
    }));
}

// app is mounted only AFTER existing Bearer/Basic/cookie auth middleware.
// This route is a trusted report of an iOS monitored-region entry, NOT a
// proof-of-presence. Never call it merely because an agent says "I am at X".
export function registerGeofenceRoutes(app, { readMap, writeMap }) {
  app.use("/api/geofences", (_req,res,next) => {
    res.setHeader("Cache-Control", "private, no-store");
    next();
  });

  app.get("/api/geofences", (_req, res) => {
    res.json({ regions: pendingLetterRegions(readMap().letters) });
  });

  app.post("/api/geofences/:id/discover", (req, res) => {
    const map = readMap();
    const letter = map.letters.find(l => l.id === req.params.id);
    if (!letter) return res.status(404).json({ error: "这封信已经不在地图里了" });
    if ((letter.visitsNeeded || 1) !== 1) {
      return res.status(409).json({ error: "需要多次到访的信暂不支持后台自动发现" });
    }
    if (letter.status === "sealed") {
      letter.status = "found";
      letter.foundAt = new Date().toISOString();
      letter.foundBy = "geofence";
      writeMap(map);
    }
    // Never reveal letter.body until they explicitly tap "拆开".
    return res.json({ ok: true, status: letter.status, letter: publicLetter(letter) });
  });
}
