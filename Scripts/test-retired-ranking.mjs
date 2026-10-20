import test from 'node:test';
import assert from 'node:assert/strict';
import {createRankingHandler,validRequest,ACTIONS,RETIRED_ACTIONS,MODEL} from '../supabase/functions/tero-rank/handler.ts';

const secret='synthetic-retired-ranking-credential-0123456789012345678901';
const context={kind:'files',files:[{name:'invoice.pdf',type:'com.adobe.pdf',bytes:1200}]};
const catalog=new Map([['rename_file',{title:'Rename',description:'Rename one file.',when_to_offer:'One file.',when_to_avoid:'Text.'}],
  ['move_files',{title:'Move files',description:'Move files to a folder.',when_to_offer:'Files.',when_to_avoid:'Text.'}]]);
function makeHandler(onSend) {
  return createRankingHandler({secret,expiresAt:Date.now()+60000,apiKey:'synthetic',loadCatalog:async()=>catalog,
    loadPrompt:async()=>({version:3,instructions:'Score each action.'}),fetcher:async(_,options)=>{
      const sent=JSON.parse(options.body); onSend(sent);
      const answers=Object.fromEntries(Object.keys(sent.questions).map(id=>[id,{type:'score',score:2,confidence:1,probabilities:{0:0,1:0,2:1,3:0}}]));
      return Response.json({model:MODEL,answers,usage:{input_tokens:10,output_tokens:2}});
    }});
}
const call=(handler,candidates)=>handler(new Request('https://test.invalid',{method:'POST',
  headers:{Authorization:`Bearer ${secret}`,'Content-Type':'application/json'},
  body:JSON.stringify({requestID:'00000000-0000-0000-0000-000000000002',candidates,context})}));

test('retired file utilities are no longer catalog actions',()=>{
  for(const id of RETIRED_ACTIONS) assert(!Object.hasOwn(ACTIONS,id),id);
  assert(validRequest({requestID:'00000000-0000-0000-0000-000000000002',candidates:['renameFile','convert'],context}));
});

test('released clients sending retired ids keep exact coverage without reaching the provider',async()=>{
  let sent;
  const response=await call(makeHandler(value=>{sent=value;}),['renameFile','compressFiles','moveFiles','resize']);
  assert.equal(response.status,200);
  assert.deepEqual(Object.keys(sent.questions),['renameFile','moveFiles']);
  const {scores}=await response.json();
  assert.deepEqual(scores.map(s=>s.id),['renameFile','compressFiles','moveFiles','resize']);
  assert.equal(scores[1].score,0); assert.equal(scores[3].score,0); assert.equal(scores[0].score,2);
});

test('only retired candidates are answered locally',async()=>{
  let called=false;
  const response=await call(makeHandler(()=>{called=true;}),['convert','resize']);
  assert.equal(response.status,200); assert.equal(called,false);
  const body=await response.json();
  assert.deepEqual(body.scores.map(s=>[s.id,s.score]),[['convert',0],['resize',0]]);
  assert.equal(body.usage.inputTokens,0);
});
