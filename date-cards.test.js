import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import express from "express";
import { makeDateCard, parseDateAnswers, registerDateCardRoutes } from "./date-cards.js";

test("card creation validates dates, type, title and optional ratings", () => {
  assert.throws(() => makeDateCard({kind:"invitation", title:"A", date:"2026-02-30"}), /不存在/);
  assert.throws(() => makeDateCard({kind:"surprise", title:"A", date:"2026-10-11"}), /类型/);
  const before = makeDateCard({kind:"invitation", title:"周日约会",date:"2026-10-18"});
  assert.equal(before.status,"pending");
  assert.deepEqual(before.ratings,[]);
  assert.deepEqual(parseDateAnswers(before,{where:"去书店",needs:"走累了休息"}),{
    where:"去书店",lookingForward:"",mood:"",needs:"走累了休息"
  });
  const after = makeDateCard({kind:"review", title:"这一次的回执",date:"2026-10-18"});
  assert.equal(after.ratings.length,5);
  assert.deepEqual(parseDateAnswers(after,{ratings:{pace:4.5},favorite:"冰淇淋"}),{
    ratings:{pace:4.5},favorite:"冰淇淋",nextTime:"",note:""
  });
  assert.throws(()=>parseDateAnswers(after,{ratings:{pace:5.3}}),/半星/);
});

test("real authenticated routes persist cards, submit once, send webhook and save agent note", async(t)=>{
  const dir=mkdtempSync(join(tmpdir(),"zfxf-cards-"));
  t.after(()=>rmSync(dir,{recursive:true,force:true}));
  const received=[];
  const agent=express();
  agent.use(express.json());
  agent.post("/hooks", (req,res)=>{
    received.push({body:req.body,auth:req.get("authorization")});
    res.json({ok:true});
  });
  const agentServer=await new Promise(resolve=>{const srv=agent.listen(0,"127.0.0.1",()=>resolve(srv));});
  t.after(()=>agentServer.close());
  const url=`http://127.0.0.1:${agentServer.address().port}/hooks`;
  const app=express();
  app.use(express.json());
  app.use((req,res,next)=>req.headers.authorization==="Bearer test-secret" ? next() : res.status(401).json({error:"unauthorized"}));
  registerDateCardRoutes(app,dir,{webhookUrl:url,webhookToken:"secret-webhook-token"});
  const server=await new Promise(resolve=>{const srv=app.listen(0,"127.0.0.1",()=>resolve(srv));});
  t.after(()=>server.close());
  const api=`http://127.0.0.1:${server.address().port}`;
  async function hit(path,opts={}){
    const res=await fetch(api+path,{...opts,headers:{authorization:"Bearer test-secret","content-type":"application/json"}});
    return {code:res.status,data:await res.json()};
  }
  const unauthorized=await fetch(api+"/api/date-cards");
  assert.equal(unauthorized.status,401);
  const created=await hit("/api/date-cards",{method:"POST",body:JSON.stringify({kind:"review",date:"2026-10-18",title:"上海散步",place:"上海",intro:"今天辛苦了"})});
  assert.equal(created.code,201);
  const id=created.data.card.id;
  assert.match(id,/^date_/);
  const got=await hit("/api/date-cards");
  assert.equal(got.data.cards.length,1);
  const saved=await hit("/api/date-cards/"+id+"/submit",{method:"POST",body:JSON.stringify({ratings:{overall:5,pace:3.5},note:"下次不要走那么远"})});
  assert.equal(saved.code,200);
  assert.equal(saved.data.card.answers.ratings.pace,3.5);
  const dupe=await hit("/api/date-cards/"+id+"/submit",{method:"POST",body:JSON.stringify({})});
  assert.equal(dupe.code,409);
  const note=await hit("/api/date-cards/"+id+"/agent-note",{method:"POST",body:JSON.stringify({note:"下次把行程减半，留时间坐着聊天。"})});
  assert.equal(note.code,200);
  assert.ok(readFileSync(join(dir,"date-cards.json"),"utf8").includes("下次把行程减半"));
  for(let i=0;i<20 && !received.length;i++)await new Promise(r=>setTimeout(r,20));
  assert.equal(received.length,1);
  assert.equal(received[0].auth,"Bearer secret-webhook-token");
  assert.equal(received[0].body.event,"zfxf.date_card.submitted");
  assert.equal(received[0].body.answers.note,"下次不要走那么远");
  const after=await hit("/api/date-cards/"+id);
  assert.equal(after.data.card.notification,"delivered");
});

test("no webhook never pretends to have notified an agent",async(t)=>{
  const dir=mkdtempSync(join(tmpdir(),"zfxf-cards-"));
  t.after(()=>rmSync(dir,{recursive:true,force:true}));
  const app=express();app.use(express.json());
  registerDateCardRoutes(app,dir,{});
  const s=await new Promise(resolve=>{const server=app.listen(0,"127.0.0.1",()=>resolve(server));});
  t.after(()=>s.close());
  const base=`http://127.0.0.1:${s.address().port}/api/date-cards`;
  const headers={"content-type":"application/json"};
  const created=await (await fetch(base,{method:"POST",headers,body:JSON.stringify({kind:"invitation",date:"2026-10-18",title:"周末见",intro:"我想约你"})})).json();
  const response=await (await fetch(base+"/"+created.card.id+"/submit",{method:"POST",headers,body:JSON.stringify({lookingForward:"一起逛书店"})})).json();
  assert.equal(response.card.notification,"not-configured");
  const retry=await fetch(base+"/"+created.card.id+"/notify",{method:"POST",headers});
  assert.equal(retry.status,409);
});
