// No request/response content or provider error text is ever logged or persisted.
export class GateError extends Error {
  code:string; status:number;
  constructor(code:string,status=503){super(code);this.code=code;this.status=status;}
}
export function database({url,key,fetcher=fetch}) {
  async function request(path:string,body?:unknown,method='POST') {
    if(!url||!key)throw new GateError('not_configured');
    const r=await fetcher(`${url}/rest/v1/${path}`,{method,headers:{apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json',Prefer:'return=representation'},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(10000)});
    if(!r.ok)throw new GateError('account_unavailable');
    return r.status===204?null:await r.json();
  }
  return {rpc:(name:string,body:unknown)=>request(`rpc/${name}`,body),request};
}
export async function authenticatedUser(request:Request,{url,key,fetcher=fetch}) {
  const header=request.headers.get('Authorization')??'';
  if(!/^Bearer [A-Za-z0-9_.-]{40,4096}$/.test(header))throw new GateError('unauthorized',401);
  const r=await fetcher(`${url}/auth/v1/user`,{headers:{apikey:key,Authorization:header},signal:AbortSignal.timeout(6000)});
  if(r.status===401||r.status===403)throw new GateError('unauthorized',401);
  if(!r.ok)throw new GateError('auth_unavailable');
  const user=await r.json();
  if(typeof user.id!=='string'||!user.email_confirmed_at||user.is_anonymous===true)throw new GateError('unauthorized',401);
  return user.id;
}
export const gateResponse=(e:GateError)=>Response.json({error:e.code},{status:e.status,headers:{'Cache-Control':'no-store'}});
const internalSecret='internal-only-not-a-network-credential-000000000';
function providerUsage(result:any,kind:string) {
  const u=result?.usage;
  if(!Number.isSafeInteger(u?.input_tokens)||!Number.isSafeInteger(u?.output_tokens)||u.input_tokens<0||u.output_tokens<0)return null;
  return {input:u.input_tokens,output:u.output_tokens,cached:u.input_tokens_details?.cached_tokens??0,
    reasoning:u.output_tokens_details?.reasoning_tokens??0,web:kind==='rank'?0:(result.output??[]).filter((x:any)=>x.type==='web_search_call').length};
}
// Every network request requires a verified account and passes through its usage ledger.
export function accountGateway({kind,url,key,create,fetcher=fetch,now=Date.now}) {
  const db=database({url,key,fetcher});
  return async (request:Request)=>{
    if(request.method!=='POST')return gateResponse(new GateError('method_not_allowed',405));
    let user:string;
    try {user=await authenticatedUser(request,{url,key,fetcher});}catch(e){return gateResponse(e instanceof GateError?e:new GateError('auth_unavailable'));}
    let denial:GateError|undefined,call:any,providerStarted=false,usage:any,promptVersion:number|undefined;
    const started=now();
    async function finish(status:string,http:number) {
      if(!call)return;
      await db.rpc('tero_finish_call',{p_call:call.call_id,p_status:status,p_input:usage?.input??null,p_cached:usage?.cached??null,
        p_output:usage?.output??null,p_reasoning:usage?.reasoning??null,p_web:usage?.web??null,p_duration:Math.max(0,now()-started),p_http:http,p_prompt:promptVersion??null});
    }
    const auditedFetch=async (input:any,options:any)=>{
      if(!String(input).startsWith(kind==='rank'?'https://api.typesafe.ai/v1/systemone':'https://api.openai.com/v1/responses'))throw new GateError('invalid_provider');
      options.signal?.throwIfAborted();
      const payload=JSON.parse(options.body);
      // Bound binary requests by the configured context capacity, without retaining their content.
      const hasBinary=JSON.stringify(payload.input??[]).includes('data:')||JSON.stringify(payload.input??[]).includes('file_data');
      const inputBound=hasBinary?128000:new TextEncoder().encode(options.body).length;
      call=await db.rpc('tero_reserve_call',{p_user:user,p_request:requestID,p_kind:kind,p_stage:stage,p_input_tokens:inputBound});
      if(call?.error){denial=new GateError(call.error,['daily_limit','monthly_limit'].includes(call.error)?402:call.error==='duplicate_request'?409:503);throw denial;}
      const model=call?.model;
      if(!model||model.provider!==(kind==='rank'?'typesafe':'openai')){denial=new GateError('model_unavailable');throw denial;}
      payload.model=model.id;
      if(kind==='action') {
        payload.max_output_tokens=Math.min(payload.max_output_tokens,model.max_output_tokens);
        if(model.reasoning_effort)payload.reasoning={effort:model.reasoning_effort};else delete payload.reasoning;
        if(!model.web_search){delete payload.tools;delete payload.tool_choice;delete payload.max_tool_calls;}
      }
      options.signal?.throwIfAborted();
      providerStarted=true;
      const response=await fetcher(input,{...options,body:JSON.stringify(payload)});
      if(!response.ok){await finish(response.status>=400&&response.status<500?'rejected':'unknown',response.status);return response;}
      if(!payload.stream){const result=await response.clone().json();usage=providerUsage(result,kind);return response;}
      // Inline SSE observer: forwards chunks immediately, holds at most one bounded event, persists usage only.
      const reader=response.body?.getReader();const decoder=new TextDecoder();let pending='';let ended=false;
      const stream=new ReadableStream({
        async pull(controller){
          try {
            const part=await reader!.read();
            if(part.done){if(!ended){ended=true;await finish(usage?'ok':'unknown',200);}controller.close();return;}
            pending+=decoder.decode(part.value,{stream:true});pending=pending.replace(/\r\n/g,'\n');
            if(pending.length>1048576)throw new Error('event_bound');
            let boundary;
            while((boundary=pending.indexOf('\n\n'))>=0){const event=pending.slice(0,boundary);pending=pending.slice(boundary+2);
              for(const line of event.split('\n'))if(line.startsWith('data:')){try{const value=JSON.parse(line.slice(5));if(value.type==='response.completed'||value.type==='response.incomplete')usage=providerUsage(value.response,kind);}catch{}}
            }
            // Reconcile as soon as completed arrives, even if the UI subsequently cancels or closes.
            if(usage&&!ended){ended=true;await finish('ok',200);}
            controller.enqueue(part.value);
          }catch{if(!ended){ended=true;await finish('unknown',502);}controller.error(new Error('stream_failed'));}
        },async cancel(){try{await reader?.cancel();}finally{if(!ended){ended=true;await finish('unknown',499);}}}
      });
      return new Response(stream,{status:response.status,headers:response.headers});
    };
    let requestID:string,stage:string;
    try {
      // Existing handlers enforce body/format/selection limits before any provider call or quota reservation.
      const clone=request.clone();let total=0;const chunks=[];const r=clone.body?.getReader();if(!r)throw new GateError('invalid_input',400);
      while(true){const part=await r.read();if(part.done)break;total+=part.value.length;if(total>5400000){await r.cancel();throw new GateError('too_long',413);}chunks.push(part.value);}
      const bytes=new Uint8Array(total);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}
      const body=JSON.parse(new TextDecoder().decode(bytes));
      requestID=body.requestID;stage=kind==='rank'?'rank_actions':body.action;
      if(!/^[0-9a-f-]{36}$/i.test(requestID)||typeof stage!=='string')throw new GateError('invalid_input',400);
      const headers=new Headers(request.headers);headers.set('Authorization',`Bearer ${internalSecret}`);
      const inner=new Request(request,{headers});
      const handler=create({secret:internalSecret,expiresAt:now()+120000,fetcher:auditedFetch,onPrompt:(version:number)=>{promptVersion=version;},modelID:()=>call?.model?.id,costUSD:(tokens:number)=>tokens*(call?.model?.input_usd_per_million??0.042)/1000000});
      const response=await handler(inner);
      if(denial){if(call?.call_id&&!providerStarted)await finish('rejected',denial.status);return gateResponse(denial);}
      if(call&&response.headers.get('Content-Type')?.startsWith('application/x-ndjson')!==true)await finish(usage?(response.ok?'ok':'failed'):providerStarted?'unknown':'rejected',response.status);
      return response;
    }catch(e){try{await finish(providerStarted?'unknown':'rejected',503);}catch{}return gateResponse(e instanceof GateError?e:new GateError('account_unavailable'));}
  };
}
