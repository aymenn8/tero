// Jev is a replaceable ranking adapter; it never creates capabilities or executes actions.
export const MODEL = 'jev-1.13.0';
export const ACTIONS = Object.freeze({
  shop:'shop', renameFile:'rename_file', batchRename:'batch_rename', moveFiles:'move_files',
  openMaps:'open_maps', directions:'directions', convertUnits:'convert_units',
  convertCurrencies:'convert_currencies', convertTimeZones:'convert_time_zones', checkClaim:'check_claim', tone:'tone',
  simplify:'simplify', improvePrompt:'improve_prompt', cleanFormatting:'clean_formatting', changeCase:'change_case', calculate:'calculate', rewrite:'rewrite',
  explain:'explain', translate:'translate', keyPoints:'key_points', extractTasks:'extract_tasks', fix:'fix', reply:'reply',
  summarizeFile:'summarize_file',
  createTasks:'task_plan', createEvent:'event_plan',
});
// Removed from the app on 13 October. Released builds may still send them; they are scored
// as unsupported without reaching the provider, so exact candidate coverage still holds.
export const RETIRED_ACTIONS = Object.freeze(new Set(['compressFiles','extractArchive','compressImages','extractText',
  'mergePDFs','extractPDFPages','convertDocument','convert','resize']));
const retiredScore = id => ({id,score:0,confidence:1,probabilities:{'0':1,'1':0,'2':0,'3':0}});
const levels = [
  'Unsupported, inappropriate, or unrelated to the observed content.',
  'Possible generic use, but no evidence of this immediate intent.',
  'Useful next step supported by the selected content and context.',
  'Especially fitting next step supported by specific content or context.',
];
const bounded = (value, max) => value === undefined || value === null || typeof value === 'string' && [...value].length <= max;
const personalID = id => /^habit_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
export function validPersonalActions(body) {
  const actions = body.personalActions ?? [];
  return Array.isArray(actions) && actions.length <= 50 && new Set(actions.map(a=>a?.id)).size === actions.length
    && actions.every(a=>a && personalID(a.id) && body.candidates?.includes(a.id)
      && typeof a.name === 'string' && a.name.trim() && bounded(a.name,40)
      && typeof a.instruction === 'string' && a.instruction.trim() && bounded(a.instruction,1000)
      && bounded(a.description,1000) && (a.operation === undefined || ['rename','move'].includes(a.operation))
      && (a.operation === undefined || body.context?.kind === 'files')
      && Object.keys(a).every(key=>['id','name','instruction','description','operation'].includes(key)))
    && (body.candidates ?? []).filter(personalID).every(id=>actions.some(a=>a.id===id));
}
export function validRequest(body) {
  if (!body || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.requestID ?? '')
    || !Array.isArray(body.candidates) || body.candidates.length < 2 || body.candidates.length > Object.keys(ACTIONS).length + RETIRED_ACTIONS.size + 50
    || new Set(body.candidates).size !== body.candidates.length || body.candidates.some(id => !Object.hasOwn(ACTIONS,id) && !RETIRED_ACTIONS.has(id) && !personalID(id)) || !validPersonalActions(body)) return false;
  if (body.debug !== undefined && typeof body.debug !== 'boolean') return false;
  const state = body.context;
  if (!state || !['text','files'].includes(state.kind) || !bounded(state.selection,2000)
    || !bounded(state.applicationID,180) || !bounded(state.applicationName,120) || !bounded(state.windowTitle,160)
    || !bounded(state.elementDescription,256) || !bounded(state.elementPlaceholder,256)
    || !bounded(state.surface,20) || !bounded(state.capture,30)
    || !(state.limitations === undefined || Array.isArray(state.limitations) && state.limitations.length <= 8 && state.limitations.every(s=>typeof s === 'string' && bounded(s,40)))
    || !(state.containers === undefined || Array.isArray(state.containers) && state.containers.length <= 15 && state.containers.every(c=>c && typeof c.role === 'string' && bounded(c.role,80) && bounded(c.label,160)))
    || !bounded(state.elementRole,80) || !bounded(state.elementLabel,160) || !bounded(state.webHost,253)
    || !bounded(state.preferredLanguage,10) || !bounded(state.nearbyText,800) || !bounded(state.localDate,10) || !bounded(state.timeZone,80)
    || ![true,false,null,undefined].includes(state.editable)) return false;
  if (state.kind === 'text') return typeof state.selection === 'string' && !!state.selection.trim() && state.files === undefined;
  return state.selection === undefined && Array.isArray(state.files) && state.files.length > 0 && state.files.length <= 20
    && state.files.every(f => f && typeof f.name === 'string' && bounded(f.name,160) && bounded(f.type,120)
      && (f.bytes === undefined || Number.isSafeInteger(f.bytes) && f.bytes >= 0));
}
// Explicit allowlist: extra client properties, paths and instructions never reach the provider.
export function observedState(input) {
  const keys = ['kind','selection','applicationID','applicationName','windowTitle','elementRole','elementLabel','elementDescription','elementPlaceholder','surface','capture','limitations','webHost','nearbyText','editable','preferredLanguage','localDate','timeZone'];
  const state = Object.fromEntries(keys.filter(k => input[k] !== undefined && input[k] !== null && input[k] !== '' && !(Array.isArray(input[k]) && input[k].length === 0)).map(k => [k,input[k]]));
  // Repeated wrapper groups have no meaning; keep labels and useful structural roles.
  if (input.containers) {
    const containers=[];
    for (const c of input.containers) {
      const label=c.label?.trim();
      if (!label && c.role === 'AXGroup') continue;
      const observation={role:c.role,...(label ? {label} : {})};
      const previous=containers.at(-1);
      if (previous?.role === observation.role && previous?.label === observation.label) continue;
      containers.push(observation);
    }
    if (containers.length) state.containers=containers;
  }
  if (state.elementDescription === state.elementLabel) delete state.elementDescription;
  if (state.elementPlaceholder === state.elementLabel || state.elementPlaceholder === state.elementDescription) delete state.elementPlaceholder;
  if (state.nearbyText?.trim() === state.selection?.trim()) delete state.nearbyText;
  if (input.kind === 'files') state.files = input.files.map(f => Object.fromEntries(['name','type','bytes'].filter(k => f[k] !== undefined).map(k => [k,f[k]])));
  return state;
}
export function validAnswers(result, ids, model=MODEL) {
  if (result?.model !== model || !result.answers || Object.keys(result.answers).length !== ids.length) return false;
  return ids.every(id => {
    const a = result.answers[id];
    if (a?.type !== 'score' || !Number.isFinite(a.score) || a.score < 0 || a.score > 3
      || !Number.isFinite(a.confidence) || a.confidence < 0 || a.confidence > 1
      || !a.probabilities || Object.keys(a.probabilities).length !== 4) return false;
    const p = [0,1,2,3].map(n => a.probabilities[String(n)]);
    return p.every(n => Number.isFinite(n) && n >= 0 && n <= 1)
      && Math.abs(p.reduce((a,b) => a+b,0)-1) <= 0.025
      && Math.abs(p.reduce((a,b,i) => a+b*i,0)-a.score) <= 0.04;
  }) && Number.isSafeInteger(result.usage?.input_tokens) && result.usage.input_tokens >= 0
    && Number.isSafeInteger(result.usage?.output_tokens) && result.usage.output_tokens >= 0;
}
export function createRankingHandler({ secret, expiresAt, apiKey, loadCatalog, loadPrompt, fetcher=fetch, now=Date.now, onPrompt=()=>{}, modelID=()=>MODEL, costUSD=tokens=>tokens*0.042/1000000 }) {
  let active = 0; let calls = [];
  const reply = (status, body) => Response.json(body,{status,headers:{'Cache-Control':'no-store'}});
  const fail = (status,code) => reply(status,{error:code});
  return async request => {
    if (request.method !== 'POST') return fail(405,'method_not_allowed');
    if (!secret || secret.length < 40 || !Number.isFinite(expiresAt) || now() >= expiresAt) return fail(503,'not_configured');
    const supplied = request.headers.get('Authorization') ?? '';
    if (supplied.length > 512) return fail(401,'unauthorized');
    const hash = async s => new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s)));
    const [a,b] = await Promise.all([hash(supplied),hash(`Bearer ${secret}`)]);
    let mismatch=0; for(let i=0;i<a.length;i++) mismatch |= a[i]^b[i];
    if (mismatch) return fail(401,'unauthorized');
    if (!apiKey) return fail(503,'not_configured');
    if (!request.headers.get('Content-Type')?.startsWith('application/json')) return fail(415,'invalid_input');
    let body, bodyBytes = 0;
    try {
      const reader=request.body?.getReader(); if(!reader) return fail(400,'invalid_input');
      const chunks=[];let size=0;
      while(true) { const {done,value}=await reader.read(); if(done) break;size+=value.length;
        if(size>131072) {await reader.cancel();return fail(413,'too_long');} chunks.push(value); }
      const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}
      body=JSON.parse(new TextDecoder().decode(bytes)); bodyBytes=size;
    } catch { return fail(400,'invalid_input'); }
    if (bodyBytes > 24576 && !(body.personalActions?.length > 0)) return fail(413,'too_long');
    if(!validRequest(body)) return fail(400,'invalid_input');
    // Dev safeguard only: per-isolate, not a production entitlement or distributed quota.
    calls=calls.filter(t => now()-t<60000);
    if(active>=2 || calls.length>=30) return fail(429,'rate_limited');
    calls.push(now());active++;
    const started=now();
    const signal=AbortSignal.any([request.signal,AbortSignal.timeout(2500)]);
    try {
      const [catalog,prompt] = await Promise.all([loadCatalog(signal),loadPrompt('rank_actions','default',signal)]);
      onPrompt(prompt.version);
      const questions={};
      const ranked=body.candidates.filter(id => !RETIRED_ACTIONS.has(id));
      const retired=body.candidates.filter(id => RETIRED_ACTIONS.has(id)).map(retiredScore);
      if(!ranked.length) return reply(200,{requestID:body.requestID,model:MODEL,scores:retired,
        usage:{inputTokens:0,outputTokens:0,estimatedCostUSD:0},promptVersion:prompt.version,latencyMs:Math.max(0,now()-started)});
      for(const id of ranked) {
        const personal=(body.personalActions ?? []).find(action=>action.id===id);
        const definition=personal ? {title:personal.name, description:personal.description?.trim() || personal.instruction,
          when_to_offer:personal.operation === 'move' ? 'Selected files fit this habit; destination folder is already chosen.'
            : personal.operation === 'rename' ? 'Selected files fit this habit’s naming rules.'
            : 'Selected text and context support this action.',
          when_to_avoid:'Unrelated intent or unsupported operations.'} : catalog.get(ACTIONS[id]);
        if(!definition) return fail(503,'catalog_unavailable');
        questions[id]={type:'score',instructions:{task:prompt.instructions, action:definition},criteria:levels};
      }
      const providerBody={model:MODEL,state:observedState(body.context),questions};
      const response=await fetcher('https://api.typesafe.ai/v1/systemone',{
        method:'POST',signal,headers:{Authorization:`Bearer ${apiKey}`,'Content-Type':'application/json'},
        body:JSON.stringify(providerBody)});
      if(!response.ok) return fail(502,'ranking_unavailable');
      const result=await response.json();
      if(!validAnswers(result,ranked,modelID())) return fail(502,'invalid_ranking');
      // The account gateway resolves the model before sending; ranking has no other payload transforms.
      const debug=body.debug ? {providerRequest:JSON.stringify({...providerBody,model:result.model},null,2),
        providerResponse:JSON.stringify({model:result.model,answers:Object.fromEntries(ranked.map(id=>[id,{type:"score",score:result.answers[id].score,confidence:result.answers[id].confidence,probabilities:result.answers[id].probabilities}])),usage:{input_tokens:result.usage.input_tokens,output_tokens:result.usage.output_tokens}},null,2)} : undefined;
      return reply(200,{debug,requestID:body.requestID,model:result.model,
        scores:body.candidates.map(id => RETIRED_ACTIONS.has(id) ? retired.find(score => score.id===id)
          : {id,score:result.answers[id].score,confidence:result.answers[id].confidence,probabilities:result.answers[id].probabilities}),
        usage:{inputTokens:result.usage.input_tokens,outputTokens:result.usage.output_tokens,
          estimatedCostUSD:costUSD(result.usage.input_tokens)},promptVersion:prompt.version,latencyMs:Math.max(0,now()-started)});
    } catch {return fail(503,'ranking_unavailable');}
    finally {active--;}
  };
}
