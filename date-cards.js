// ZFxF date cards: an invitation before a date, a feedback receipt afterwards.
// Mechanism inspired by Sigillo (29-Cu/sigillo, CC BY 4.0); independent implementation.
// Stores consented answers in DATA_DIR/date-cards.json, never inside public/ or dist/.
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MAX_CARDS = 500;
const RATINGS = [
  { key: "surprise", title: "今天的惊喜" },
  { key: "together", title: "陪伴感" },
  { key: "pace", title: "行程节奏" },
  { key: "food", title: "吃到的好东西" },
  { key: "overall", title: "整体心情" },
];

function plain(value, limit, name, required = false) {
  if (value != null && typeof value !== "string") throw new Error(`${name} 应填写文字`);
  const s = (value || "").trim();
  if (required && !s) throw new Error(`请填写${name}`);
  if (s.length > limit) throw new Error(`${name}最多 ${limit} 字`);
  return s;
}

function dateOnly(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error("日期格式应为 YYYY-MM-DD");
  const d = new Date(value + "T00:00:00Z");
  if (!Number.isFinite(d.getTime()) || d.toISOString().slice(0, 10) !== value) {
    throw new Error("约会日期不存在");
  }
  return value;
}

export function makeDateCard(input = {}, now = new Date()) {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("卡片内容无效");
  const kind = input.kind;
  if (!["invitation", "review"].includes(kind)) throw new Error("类型只能是 invitation 或 review");
  const title = plain(input.title, 80, "标题", true);
  const date = dateOnly(input.date);
  const place = plain(input.place, 120, "地点");
  const intro = plain(input.intro, 800, "邀请语");
  return {
    id: "date_" + randomUUID(),
    kind, title, date, place, intro,
    status: "pending",
    ratings: kind === "review" ? RATINGS.map(({ key, title }) => ({ key, title })) : [],
    createdAt: now.toISOString(),
    submittedAt: null,
    answers: null,
    agentNote: null,
    agentNoteAt: null,
    notification: "not-configured",
  };
}

function optional(input, key, maxLength) {
  return plain(input[key], maxLength, key);
}

export function parseDateAnswers(card, value = {}) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("填写内容格式不对");
  if (card.kind === "invitation") {
    return {
      where: optional(value, "where", 160),
      lookingForward: optional(value, "lookingForward", 500),
      mood: optional(value, "mood", 160),
      needs: optional(value, "needs", 800),
    };
  }
  const ratings = {};
  const raw = value.ratings || {};
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("评分格式不对");
  for (const { key } of RATINGS) {
    const n = raw[key];
    if (n == null) continue; // ratings are optional; silence is not a bad score
    if (typeof n !== "number" || n < 1 || n > 5 || !Number.isInteger(n * 2)) {
      throw new Error(`${key} 只能填 1～5 星，支持半星`);
    }
    ratings[key] = n;
  }
  return { ratings, favorite: optional(value, "favorite", 800),
    nextTime: optional(value, "nextTime", 800), note: optional(value, "note", 1600) };
}

function createRepository(file) {
  const read = () => {
    if (!existsSync(file)) return [];
    const data = JSON.parse(readFileSync(file, "utf8"));
    if (!Array.isArray(data)) throw new Error("约会卡片文件格式不正确，已停止写入以免覆盖");
    return data;
  };
  const save = (cards) => {
    const temp = `${file}.${randomUUID()}.tmp`;
    try {
      writeFileSync(temp, JSON.stringify(cards, null, 2) + "\n", { flag: "wx", mode: 0o600 });
      renameSync(temp, file);
    } catch (e) {
      try { if (existsSync(temp)) { unlinkSync(temp); } } catch {}
      throw e;
    }
  };
  // No concurrent asynchronous mutation between read+write: routes write synchronously.
  return { read, save };
}

export function registerDateCardRoutes(app, dataDir, options = {}) {
  mkdirSync(dataDir, { recursive: true });
  const store = createRepository(join(dataDir, "date-cards.json"));
  const webhookUrl = options.webhookUrl || "";
  const webhookToken = options.webhookToken || "";
  const canNotify = /^https:\/\//.test(webhookUrl) || /^http:\/\/127\.0\.0\.1(?::\d+)?\//.test(webhookUrl);
  if (webhookUrl && !canNotify) throw new Error("DATE_CARD_WEBHOOK_URL 必须是 HTTPS 或本机地址");

  const find = (id) => store.read().find((x) => x.id === id);
  async function notify(card) {
    if (!canNotify) return;
    try {
      const response = await fetch(webhookUrl, {
        method: "POST",
        headers: { "content-type": "application/json",
          ...(webhookToken ? { authorization: `Bearer ${webhookToken}` } : {}) },
        body: JSON.stringify({
          event: "zfxf.date_card.submitted",
          cardId: card.id, kind: card.kind, date: card.date,
          title: card.title, place: card.place,
          answers: card.answers, submittedAt: card.submittedAt,
          instruction: "这是真实填写的约会回执；请阅读事实，不要把评分机械转换成指令。若支持工具，可用 date_card_agent_note 留下复盘。",
        }),
        signal: AbortSignal.timeout(7000),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const cards = store.read();
      const current = cards.find((x) => x.id === card.id);
      if (current?.status === "submitted") {
        current.notification = "delivered";
        store.save(cards);
      }
    } catch (err) {
      // Keep the card and retry manually after fixing the webhook.
      console.warn("[date-cards] webhook failed:", err.message);
      const cards = store.read();
      const current = cards.find((x) => x.id === card.id);
      if (current?.status === "submitted" && current.notification !== "delivered") {
        current.notification = "failed";
        store.save(cards);
      }
    }
  }
  const sendLater = (card) => {
    if (!canNotify) return;
    setImmediate(() => { void notify(card); });
  };

  app.get("/api/date-cards", (_req, res) => {
    try { res.json({ cards: store.read().sort((a, b) => b.createdAt.localeCompare(a.createdAt)) }); }
    catch (e) { res.status(500).json({ error: e.message }); }
  });

  app.get("/api/date-cards/:id", (req, res) => {
    try {
      const card = find(req.params.id);
      return card ? res.json({ card }) : res.status(404).json({ error: "找不到这张卡片" });
    } catch (e) { return res.status(500).json({ error: e.message }); }
  });

  // Agent/MCP creates the card. Native app consumes the same API.
  app.post("/api/date-cards", (req, res) => {
    try {
      const cards = store.read();
      if (cards.length >= MAX_CARDS) return res.status(409).json({ error: "卡片数量已达到上限" });
      const card = makeDateCard(req.body);
      cards.push(card);
      store.save(cards);
      return res.status(201).json({ ok: true, card });
    } catch (e) { return res.status(400).json({ error: e.message }); }
  });

  app.post("/api/date-cards/:id/submit", (req, res) => {
    try {
      const cards = store.read();
      const card = cards.find((x) => x.id === req.params.id);
      if (!card) return res.status(404).json({ error: "找不到这张卡片" });
      if (card.status !== "pending") return res.status(409).json({ error: "这张卡片已经提交过了" });
      card.answers = parseDateAnswers(card, req.body);
      card.status = "submitted";
      card.submittedAt = new Date().toISOString();
      card.notification = canNotify ? "pending" : "not-configured";
      store.save(cards); // persist before webhook attempt; no phantom replies
      sendLater(card);
      return res.json({ ok: true, card });
    } catch (e) { return res.status(400).json({ error: e.message }); }
  });

  app.post("/api/date-cards/:id/agent-note", (req, res) => {
    try {
      const cards = store.read();
      const card = cards.find((x) => x.id === req.params.id);
      if (!card) return res.status(404).json({ error: "找不到这张卡片" });
      if (card.status !== "submitted") return res.status(409).json({ error: "等念念提交卡片后再写复盘" });
      card.agentNote = plain(req.body?.note, 1000, "复盘", true);
      card.agentNoteAt = new Date().toISOString();
      store.save(cards);
      return res.json({ ok: true, card });
    } catch (e) { return res.status(400).json({ error: e.message }); }
  });

  app.post("/api/date-cards/:id/notify", (req, res) => {
    try {
      if (!canNotify) return res.status(409).json({ error: "尚未配置 AI 接收地址" });
      const card = find(req.params.id);
      if (!card) return res.status(404).json({ error: "找不到这张卡片" });
      if (card.status !== "submitted") return res.status(409).json({ error: "卡片还没提交" });
      sendLater(card);
      return res.json({ ok: true, message: "已尝试再次通知 AI，稍后查看 notification 状态" });
    } catch (e) { return res.status(500).json({ error: e.message }); }
  });
}
