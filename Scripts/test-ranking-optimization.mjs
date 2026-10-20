import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRankingHandler,observedState,MODEL} from '../supabase/functions/tero-rank/handler.ts';
const sql=readFileSync(new URL('../supabase/migrations/20261008193215_compact_jev_ranking_prompt.sql',import.meta.url),'utf8');
const prompt=sql.split('$prompt$')[1];
assert(prompt && prompt.length < 600);
const secret='synthetic-optimization-authentication-00000000000000';
const personal='habit_00000000-0000-0000-0000-000000000002';
const observed={kind:'text',selection:'I shipped my Mac app today.',editable:true,surface:'writing',elementLabel:'Post text',elementDescription:'Post text',elementPlaceholder:'',nearbyText:'I shipped my Mac app today.',containers:[{role:'AXGroup',label:''},{role:'AXGroup',label:'Compose'},{role:'AXGroup',label:'Compose'},{role:'AXWebArea',label:''}],limitations:['ancestorLimitReached']};
const cleaned=observedState(observed);
assert.equal(cleaned.elementDescription,undefined);assert.equal(cleaned.nearbyText,undefined);assert.equal(cleaned.elementPlaceholder,undefined);
assert.deepEqual(cleaned.containers,[{role:'AXGroup',label:'Compose'},{role:'AXWebArea'}]);
assert.equal(cleaned.editable,true);assert.deepEqual(cleaned.limitations,['ancestorLimitReached']);
assert.equal(observed.containers.length,4); // Never mutate the captured observation.
assert.equal(observedState({...observed,nearbyText:'Conversation before the selected draft.'}).nearbyText,'Conversation before the selected draft.');
assert.equal(observedState({...observed,elementDescription:'A distinct description.'}).elementDescription,'A distinct description.');
assert.equal(observedState({...observed,containers:Array(15).fill({role:'AXGroup',label:''})}).containers,undefined);
assert.equal(observedState({...observed,editable:false}).editable,false);
async function capture(body,catalog) {
 let sent;
 const handler=createRankingHandler({secret,expiresAt:Date.now()+60000,apiKey:'synthetic',loadCatalog:async()=>catalog,loadPrompt:async()=>({version:3,instructions:prompt}),fetcher:async(_,options)=>{
  sent=JSON.parse(options.body);
  const answers=Object.fromEntries(body.candidates.map(id=>[id,{type:'score',score:2,confidence:1,probabilities:{0:0,1:0,2:1,3:0}}]));
  return Response.json({model:MODEL,answers,usage:{input_tokens:100,output_tokens:10}});
 }});
 const response=await handler(new Request('https://example.com',{method:'POST',headers:{Authorization:`Bearer ${secret}`,'Content-Type':'application/json'},body:JSON.stringify({...body,requestID:'00000000-0000-0000-0000-000000000001'})}));
 assert.equal(response.status,200);assert.equal((await response.json()).promptVersion,3);
 assert.deepEqual(Object.keys(sent.questions),body.candidates);
 return sent;
}
const habit={id:personal,name:'Founder tweet',description:'Rewrite a draft as a concise, natural founder tweet.',instruction:'Rewrite selected text. Preserve all facts. Return only the rewritten text.'};
const catalog=new Map([['fix',{title:'Correct',description:'Fix spelling and grammar.'}]]);
let sent=await capture({candidates:['fix',personal],context:observed,personalActions:[habit]},catalog);
assert.equal(sent.questions[personal].instructions.action.description,habit.description);
assert(!JSON.stringify(sent).includes(habit.instruction));
assert.deepEqual(sent.questions.fix.criteria,sent.questions[personal].criteria);
sent=await capture({candidates:['fix',personal],context:observed,personalActions:[{...habit,description:'  '}]},catalog);
assert.equal(sent.questions[personal].instructions.action.description,habit.instruction);
console.log('PASS: compact prompt, meaningful context, native/personal parity, legacy description fallback and unchanged candidate coverage');
if(process.argv[2]) {
 // User trace stays in memory. Only request sizes and structural counts are printed.
 const trace=readFileSync(process.argv[2],'utf8');
 const request=JSON.parse(trace.split('Jev request (JSON body, no credentials)\n')[1].split('\n\nJev response (validated scores and probabilities)')[0]);
 const personalActions=Object.entries(request.questions).filter(([id])=>id.startsWith('habit_')).map(([id,q])=>{
  const [description,instruction]=q.instructions.action.description.split('\nExecution rules: ');
  return {id,name:q.instructions.action.title,description,instruction:instruction||description};
 });
 // Map native ids exactly as the runtime does, using the trace's definitions.
 const {ACTIONS}=await import('../supabase/functions/tero-rank/handler.ts');
 const nativeCatalog=new Map(Object.entries(request.questions).filter(([id])=>!id.startsWith('habit_')).map(([id,q])=>[ACTIONS[id],q.instructions.action]));
 const compact=await capture({candidates:Object.keys(request.questions),context:request.state,personalActions},nativeCatalog);
 const before=Buffer.byteLength(JSON.stringify(request)),after=Buffer.byteLength(JSON.stringify(compact));
 console.log(JSON.stringify({candidates:Object.keys(compact.questions).length,beforeBytes:before,afterBytes:after,reductionPercent:Math.round(100*(1-after/before)),taskBeforeCharacters:Object.values(request.questions)[0].instructions.task.length,taskAfterCharacters:prompt.length}));
}
