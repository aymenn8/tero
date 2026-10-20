import assert from 'node:assert/strict';
import {accountGateway,authenticatedUser} from '../supabase/functions/_shared/accounts.ts';
import {createHandler} from '../supabase/functions/tero-correct/handler.ts';
let userCalls=0,providerCalls=0,ledger=[],reserveError,failProvider=false,stream=false;
const model={id:'configurable-test-model',provider:'openai',max_output_tokens:1024,reasoning_effort:'none',web_search:true,input_usd_per_million:0.1};
const user='00000000-0000-0000-0000-000000000001',credential='a'.repeat(60);
const response={status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({status:'ok',text:'Corrected.'})}]}],usage:{input_tokens:100,output_tokens:20,input_tokens_details:{cached_tokens:25},output_tokens_details:{reasoning_tokens:4}}};
const mock=async(url,options)=>{
 if(url.endsWith('/auth/v1/user')){userCalls++;return options.headers.Authorization===`Bearer ${credential}`?Response.json({id:user,email_confirmed_at:'2026-10-01',is_anonymous:false}):Response.json({error:'invalid'},{status:401});}
 if(url.endsWith('/rpc/tero_reserve_call')){ledger.push(['reserve',JSON.parse(options.body)]);return Response.json(reserveError?{error:reserveError}:{call_id:user,model,plan:'free'});}
 if(url.endsWith('/rpc/tero_finish_call')){ledger.push(['finish',JSON.parse(options.body)]);return Response.json(null);}
 if(url==='https://api.openai.com/v1/responses'){
 providerCalls++;const body=JSON.parse(options.body);assert.equal(body.model,model.id);assert.equal(body.max_output_tokens,1024);assert.equal(body.store,false);
 if(failProvider)throw new Error('provider private content must not leak');
 if(stream){return new Response(`data: ${JSON.stringify({type:'response.output_text.delta',delta:'{"status":"ok","text":"Corrected."}'})}\n\ndata: ${JSON.stringify({type:'response.completed',response})}\n\n`,{headers:{'Content-Type':'text/event-stream'}});}
 return Response.json(response);
 }throw new Error('Unexpected endpoint');
};
const gateway=accountGateway({kind:'action',url:'https://example.supabase.co',key:'server-secret',fetcher:mock,create:options=>createHandler({...options,apiKey:'private',loadPrompt:async()=>({version:7,instructions:'Correct spelling'})})});
const request=(token=credential,extra={})=>new Request('https://example.com',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({requestID:user,action:'fix',selection:'Private customer sentence.',...extra})});
// Signed-out, malformed and formerly privileged credentials must never reserve quota or call AI.
for (const kind of ['action','rank']) {
 const legacy='legacy-development-bearer-'.padEnd(60,'x');
 const protectedGateway=accountGateway({kind,url:'https://example.supabase.co',key:'server-secret',fetcher:mock,
   devSecret:legacy,devExpires:Date.now()+60000,
   create:()=>{throw new Error('Unauthenticated request reached handler');}});
 for (const token of [undefined,'', 'invalid', legacy, 'b'.repeat(60)]) {
  const req=request(token??''); if(token===undefined)req.headers.delete('Authorization');
  assert.equal((await protectedGateway(req)).status,401);
  assert.equal(providerCalls,0);assert.equal(ledger.length,0);
 }
 for (const identity of [{id:user,is_anonymous:true,email_confirmed_at:'2026-10-01'}, {id:user,is_anonymous:false}]) {
  const denied=accountGateway({kind,url:'https://example',key:'key',fetcher:async()=>Response.json(identity),
   create:()=>{throw new Error('Unverified identity reached handler');}});
  assert.equal((await denied(request())).status,401);
 }
}

assert.equal((await gateway(request(credential,{action:'unknown'}))).status,400);assert.equal(providerCalls,0);assert.equal(ledger.length,0);
reserveError='daily_limit';assert.equal((await gateway(request())).status,402);assert.equal(providerCalls,0);
reserveError=undefined;ledger=[];
assert.equal((await gateway(request())).status,200);assert.equal(providerCalls,1);
const finished=ledger.find(x=>x[0]==='finish')[1];assert.equal(finished.p_input,100);assert.equal(finished.p_cached,25);assert.equal(finished.p_output,20);assert.equal(finished.p_reasoning,4);assert.equal(finished.p_prompt,7);assert.equal(finished.p_status,'ok');
assert.ok(!JSON.stringify(ledger).includes('customer'));assert.ok(!JSON.stringify(ledger).includes('Corrected'));assert.ok(!JSON.stringify(ledger).includes('private'));
ledger=[];failProvider=true;const failure=await gateway(request());assert.equal(failure.status,502);assert.equal(ledger.find(x=>x[0]==='finish')[1].p_status,'unknown');assert.ok(!(await failure.text()).includes('private'));
failProvider=false;stream=true;ledger=[];const streamed=await gateway(request(credential,{stream:true}));const content=await streamed.text();assert.ok(content.includes('"type":"done"'));assert.equal(ledger.find(x=>x[0]==='finish')[1].p_input,100);
await assert.rejects(authenticatedUser(request(),{url:'https://example',key:'key',fetcher:async()=>Response.json({id:user,is_anonymous:true})}));
console.log('PASS: verified identity, denied quota before provider, DB model routing, price-independent usage, sanitized errors, SSE accounting and content-free ledger');
