import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, existsSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import express from "express";
import { normalizeSavedPlace, registerSavedPlacesRoutes } from "./saved-places.js";

test("private place rejects invalid or missing inputs", () => {
  assert.throws(()=>normalizeSavedPlace({label:"家",lat:null,lon:1}),/经纬度/);
  assert.throws(()=>normalizeSavedPlace({label:"家",lat:91,lon:1}),/经纬度/);
  assert.throws(()=>normalizeSavedPlace({label:"",lat:10,lon:10}),/地点/);
  assert.throws(()=>normalizeSavedPlace({label:"\n",lat:10,lon:10}),/地点/);
  assert.throws(()=>normalizeSavedPlace({label:"家",lat:10,lon:10,kind:"gps"}),/类型/);
  assert.equal(normalizeSavedPlace({label:"家",lat:0,lon:0}).kind,"other");
});

test("private places require auth; support list, create, edit, delete, and avoid tracking", async(t) => {
  const dir=mkdtempSync(join(tmpdir(),"zfxf-places-"));
  t.after(()=>rmSync(dir,{recursive:true,force:true}));
  const app=express();app.use(express.json());
  app.use((req,res,next)=>req.get("authorization")==="Bearer private-test"?
    next():res.status(401).json({error:"unauthorized"}));
  registerSavedPlacesRoutes(app,dir);
  const server=await new Promise(resolve=>{
    const s=app.listen(0,"127.0.0.1",()=>resolve(s));
  });
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  const url=`http://127.0.0.1:${server.address().port}/api/places`;
  const call=async(path="",method="GET",body,auth=true)=>{
    const resp=await fetch(url+path,{
      method,headers:{"content-type":"application/json",
        ...(auth?{authorization:"Bearer private-test"}:{})},
      ...(body!==undefined?{body:JSON.stringify(body)}:{})
    });
    return {status:resp.status,cache:resp.headers.get("cache-control"),data:await resp.json()};
  };
  const home={label:"家",kind:"home",lat:31.1,lon:121.4,note:"仅供测试"};
  assert.equal((await call("","GET",undefined,false)).status,401);
  assert.deepEqual((await call()).data,{places:[]});
  assert.equal((await call("","POST",home,false)).status,401);
  const first=await call("","POST",home);
  assert.equal(first.status,201);
  const id=first.data.place.id;
  assert.ok(id);
  assert.equal((await call()).data.places[0].label,"家");
  assert.match((await call()).cache,/no-store/);
  assert.equal(statSync(join(dir,"private-places.json")).mode & 0o777,0o600);
  assert.equal((await call("","POST",{...home,label:"  家 " })).status,409);
  const updated=await call("/"+id,"PUT",{...home,label:"旧家",lat:31.2});
  assert.equal(updated.status,200);
  assert.equal(updated.data.place.id,id);
  assert.equal((await call()).data.places[0].lat,31.2);
  assert.equal((await call("/unknown","DELETE")).status,404);
  assert.equal((await call("/"+id,"DELETE")).status,200);
  assert.deepEqual((await call()).data,{places:[]});
  assert.equal(existsSync(join(dir,"track.jsonl")),false);
  assert.equal(existsSync(join(dir,"manual-location.json")),false);
});
