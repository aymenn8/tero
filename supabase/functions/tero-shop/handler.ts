import { productSchema, productsFromResponse } from './products.ts';
import { productImage } from './images.ts';
import { renderPrompt, PromptUnavailable } from '../tero-correct/prompt-store.ts';
export function createShoppingHandler({secret,expiresAt,apiKey,fetcher=fetch,loadPrompt,onPrompt=()=>{},now=Date.now,imageOptions}) {
  const reply=(status,body)=>Response.json(body,{status,headers:{'Cache-Control':'no-store'}});
  return async request=>{
    if(request.method!=='POST')return reply(405,{error:'method_not_allowed'});
    if(!secret||secret.length<40||now()>=expiresAt||!apiKey)return reply(503,{error:'not_configured'});
    if(request.headers.get('Authorization')!==`Bearer ${secret}`)return reply(401,{error:'unauthorized'});
    if(!request.headers.get('Content-Type')?.startsWith('application/json'))return reply(415,{error:'invalid_input'});
    let body;
    try {
      const reader=request.body?.getReader();if(!reader)throw Error();
      let source='',size=0;const decoder=new TextDecoder();
      while(true){const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>32768){await reader.cancel();return reply(413,{error:'too_long'});}source+=decoder.decode(part.value,{stream:true});}
      body=JSON.parse(source);
    }catch{return reply(400,{error:'invalid_input'});}
    if(body.action!=='ask'||typeof body.selection!=='string'||[...body.selection].length>4000
      ||typeof body.requestID!=='string'||!/^[0-9a-f-]{36}$/i.test(body.requestID)||body.stream||body.file||body.files)return reply(400,{error:'invalid_input'});
    let input;try{input=JSON.parse(body.selection);}catch{return reply(400,{error:'invalid_input'});}
    if(!input||typeof input.request!=='string'||!input.request.trim()||input.request.length>3000
      ||typeof input.preferences!=='string'||input.preferences.length>600||typeof input.locale!=='string'||input.locale.length>40)return reply(400,{error:'invalid_input'});
    try {
      const signal=AbortSignal.any([request.signal,AbortSignal.timeout(55000)]);
      const prompt=await loadPrompt('shop','default',signal);onPrompt(prompt.version);
      const response=await fetcher('https://api.openai.com/v1/responses',{
        method:'POST',signal,headers:{Authorization:`Bearer ${apiKey}`,'Content-Type':'application/json'},
        body:JSON.stringify({model:'gpt-6-luna',store:false,stream:false,reasoning:{effort:'none'},
          instructions:renderPrompt(prompt.instructions,{action:'ask'},new Map(),new Date(now()).toISOString().slice(0,10)),
          input:[{role:'user',content:JSON.stringify(input)}],
          tools:[{type:'web_search',search_context_size:'low',external_web_access:true}],tool_choice:'required',max_tool_calls:2,
          include:['web_search_call.action.sources'],max_output_tokens:1600,
          text:{format:{type:'json_schema',name:'shopping_products',strict:true,schema:productSchema}}
        })});
      if(!response.ok)return reply(response.status===429?429:502,{error:'provider_error'});
      const value=productsFromResponse(await response.json());
      if(!value)return reply(502,{error:'unverified_products'});
      // Images come from the verified product page metadata, never a generated image URL.
      await Promise.all(value.products.map(async p=>{p.imageURL=await productImage(p.url,imageOptions??{});}));
      return reply(200,{requestID:body.requestID,...value});
    }catch(e){return reply(e instanceof PromptUnavailable?503:502,{error:e instanceof PromptUnavailable?'prompt_unavailable':'search_failed'});}
  };
}
