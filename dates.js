// ZFxF date board: private-by-login memories; photos stay outside public/ and dist/.
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MAX_PHOTOS = 4;
const MAX_PHOTO_BYTES = 1_500_000;
const MAX_ENTRIES = 1000;

export function normalizeDateEntry(input = {}, now = new Date()) {
  const date = String(input.date || "").trim();
  const title = String(input.title || "").trim();
  const place = String(input.place || "").trim();
  const note = String(input.note || "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(Date.parse(date))) {
    throw new Error("请选择有效的约会日期");
  }
  if (!title || title.length > 80) throw new Error("约会标题需要 1–80 个字");
  if (place.length > 100 || note.length > 1200) throw new Error("地点或日记太长啦");
  const photos = input.photos ?? [];
  if (!Array.isArray(photos) || photos.length > MAX_PHOTOS) throw new Error("每次最多上传 4 张照片");
  const imageBuffers = photos.map((dataUrl) => {
    if (typeof dataUrl !== "string" || !/^data:image\/jpeg;base64,[A-Za-z0-9+/]+={0,2}$/.test(dataUrl)) {
      throw new Error("请上传 JPG 照片");
    }
    const bytes = Buffer.from(dataUrl.slice("data:image/jpeg;base64,".length), "base64");
    if (!bytes.length || bytes.length > MAX_PHOTO_BYTES || bytes[0] !== 0xff || bytes[1] !== 0xd8) {
      throw new Error("有张照片太大或者格式不对");
    }
    return bytes;
  });
  return {
    entry: { id: randomUUID(), date, title, place, note, photos: [],
      createdAt: now.toISOString() },
    imageBuffers,
  };
}

export function registerDateRoutes(app, dataDir) {
  const file = join(dataDir, "dates.json");
  const photoDir = join(dataDir, "date-photos");
  mkdirSync(photoDir, { recursive: true });
  const read = () => {
    try {
      const dates = JSON.parse(readFileSync(file, "utf-8"));
      return Array.isArray(dates) ? dates : [];
    } catch { return []; }
  };
  const write = (entries) => writeFileSync(file, JSON.stringify(entries, null, 2) + "\n");

  app.get("/api/dates", (_req, res) => {
    const dates = read().sort((a, b) =>
      b.date.localeCompare(a.date) || b.createdAt.localeCompare(a.createdAt));
    res.json({ dates });
  });

  app.post("/api/dates", (req, res) => {
    try {
      const entries = read();
      if (entries.length >= MAX_ENTRIES) return res.status(409).json({ error: "纪念册暂时满啦" });
      const { entry, imageBuffers } = normalizeDateEntry(req.body);
      entry.photos = imageBuffers.map((_, index) => `${entry.id}-${index}.jpg`);
      for (let i = 0; i < imageBuffers.length; i++) {
        writeFileSync(join(photoDir, entry.photos[i]), imageBuffers[i], { flag: "wx" });
      }
      entries.push(entry);
      write(entries);
      res.status(201).json({ ok: true, entry });
    } catch (e) {
      res.status(400).json({ error: e.message || "保存失败，请重试" });
    }
  });

  // The directory is not static; a valid authenticated entry must reference the image.
  app.get("/api/dates/photos/:name", (req, res) => {
    const name = req.params.name;
    if (!/^[a-f0-9-]{36}-[0-3]\.jpg$/.test(name) ||
      !read().some((entry) => entry.photos?.includes(name)) ||
      !existsSync(join(photoDir, name))) return res.status(404).end();
    res.type("image/jpeg").set("Cache-Control", "private, max-age=600")
      .sendFile(join(photoDir, name));
  });
}
