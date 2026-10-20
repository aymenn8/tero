import {authenticatedUser,database,GateError,gateResponse} from '../_shared/accounts.ts';
const server={url:Deno.env.get('SUPABASE_URL'),key:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')};
Deno.serve(async request=>{
 if(request.method!=='POST')return gateResponse(new GateError('method_not_allowed',405));
 try{const user=await authenticatedUser(request,server);const raw=await request.text();if(raw.length>1024)throw new GateError('invalid_input',400);const b=JSON.parse(raw);
 if(!/^[0-9a-f-]{36}$/i.test(b.id??'')||!['action_selected','panel_opened','panel_closed','result_copied','result_pasted'].includes(b.event)
 ||b.mode!==null&&!/^[a-zA-Z_]{1,40}$/.test(b.mode??'')||!/^\d[\d.]{0,23}$/.test(b.version??'')||!/^\d[\d.]{0,31}$/.test(b.os??''))throw new GateError('invalid_input',400);
 await database(server).rpc('tero_record_event',{p_user:user,p_id:b.id,p_event:b.event,p_mode:b.mode,p_version:b.version,p_os:b.os});return new Response(null,{status:204});
 }catch(e){return gateResponse(e instanceof GateError?e:new GateError('event_unavailable'));}
});
