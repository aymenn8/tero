import test from 'node:test';
import { readFileSync } from 'node:fs';
const prompts = JSON.parse(readFileSync(new URL('./fixtures/published-prompts.json', import.meta.url)));
const loadPrompt = async (mode, variant) => prompts.find(p => p.mode_id === mode && p.variant === variant);
import assert from 'node:assert/strict';
import { createHandler } from '../supabase/functions/tero-correct/handler.ts';
import { previewJSON } from '../supabase/functions/tero-correct/reading-stream.ts';
const secret = 'synthetic-stream-test-credential-012345678901234567890';
const id = 'a29e3710-4438-41bf-beb6-c1d6d20d366d';
const request = (action='ask', overrides={}) => new Request('https://test.invalid',{method:'POST',
 headers:{Authorization:`Bearer ${secret}`,'Content-Type':'application/json'},
 body:JSON.stringify({action,requestID:id,selection:'What is a cache?',stream:true,...overrides})});
const result = (text='A cache stores reusable data.') => ({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({status:'ok',text})}]}]});
const encode = event => 'data: '+JSON.stringify(event)+'\r\n\r\n';
const upstream = events => {
 const bytes = new TextEncoder().encode(events.map(encode).join(''));
 return new Response(new ReadableStream({start(c){for(let i=0;i<bytes.length;i+=7)c.enqueue(bytes.slice(i,i+7));c.close();}}));
};
const handler = fetcher => createHandler({secret,expiresAt:Date.now()+60000,apiKey:'fixture',fetcher,loadPrompt});
test('progress is actual provider output; completion is validated and metadata stays private',async()=>{
 const h=handler(async(_,options)=>{
 const p=JSON.parse(options.body);assert.equal(p.stream,true);assert.equal(p.store,false);assert.equal(p.model,'gpt-6-luna');
 assert(p.instructions.includes('200 words'));assert.equal(p.tools[0].type,'web_search');assert.equal(p.text.format.type,'text');assert(p.instructions.includes('language of their question'));
 return upstream([{type:'response.created',response:{private:'never exposed'}},
 {type:'response.output_text.delta',delta:'A cache'},
 {type:'response.output_text.delta',delta:' stores reusable data.'},
 {type:'response.completed',response:{status:'completed',output:[{type:'message',content:[{type:'output_text',text:'A cache stores reusable data.'}]}]}}]);});
 const response=await h(request());assert.equal(response.headers.get('content-type'),'application/x-ndjson; charset=utf-8');
 const events=(await response.text()).trim().split('\n').map(JSON.parse);
 assert.equal(events[0].type,'progress');assert.equal(events[0].text,'A cache');
 assert.deepEqual(events.at(-1),{requestID:id,type:'done',text:'A cache stores reusable data.'});
 assert(!JSON.stringify(events).includes('private'));
});
test('escaped strings, split Unicode and points decode without exposing transport JSON',()=>{
 assert.equal(previewJSON('{"status":"ok","text":"line\\nquote\\" café\\u00','ask'),'line\nquote" café');
 assert.equal(previewJSON('{"status":"ok","points":["First", "Sec','key_points'),'- First\n- Sec');
 assert.equal(previewJSON('{"status":"ok","tasks":[{"action":"Review links","owner":null','extract_tasks'),'- Review links');
});
test('incomplete, invalid and refused streams never emit done',async()=>{
 for(const ending of [[],[{type:'response.incomplete'}],[{type:'response.completed',response:result('')}],
 [{type:'response.refusal.delta',delta:'no'}]]){
 const response=await handler(async()=>upstream([{type:'response.output_text.delta',delta:'{"text":"partial'},...ending]))(request('explain'));
 const events=(await response.text()).trim().split('\n').map(JSON.parse);
 assert.equal(events.at(-1).type,'error');assert(!events.some(e=>e.type==='done'));
 }
});
test('busy guard remains held while streaming; cancellation releases it',async()=>{
 let controller;
 const h=handler(async()=>new Response(new ReadableStream({start(c){controller=c;}})));
 const first=await h(request());assert.equal((await h(request())).status,429);
 await first.body.cancel();
 await new Promise(r=>setTimeout(r,0));
 const second=await h(request());assert.equal(second.status,200);await second.body.cancel();
});
test('streaming remains behind authentication and validates intent/options',async()=>{
 let calls=0;const h=handler(async()=>{calls++;return upstream([]);});
 const unauthorized=request();unauthorized.headers.set('Authorization','Bearer wrong');
 assert.equal((await h(unauthorized)).status,401);
 assert.equal((await h(request('reply_options'))).status,400);
 assert.equal((await h(request('ask',{stream:'true'}))).status,400);assert.equal(calls,0);
});

test('Ask web citations become clickable links; invented/unsafe URLs do not become sources',async()=>{
 const marker='citeturn0search0';const prose='An update was published. '+marker;
 const webResult={status:'completed',output:[{type:'web_search_call',action:{type:'search'}},
 {type:'message',content:[{type:'output_text',text:prose,annotations:[
 {type:'url_citation',url:'https://example.org/news',title:'Official update',start_index:prose.indexOf(marker),end_index:prose.indexOf(marker)+[...marker].length},
 {type:'url_citation',url:'javascript:alert(1)',title:'Unsafe',start_index:0,end_index:2}]}]}]};
 const h=handler(async()=>upstream([{type:'response.output_text.delta',delta:prose},{type:'response.completed',response:webResult}]));
 const events=(await (await h(request())).text()).trim().split('\n').map(JSON.parse);
 assert(!events[0].text.includes(''));
 assert.equal(events.at(-1).type,'done');
 assert(events.at(-1).text.includes('[1](https://example.org/news)'));
 assert(events.at(-1).text.includes('[1 · Official update](https://example.org/news)'));
 assert(!events.at(-1).text.includes('javascript'));
});
test('completed Ask accepts missing source metadata; other modes have no search tool',async()=>{
 const searched={status:'completed',output:[{type:'web_search_call'}, {type:'message',content:[{type:'output_text',text:'Uncited news'}]}]};
 const response=await handler(async()=>upstream([{type:'response.completed',response:searched}]))(request());
 const answer=JSON.parse((await response.text()).trim());
 assert.equal(answer.type,'done');assert.equal(answer.text,'Uncited news');
 const h=handler(async(_,options)=>{
 const payload=JSON.parse(options.body);assert.equal(payload.tools,undefined);assert.equal(payload.text.format.type,'json_schema');
 return upstream([{type:'response.completed',response:result('A stable explanation.')}]);});
 const events=(await (await h(request('explain'))).text()).trim().split('\n').map(JSON.parse);
 assert.equal(events.at(-1).type,'done');
});

test('weather feed completes without URL citations, with explicit provider attribution',async()=>{
 const weather={status:'completed',output:[{type:'web_search_call',action:{type:'search',sources:[{type:'api',name:'oai-weather'}]}},
 {type:'message',content:[{type:'output_text',text:'It will be cool tomorrow, with showers possible.',annotations:[]}]}]};
 const h=handler(async(_,options)=>{assert.deepEqual(JSON.parse(options.body).include,['web_search_call.action.sources']);return upstream([
 {type:'response.output_text.delta',delta:weather.output[1].content[0].text},{type:'response.completed',response:weather}]);});
 const events=(await (await h(request())).text()).trim().split('\n').map(JSON.parse);
 assert.equal(events.at(-1).type,'done');assert(events.at(-1).text.includes('Source: OpenAI weather feed.'));
});
test('Ask tolerates unsupported source metadata; uncited claims remain rejected',async()=>{
 for(const [source,action,expected] of [
 [{type:'url',url:'https://example.org/weather'},'ask','done'],
 [{type:'api',name:'unknown'},'ask','done'],
 [{type:'api',name:'oai-weather'},'check_claim','error']]){
 const r={status:'completed',output:[{type:'web_search_call',action:{sources:[source]}},
 {type:'message',content:[{type:'output_text',text:'Prepared answer.'}]}]};
 const events=(await (await handler(async()=>upstream([{type:'response.completed',response:r}]))(request(action))).text()).trim().split('\n').map(JSON.parse);
 assert.equal(events.at(-1).type,expected);
 }
});
test('interim search commentary does not invalidate the final answer',async()=>{
 const r={status:'completed',output:[{type:'message',phase:'commentary',content:[{type:'output_text',text:'Let me check.'}]},
 {type:'message',phase:'final_answer',content:[{type:'output_text',text:'The completed answer.'}]}]};
 const events=(await (await handler(async()=>upstream([{type:'response.completed',response:r}]))(request())).text()).trim().split('\n').map(JSON.parse);
 assert.equal(events.at(-1).type,'done');assert.equal(events.at(-1).text,'The completed answer.');
});

test('Miami time answer finishes after visible progress even without citations',async()=>{
 const text="It's 7:13 PM in Miami.";
 const r={status:'completed',output:[{type:'web_search_call',status:'completed',action:{type:'search'}},
 {type:'message',phase:'final_answer',content:[{type:'output_text',text,annotations:[]}]}]};
 const events=(await (await handler(async()=>upstream([
 {type:'response.output_text.delta',delta:text},{type:'response.completed',response:r}]))(request())).text()).trim().split('\n').map(JSON.parse);
 assert.equal(events[0].type,'progress');assert.equal(events[0].text,text);
 assert.equal(events.at(-1).type,'done');assert.equal(events.at(-1).text,text);
 assert(!events.some(event=>event.type==='error'));
});
