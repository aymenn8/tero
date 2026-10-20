import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createPromptStore, PromptUnavailable, renderPrompt, promptVariant } from '../supabase/functions/tero-correct/prompt-store.ts';
import { translationLanguages } from '../supabase/functions/tero-correct/text-actions.ts';
import { createHandler } from '../supabase/functions/tero-correct/handler.ts';
const prompts = JSON.parse(readFileSync(new URL('./fixtures/published-prompts.json', import.meta.url)));
test('only a single published exact variant is loaded; cache refreshes and never persists selection', async () => {
  let now=0, calls=0;
  const load=createPromptStore({url:'https://db.invalid',key:'server-test-key',now:()=>now,fetcher:async (url,options)=>{
    calls++;
    assert.equal(url.pathname,'/rest/v1/ai_prompts');
    assert.equal(url.searchParams.get('mode_id'),'eq.rewrite');
    assert.equal(url.searchParams.get('variant'),'eq.professional');
    assert.equal(url.searchParams.get('state'),'eq.published');
    assert.equal(options.headers.apikey,'server-test-key');
    assert.equal(options.body,undefined);
    return Response.json([{id:calls,version:calls,instructions:'DB version '+calls}]);
  }});
  const first=await load('rewrite','professional');
  now=29999; assert.equal(await load('rewrite','professional'),first); assert.equal(calls,1);
  now=30000; assert.equal((await load('rewrite','professional')).version,2); assert.equal(calls,2);
});
test('missing, duplicate, invalid or unavailable published prompts fail closed, including after cache expiry', async()=>{
  for (const rows of [[],[{id:1,version:1,instructions:'x'},{id:2,version:2,instructions:'y'}],
    [{id:1,version:0,instructions:'x'}],[{id:1,version:1,instructions:' '}],[{id:1,version:1,instructions:'x'.repeat(32001)}]]) {
    const load=createPromptStore({url:'https://db.invalid',key:'test',fetcher:async()=>Response.json(rows)});
    await assert.rejects(load('fix','default'),PromptUnavailable);
  }
  let now=0,offline=false;
  const load=createPromptStore({url:'https://db.invalid',key:'test',now:()=>now,fetcher:async()=>{
    if(offline) throw new Error('private diagnostic'); return Response.json([{id:1,version:1,instructions:'x'}]);
  }});
  await load('fix','default');offline=true;now=30000;
  await assert.rejects(load('fix','default'),PromptUnavailable);
  await assert.rejects(load('constructor','bad variant'),PromptUnavailable);
});
test('all seeded variants render with trusted validated parameters and required placeholders',()=>{
  for(const row of prompts){
    const body={action:row.mode_id,style:row.variant,replyIntent:row.variant,responseLanguage:'en',targetLanguage:'fr',planningReference:{localDate:'2026-10-06',timeZone:'Europe/Paris'}};
    assert.equal(promptVariant(body),row.variant);
    const rendered=renderPrompt(row.instructions,body,translationLanguages,'2026-10-06');
    assert(!rendered.includes('{{'));assert(rendered.length>100);
  }
  assert.throws(()=>renderPrompt('missing target',{action:'translate',targetLanguage:'fr'},translationLanguages,'2026-10-06'),PromptUnavailable);
  assert.throws(()=>renderPrompt('{{selection}}',{action:'fix'},translationLanguages,'2026-10-06'),PromptUnavailable);
});
test('authentication and input validation precede DB lookup; lookup failure never reaches provider or leaks details',async()=>{
  const secret='private-test-secret-01234567890123456789'; let lookups=0,providers=0;
  const handler=createHandler({secret,expiresAt:Date.now()+60000,apiKey:'test',fetcher:async()=>{providers++;throw new Error('unexpected');},loadPrompt:async()=>{lookups++;throw new PromptUnavailable();}});
  const request=(token,action='fix')=>new Request('https://test.invalid',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({action,requestID:'a29e3710-4438-41bf-beb6-c1d6d20d366d',selection:'fixture'})});
  assert.equal((await handler(request('bad'))).status,401);
  assert.equal((await handler(request(secret,'unknown'))).status,400);assert.equal(lookups,0);
  const result=await handler(request(secret));assert.equal(result.status,503);
  assert.deepEqual(await result.json(),{error:'prompt_unavailable'});assert.equal(providers,0);
  assert.equal((await handler(request(secret))).status,503);assert.equal(lookups,2); // busy released
});
