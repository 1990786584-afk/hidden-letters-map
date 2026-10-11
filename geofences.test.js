import test from "node:test";
import assert from "node:assert/strict";
import express from "express";
import { pendingLetterRegions, registerGeofenceRoutes } from "./geofences.js";

test("only valid sealed single-visit letters get geofences", () => {
  const letters = [
    { id:"a", lat:31, lon:121, status:"sealed", radiusM:70, visitsNeeded:1 },
    { id:"b", lat:31, lon:121, status:"found", radiusM:70 },
    { id:"c", lat:31, lon:121, status:"sealed", visitsNeeded:3 },
    { id:"d", lat:null, lon:121, status:"sealed" },
    { id:"e", lat:31, lon:181, status:"sealed" },
    { id:"f", lat:31.2, lon:121.2, status:"sealed", radiusM:600 },
  ];
  assert.deepEqual(pendingLetterRegions(letters),[
    {id:"a",lat:31,lon:121,radiusM:160},
    {id:"f",lat:31.2,lon:121.2,radiusM:350},
  ]);
});

test("authenticated region entry only marks found; never opens; repeated entry is idempotent", async (t) => {
  const letter={
    id:"secret",place:"大草坪",lat:31,lon:121,radiusM:180,visitsNeeded:1,
    status:"sealed",hint:"这里有个秘密",body:"绝对不自动显示的秘密正文",
    area:{lat:31.0005,lon:121.0005,r:540},createdAt:"2026-10-11T00:00:00Z"
  };
  const map={letters:[letter]};
  let writes=0;
  const app=express();app.use(express.json());
  app.use((req,res,next)=>req.get("authorization")==="Bearer test" ? next() : res.status(401).json({error:"unauthorized"}));
  registerGeofenceRoutes(app,{readMap:()=>map,writeMap:()=>{writes++;}});
  const s=await new Promise(resolve=>{const server=app.listen(0,"127.0.0.1",()=>resolve(server));});
  t.after(()=>new Promise(resolve=>s.close(resolve)));
  const base=`http://127.0.0.1:${s.address().port}/api/geofences`;
  async function call(path,method="GET",auth=true) {
    const response=await fetch(base+path,{
      method,headers:auth?{"authorization":"Bearer test"}:{}
    });
    return { status:response.status, body:await response.json(), cache:response.headers.get("cache-control") };
  }
  assert.equal((await call("", "GET", false)).status,401);
  assert.equal((await call("/secret/discover","POST",false)).status,401);
  assert.equal((await call("")).body.regions.length,1);
  const first=await call("/secret/discover","POST");
  assert.equal(first.status,200);
  assert.equal(first.body.status,"found");
  assert.equal(first.body.letter.body,undefined);
  assert.equal(first.body.letter.place,"大草坪");
  assert.equal(writes,1);
  const second=await call("/secret/discover","POST");
  assert.equal(second.body.status,"found");
  assert.equal(writes,1);
  assert.deepEqual((await call("")).body,{regions:[]});
  assert.equal((await call("/missing/discover","POST")).status,404);
});
