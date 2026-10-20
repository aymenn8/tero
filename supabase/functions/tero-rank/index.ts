import {createRankingHandler} from './handler.ts';
import {createCatalogStore} from './catalog.ts';
import {createPromptStore} from '../tero-correct/prompt-store.ts';
import {accountGateway} from '../_shared/accounts.ts';
const server={url:Deno.env.get('SUPABASE_URL'),key:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')};
Deno.serve(accountGateway({...server,kind:'rank',
 create: options=>createRankingHandler({...options,apiKey:Deno.env.get('TYPESAFE_API_KEY'),loadPrompt:createPromptStore(server),loadCatalog:createCatalogStore(server)})
}));
