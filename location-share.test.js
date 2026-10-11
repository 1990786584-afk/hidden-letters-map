import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import express from "express";
import { SHARE_TTL_MS, normalizeManualShare, registerManualLocationRoutes } from "./location-share.js";

test("share rejects bad coordinates and expires after one day", () => {
  const now = new Date("2026-10-11T08:00:00Z");
  assert.throws(() => normalizeManualShare({ lat: null, lon: 0, acc: 10 }, now));
  assert.throws(() => normalizeManualShare({ lat: 20, lon: 200, acc: 10 }, now));
  const shared = normalizeManualShare({ lat: 20, lon: 30, acc: 10 }, now);
  assert.equal(Date.parse(shared.expiresAt)-Date.parse(shared.at), SHARE_TTL_MS);
});

test("manual sharing accepts explicit action only, returns latest, supports deletion", async(t) => {
  const dir = mkdtempSync(join(tmpdir(),"zfxf-share-"));
  t.after(()=>rmSync(dir,{recursive:true,force:true}));
  const app = express();
  app.use(express.json());
  app.use((req,res,next)=>req.get("authorization") === "Bearer test" ? next() : res.sendStatus(401));
  registerManualLocationRoutes(app,dir);
  const server = await new Promise(resolve => { const s = app.listen(0,"127.0.0.1",()=>resolve(s)); });
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  const url = `http://127.0.0.1:${server.address().port}/api/location/share`;
  const call=async(method,body,auth=true)=>{
    const res=await fetch(url,{method,headers:{
      "content-type":"application/json", ...(auth?{authorization:"Bearer test"}:{})
    },...(body?{body:JSON.stringify(body)}:{})});
    return {status:res.status,result:await res.json()};
  };
  assert.equal((await call("GET",null,false)).status,401);
  assert.equal((await call("GET")).result.shared,null);
  assert.equal((await call("POST",{lat:20,lon:30,acc:8})).status,201);
  assert.equal((await call("GET")).result.shared.lat,20);
  assert.equal((await call("POST",{lat:21,lon:31,acc:9})).status,201);
  assert.equal((await call("GET")).result.shared.lat,21);
  assert.equal(existsSync(join(dir,"track.jsonl")),false);
  assert.equal((await call("DELETE")).status,200);
  assert.equal((await call("GET")).result.shared,null);
});
