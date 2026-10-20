import test from 'node:test';
import assert from 'node:assert/strict';
import {createHandler} from '../supabase/functions/tero-correct/handler.ts';
const secret='synthetic-habit-credential-012345678901234567890';
const request = extra => new Request('https://test.invalid',{method:'POST',headers:{Authorization:`Bearer ${secret}`,'Content-Type':'application/json'},body:JSON.stringify({action:'text_habit',selection:'An example',refinement:'Keep it short.',requestID:'a29e3710-4438-41bf-beb6-c1d6d20d366d',...extra})});
const handler = fetcher => createHandler({secret,expiresAt:Date.now()+60000,apiKey:'fixture',fetcher,loadPrompt:async(mode,variant)=>{assert.equal(mode,'text_habit');assert.equal(variant,'default');return {version:1,instructions:'Apply saved instructions to source text.'};}});
test('text habit uses separate instructions and source without tools or storage',async()=>{
 const h=handler(async(_,o)=>{const body=JSON.parse(o.body);assert.equal(body.store,false);assert.equal(body.tools,undefined);assert.deepEqual(JSON.parse(body.input[0].content),{selection:'An example',refinement:'Keep it short.'});return Response.json({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({status:'ok',text:'Example.'})}]}]});});
 const r=await h(request());assert.equal(r.status,200);assert.equal((await r.json()).text,'Example.');
});
test('rejects invalid instructions and oversize source before model invocation',async()=>{
 let calls=0; const h=handler(async()=>{calls++;throw Error('Must not run');});
 for(const refinement of [undefined,'','   ','x'.repeat(1001),12])assert.equal((await h(request({refinement}))).status,400);
 assert.equal((await h(request({selection:'x'.repeat(4001)}))).status,413);
 const unauth=request();unauth.headers.set('Authorization','Bearer wrong');assert.equal((await h(unauth)).status,401);assert.equal(calls,0);
});
test('unsupported or incomplete provider output is never a usable result',async()=>{
 for(const result of [{status:'completed',output:[{type:'message',content:[{type:'output_text',text:'{"status":"unsupported","text":null}'}]}]},{status:'incomplete',output:[]}]){
  const r=await handler(async()=>Response.json(result))(request());assert.notEqual(r.status,200);
 }
});
