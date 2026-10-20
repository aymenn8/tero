import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHandler} from '../supabase/functions/tero-correct/handler.ts';
import {validNamingFiles,validNames,namingContent} from '../supabase/functions/tero-correct/file-naming.ts';
const files=[{id:'file-0',text:'Invoice for Project Orion. Total: 80 EUR.'},{id:'file-1',text:'Schedule for the Orion launch on 2026-10-20.'}];
const names=[{id:'file-1',stem:'Orion Launch Schedule'},{id:'file-0',stem:'Orion Invoice'}];
const prompts=JSON.parse(readFileSync(new URL('./fixtures/published-prompts.json',import.meta.url)));
const secret='fixture-token-0123456789012345678901234567890123456789';
const id='a29e3710-4438-41bf-beb6-c1d6d20d366d';
const request=(extra={})=>new Request('https://fixture.invalid',{method:'POST',headers:{Authorization:`Bearer ${secret}`,'Content-Type':'application/json','X-Tero-File':'1'},body:JSON.stringify({action:'rename_files',selection:'Propose names.',requestID:id,files,...extra})});
const handler=(fetcher)=>createHandler({secret,expiresAt:Date.now()+60000,apiKey:'fixture',fetcher,loadPrompt:async()=>prompts.find(p=>p.mode_id==='rename_files')});
test('batch binding, paths, unsafe filenames and incomplete results are rejected',()=>{
 assert(validNamingFiles(files)); assert(validNames({status:'ok',names},files));
 for(const bad of [[{id:'file-1',text:'wrong mapping'}],[{...files[0],path:'/private'}],[{...files[0],file:{}}],[{...files[0],text:'x'.repeat(120001)}]]) assert(!validNamingFiles(bad));
 for(const bad of [names.slice(1),[names[0],names[0]],names.map(n=>({...n,stem:'../escape'})),names.map(n=>({...n,stem:'file/name'})),names.map(n=>({...n,stem:'x\u0000'}))]) assert(!validNames({status:'ok',names:bad},files));
});
test('vision and PDF contents have opaque IDs, no URL or filesystem access',()=>{
 const mixed=[{id:'file-0',file:{mime:'image/jpeg',data:Buffer.from([255,216,255,0]).toString('base64')}},{id:'file-1',file:{mime:'application/pdf',data:Buffer.from('%PDF-1.4\n').toString('base64')}}];
 assert(validNamingFiles(mixed)); const parts=namingContent(mixed); assert.equal(parts[1].type,'input_image');assert.equal(parts[3].filename,'file-1.pdf');
});
test('gateway uses database prompt, vision-compatible schema and validated proposal envelope',async()=>{
 let calls=0;
 const run=handler(async(_url,options)=>{calls++;const payload=JSON.parse(options.body);assert.equal(payload.store,false);assert.equal(payload.text.format.name,'file_names');assert.equal(payload.tools,undefined);assert.equal(payload.input[0].content[0].type,'input_text');return Response.json({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({status:'ok',names})}]}]});});
 assert.equal((await run(request({stream:true}))).status,400);assert.equal(calls,0);
 const result=await run(request());assert.equal(result.status,200);assert.deepEqual((await result.json()).names,names);
});
test('invalid provider names never become success, unauthorized calls never reach provider',async()=>{
 let calls=0;const run=handler(async()=>{calls++;return Response.json({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({status:'ok',names:[{id:'file-0',stem:'../escape'}]})}]}]});});
 assert.equal((await run(request())).status,502);
 const denied=request();denied.headers.set('Authorization','Bearer nope');assert.equal((await run(denied)).status,401);assert.equal(calls,1);
});
