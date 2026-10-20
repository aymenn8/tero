import {createShoppingHandler} from './handler.ts';
import {createPromptStore} from '../tero-correct/prompt-store.ts';
import {accountGateway} from '../_shared/accounts.ts';
const server={url:Deno.env.get('SUPABASE_URL'),key:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')};
// Shopping uses the existing metered Ask web-search route and reservation bounds.
Deno.serve(accountGateway({...server,kind:'action',create:options=>createShoppingHandler({...options,
 apiKey:Deno.env.get('OPENAI_API_KEY'),loadPrompt:createPromptStore(server),imageOptions:{
  resolve:async host=>{const records=await Promise.allSettled([Deno.resolveDns(host,'A'),Deno.resolveDns(host,'AAAA')]);
   return records.flatMap(r=>r.status==='fulfilled'?r.value:[]);}
 }})}));
