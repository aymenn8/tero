import {authenticatedUser,database,gateResponse,GateError} from '../_shared/accounts.ts';
const server={url:Deno.env.get('SUPABASE_URL'),key:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')};
Deno.serve(async request=>{
 if(request.method!=='GET')return gateResponse(new GateError('method_not_allowed',405));
 try{const user=await authenticatedUser(request,server);return Response.json(await database(server).rpc('tero_account_snapshot',{p_user:user}),{headers:{'Cache-Control':'no-store'}});}
 catch(e){return gateResponse(e instanceof GateError?e:new GateError('account_unavailable'));}
});
