// Rebuilds a client ranking request with tero-rank and compares it with the provider body
// JevClient sent from the Mac. Usage: node --experimental-strip-types Scripts/test-jev-parity.mjs <request.json> <sent.json>
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRankingHandler,MODEL} from '../supabase/functions/tero-rank/handler.ts';
const [requestPath,sentPath]=process.argv.slice(2);
const read=path=>JSON.parse(readFileSync(path,'utf8'));
const prompts=read(new URL('../Resources/AI/Prompts.json',import.meta.url));
const catalog=new Map(Object.entries(read(new URL('../Resources/AI/RankingCatalog.json',import.meta.url))));
const body=read(requestPath),swift=read(sentPath);
let server;
const secret='x'.repeat(50);
const handler=createRankingHandler({secret,expiresAt:Date.now()+60000,apiKey:'k',loadCatalog:async()=>catalog,
  loadPrompt:async()=>prompts['rank_actions:default'],
  fetcher:async(url,options)=>{server=JSON.parse(options.body);return Response.json({});}});
await handler(new Request('https://example.com',{method:'POST',headers:{Authorization:`Bearer ${secret}`,'Content-Type':'application/json'},body:JSON.stringify(body)}));
assert.ok(server,'tero-rank accepted the client request');
assert.equal(swift.model,MODEL,'model matches tero-rank');
assert.deepEqual(swift,server);
console.log('Jev request parity OK');
