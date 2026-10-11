import { useEffect, useState } from "react";
import { api } from "./api.js";
import "./date-board.css";

const today = () => {
  const d = new Date();
  return [d.getFullYear(), String(d.getMonth() + 1).padStart(2, "0"), String(d.getDate()).padStart(2, "0")].join("-");
};
const displayDate = (value) => value ? value.replace(/^(\d{4})-(\d{2})-(\d{2})$/, "$1 · $2 · $3") : "";
const photoUrl = (name) => `/api/dates/photos/${encodeURIComponent(name)}`;

function compressPhoto(file) {
  return new Promise((resolve, reject) => {
    if (!file.type.startsWith("image/")) return reject(new Error("请选择图片"));
    const url = URL.createObjectURL(file);
    const img = new Image();
    const clean = () => URL.revokeObjectURL(url);
    img.onerror = () => { clean(); reject(new Error("照片无法读取，可以换一张试试")); };
    img.onload = () => {
      try {
        const ratio = Math.min(1, 1200 / Math.max(img.naturalWidth, img.naturalHeight));
        const canvas = document.createElement("canvas");
        canvas.width = Math.max(1, Math.round(img.naturalWidth * ratio));
        canvas.height = Math.max(1, Math.round(img.naturalHeight * ratio));
        canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height);
        const jpeg = canvas.toDataURL("image/jpeg", 0.72);
        if (jpeg.length > 1_950_000) throw new Error("照片压缩后还是太大，可以换一张试试");
        resolve(jpeg);
      } catch (error) { reject(error); }
      finally { clean(); }
    };
    img.src = url;
  });
}

function MemoryCard({ entry }) {
  const [expanded, setExpanded] = useState(false);
  return (
    <article className="zf-card">
      <button type="button" className="zf-card-open" onClick={() => setExpanded(!expanded)} aria-expanded={expanded}>
        <div className={`zf-card-cover ${entry.photos.length ? "" : "zf-card-empty"}`}>
          {entry.photos.length
            ? <img src={photoUrl(entry.photos[0])} alt={`${entry.title}的照片`} loading="lazy" />
            : <span aria-hidden="true">♡</span>}
          {entry.photos.length > 1 && <span className="zf-count">📷 {entry.photos.length}</span>}
        </div>
        <span className="zf-card-text">
          <span className="zf-card-date">{displayDate(entry.date)}</span>
          <strong>{entry.title}</strong>
          {entry.place && <span>📍 {entry.place}</span>}
        </span>
      </button>
      {expanded && (
        <div className="zf-card-story">
          {entry.note && <p>{entry.note}</p>}
          {entry.photos.length > 1 && (
            <div className="zf-photo-grid">
              {entry.photos.slice(1).map((image) => <img key={image} src={photoUrl(image)} alt={`${entry.title}的另一张照片`} loading="lazy" />)}
            </div>
          )}
        </div>
      )}
    </article>
  );
}

export default function DateBoard({ onBack }) {
  const [dates, setDates] = useState([]);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [saving, setSaving] = useState(false);
  const [busyPhotos, setBusyPhotos] = useState(false);
  const [error, setError] = useState("");
  const [form, setForm] = useState({ title: "", date: today(), place: "", note: "" });
  const [photos, setPhotos] = useState([]);

  useEffect(() => {
    api.dates().then((r) => setDates(r.dates)).catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  const addPhotos = async (event) => {
    const files = Array.from(event.target.files || []);
    event.target.value = "";
    if (photos.length + files.length > 4) { setError("每次约会最多放 4 张照片哦"); return; }
    setError(""); setBusyPhotos(true);
    try {
      const list = await Promise.all(files.map(compressPhoto));
      setPhotos((old) => [...old, ...list].slice(0, 4));
    } catch (e) { setError(e.message); }
    finally { setBusyPhotos(false); }
  };

  const save = async (event) => {
    event.preventDefault();
    if (saving || busyPhotos) return;
    setError(""); setSaving(true);
    try {
      const r = await api.addDate({ ...form, photos });
      setDates((old) => [r.entry, ...old].sort((a, b) => b.date.localeCompare(a.date)));
      setCreating(false);
      setPhotos([]);
      setForm({ title: "", date: today(), place: "", note: "" });
    } catch (e) { setError(e.message); }
    finally { setSaving(false); }
  };

  return (
    <main className="zf-board">
      <header className="zf-head">
        <button type="button" className="zf-back" onClick={onBack}>← 藏宝地图</button>
        <span className="zf-eyebrow">ZFxF · OUR LITTLE DATES</span>
        <h1>我们的约会板 ♡</h1>
        <p>把每一次出门，都收进一张小小的拍立得。</p>
      </header>
      <div className="zf-toolbar">
        <span>{dates.length} 个约会纪念</span>
        <button type="button" className="zf-primary" onClick={() => { setCreating(!creating); setError(""); }}>
          {creating ? "先不写了" : "＋ 记录一次约会"}
        </button>
      </div>
      {error && <p className="zf-error" role="alert">{error}</p>}
      {creating && (
        <form className="zf-editor" onSubmit={save}>
          <h2>New Memory <span>♡</span></h2>
          <label>约会名字 <input required maxLength={80} placeholder="例如：秋天的第一次散步" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} /></label>
          <div className="zf-fields">
            <label>日期 <input required type="date" value={form.date} onChange={(e) => setForm({ ...form, date: e.target.value })} /></label>
            <label>地点 <input maxLength={100} placeholder="上海 · 某家咖啡馆" value={form.place} onChange={(e) => setForm({ ...form, place: e.target.value })} /></label>
          </div>
          <label>当天的小日记 <textarea maxLength={1200} rows={4} placeholder="今天发生了什么有趣的事……" value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></label>
          <label className="zf-upload">📷 添加照片（最多 4 张）
            <input type="file" multiple accept="image/*" onChange={addPhotos} disabled={busyPhotos || photos.length >= 4} />
          </label>
          {!!photos.length && <div className="zf-previews">
            {photos.map((src, i) => <div className="zf-preview" key={i}>
              <img src={src} alt={`待上传照片 ${i + 1}`} />
              <button type="button" aria-label={`移除第 ${i + 1} 张照片`} onClick={() => setPhotos((old) => old.filter((_, j) => j !== i))}>×</button>
            </div>)}
          </div>}
          <button type="submit" className="zf-primary zf-save" disabled={saving || busyPhotos}>{busyPhotos ? "正在整理照片…" : saving ? "保存中…" : "收藏这一天 ♡"}</button>
        </form>
      )}
      {loading ? <p className="zf-empty">正在翻开纪念册……</p> :
        dates.length ? <section className="zf-grid" aria-label="约会纪念册">
          {dates.map((entry) => <MemoryCard entry={entry} key={entry.id} />)}
        </section> : <section className="zf-empty">
          <span aria-hidden="true">💌</span>
          <h2>第一张拍立得，等你来贴。</h2>
          <p>照片、地点、日记都可以慢慢补进我们的故事里。</p>
        </section>}
      <footer className="zf-footer">ZFxF · in all the little places ♡</footer>
    </main>
  );
}
