import test from "node:test";
import assert from "node:assert/strict";
import { normalizeDateEntry } from "./dates.js";

const example = { date: "2026-10-11", title: "第一场约会", place: "上海", note: "今天拍了照片。" };
test("a date memory is stored with an ID and no photos by default", () => {
  const { entry, imageBuffers } = normalizeDateEntry(example, new Date("2026-10-11T00:00:00Z"));
  assert.equal(entry.title, "第一场约会");
  assert.equal(entry.createdAt, "2026-10-11T00:00:00.000Z");
  assert.match(entry.id, /^[a-f0-9-]{36}$/);
  assert.deepEqual(entry.photos, []);
  assert.deepEqual(imageBuffers, []);
});
test("a date and a title are required", () => {
  assert.throws(() => normalizeDateEntry({ ...example, date: "yesterday" }), /日期/);
  assert.throws(() => normalizeDateEntry({ ...example, title: "" }), /标题/);
});
test("a scrapbook entry can contain at most four photos", () => {
  assert.throws(() => normalizeDateEntry({ ...example, photos: new Array(5).fill("abc") }), /4 张/);
  assert.throws(() => normalizeDateEntry({ ...example, photos: ["data:text/html;base64,SGk="] }), /JPG/);
});
