import { habitDesignSchema, validDesignRequest, validHabitDesign } from './habit-design.ts';
import { validNamingFiles, namingSchema, namingContent, validNames } from './file-naming.ts';
import { PromptUnavailable, promptVariant, renderPrompt } from './prompt-store.ts';
import { translationLanguages, validTextOptions } from './text-actions.ts';
import { commitmentSchema, validPlanningReference, validateCommitments } from './commitments.ts';
import { validSummaryFile, summaryContent } from './file-summary.ts';
import { askAnswer } from './ask-web.ts';
import { readingStream } from './reading-stream.ts';
import { isReplyIntent, validReplyContext, replyOptionsSchema } from './reply.ts';

// Private, single-tester gateway. No body/selection/prompt logging.
// The throttle is per isolate, NOT a distributed production quota.
const responseLanguages = translationLanguages;

export function createHandler({ secret, expiresAt, apiKey, fetcher = fetch, now = Date.now, onPrompt = () => {}, loadPrompt = async () => { throw new PromptUnavailable(); } }) {
  let busy = false;
  let calls = [];
  const reply = (status, body) => Response.json(body, {
    status, headers: { 'Cache-Control': 'no-store' },
  });
  const error = (status, code) => reply(status, { error: code });
  return async function handle(request) {
    if (request.method !== 'POST') return error(405, 'method_not_allowed');
    if (!secret || secret.length < 40 || !Number.isFinite(expiresAt) || now() >= expiresAt) {
      return error(503, 'not_configured');
    }
    const supplied = request.headers.get('Authorization') ?? '';
    // Compare fixed-length digests; never reveal the expected credential.
    const digest = async (s) => new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)));
    if (supplied.length > 512) return error(401, 'unauthorized');
    const [a, b] = await Promise.all([digest(supplied), digest(`Bearer ${secret}`)]);
    let difference = 0;
    for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
    if (difference !== 0) return error(401, 'unauthorized');
    if (!apiKey) return error(503, 'not_configured');
    if (!request.headers.get('Content-Type')?.startsWith('application/json')) return error(415, 'invalid_input');
    let body;
    try {
      const reader = request.body?.getReader();
      if (!reader) return error(400, 'invalid_input');
      const chunks = []; let size = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.length;
        if (size > (request.headers.get('X-Tero-File') === '1' ? 5_400_000 : 32768)) { await reader.cancel(); return error(413, 'too_long'); }
        chunks.push(value);
      }
      const bytes = new Uint8Array(size); let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      body = JSON.parse(new TextDecoder().decode(bytes));
    } catch { return error(400, 'invalid_input'); }
    if (!body || !['fix', 'explain', 'check_claim', 'translate', 'rewrite', 'key_points', 'extract_tasks', 'reply_options', 'reply', 'ask', 'ask_refine', 'summarize_file', 'task_plan', 'event_plan', 'tone', 'simplify', 'improve_prompt', 'result_refine', 'text_habit', 'habit_design', 'rename_files'].includes(body.action) || typeof body.selection !== 'string'
        || !body.selection.trim() || typeof body.requestID !== 'string'
        || !/^[0-9a-f-]{36}$/i.test(body.requestID)) return error(400, 'invalid_input');
    if (body.action === 'habit_design' && !validDesignRequest(body.selection)) return error(400, 'invalid_input');
    const responseLanguage = body.responseLanguage === undefined ? 'en' : body.responseLanguage;
    if (['explain', 'ask', 'summarize_file'].includes(body.action) && !responseLanguages.has(responseLanguage)) return error(400, 'invalid_language');
    if (body.action === 'translate' && !responseLanguages.has(body.targetLanguage)) return error(400, 'invalid_language');
    if ([...body.selection].length > (body.action === 'result_refine' ? 8000 : 4000)) return error(413, 'too_long');
    if (body.action === 'summarize_file' ? !validSummaryFile(body.file) : body.file !== undefined) return error(400, 'invalid_file');
    if (body.action === 'rename_files' ? !validNamingFiles(body.files) : body.files !== undefined) return error(400, 'invalid_files');
    if (!['summarize_file','rename_files'].includes(body.action) && JSON.stringify(body).length > 32768) return error(413, 'too_long');
    const isPlanning = ['task_plan','event_plan'].includes(body.action);
    if (isPlanning && !validPlanningReference(body.planningReference)) return error(400, 'invalid_reference');
    const isReply = body.action === 'reply_options' || body.action === 'reply';
    const hasContext = isReply || ['explain','check_claim','task_plan','event_plan'].includes(body.action);
    if (hasContext && !validReplyContext(body.replyContext)) return error(400, 'invalid_context');
    if (body.action === 'reply' && !isReplyIntent(body.replyIntent)) return error(400, 'invalid_intent');
    if (!validTextOptions(body)) return error(400, 'invalid_style');
    if (['result_refine','text_habit'].includes(body.action) || body.action === 'rename_files' && body.refinement !== undefined ? typeof body.refinement !== 'string' || !body.refinement.trim() || [...body.refinement].length > 1000 : body.refinement !== undefined) return error(400, 'invalid_refinement');
    if (body.stream !== undefined && typeof body.stream !== 'boolean') return error(400, 'invalid_input');
    if (body.stream && ['reply_options', 'ask_refine', 'task_plan', 'event_plan', 'rename_files', 'habit_design'].includes(body.action)) return error(400, 'invalid_input');
    calls = calls.filter(t => now() - t < 60000);
    if (busy || calls.length >= 12) return error(429, 'rate_limited');
    calls.push(now()); busy = true;
    let streaming = false;
    try {
      const signal = AbortSignal.any([request.signal, AbortSignal.timeout(['ask', 'check_claim', 'summarize_file', 'rename_files'].includes(body.action) ? 55000 : 25000)]);
      const published = await loadPrompt(body.action, promptVariant(body), signal);
      onPrompt(published.version);
      const modelInstructions = renderPrompt(published.instructions, body, responseLanguages, new Date(now()).toISOString().slice(0, 10));
      const response = await fetcher('https://api.openai.com/v1/responses', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
        signal,
        body: JSON.stringify({
          model: 'gpt-6-luna', store: false, stream: body.stream === true, reasoning: { effort: 'none' },
          ...(['ask','check_claim'].includes(body.action) ? { tools: [{type: 'web_search', search_context_size: 'low', external_web_access: true}], tool_choice: body.action === 'check_claim' ? 'required' : 'auto', max_tool_calls: 2, include: ['web_search_call.action.sources'] } : {}),
          instructions: modelInstructions,
          input: [{ role: 'user', content: body.action === 'rename_files' ? [...namingContent(body.files), ...(body.refinement ? [{type:'input_text',text:JSON.stringify({personalNamingInstructions:body.refinement})}] : [])] : body.action === 'summarize_file' ? summaryContent(body.file) : JSON.stringify(hasContext ? { selection: body.selection, context: body.replyContext ?? null } : ['result_refine','text_habit'].includes(body.action) ? {selection: body.selection, refinement: body.refinement} : { selection: body.selection }) }],
          max_output_tokens: body.action === 'reply_options' ? 512 : ['explain', 'ask', 'check_claim', 'ask_refine', 'summarize_file'].includes(body.action) ? 1024 : 4096,
          text: ['ask','check_claim'].includes(body.action) ? { format: {type: 'text'} } : { format: { type: 'json_schema', name: body.action === 'rename_files' ? 'file_names' : isPlanning ? body.action : isReply || body.action === 'ask_refine' ? body.action : body.action === 'extract_tasks' ? 'extract_tasks' : body.action === 'key_points' ? 'key_points' : body.action === 'rewrite' ? 'rewrite' : body.action === 'explain' ? 'explanation' : body.action === 'translate' ? 'translation' : 'correction', strict: true,
            schema: body.action === 'habit_design' ? habitDesignSchema : body.action === 'rename_files' ? namingSchema : isPlanning ? commitmentSchema : body.action === 'reply_options' ? replyOptionsSchema : body.action === 'extract_tasks' ? {
              type: 'object', additionalProperties: false,
              properties: { status: { type: 'string', enum: ['ok', 'unsupported'] },
                tasks: { type: ['array', 'null'], items: {
                  type: 'object', additionalProperties: false,
                  properties: { action: { type: 'string' }, owner: { type: ['string', 'null'] }, deadline: { type: ['string', 'null'] } },
                  required: ['action', 'owner', 'deadline']
                } } }, required: ['status', 'tasks']
            } : body.action === 'key_points' ? {
              type: 'object', additionalProperties: false,
              properties: { status: { type: 'string', enum: ['ok', 'unsupported'] },
                points: { type: ['array', 'null'], items: { type: 'string' }, minItems: 1, maxItems: 3 } },
              required: ['status', 'points']
            } : { type: 'object', additionalProperties: false,
              properties: { status: { type: 'string', enum: ['ok', 'unsupported'] }, text: { type: ['string', 'null'] } },
              required: ['status', 'text'] } } },
        }),
      });
      if (!response.ok) return error(response.status === 429 ? 429 : 502,
        response.status === 429 ? 'rate_limited' : 'provider_error');
      if (body.stream === true) {
        streaming = true;
        return readingStream(response, body.requestID, body.action, result => {
          const decoded = decodeResult(result, body);
          if (decoded.error || typeof decoded.text !== 'string') throw new Error('invalid_result');
          return decoded.text;
        }, () => { busy = false; });
      }
      const result = await response.json();
      const decoded = decodeResult(result, body);
      return decoded.error ? error(decoded.status, decoded.error) : reply(200, {requestID: body.requestID, ...decoded});
    } catch (e) {
      if (e instanceof PromptUnavailable) return error(503, 'prompt_unavailable');
      return error(e?.name === 'TimeoutError' || e?.name === 'AbortError' ? 504 : 502, 'request_failed');
    } finally { if (!streaming) busy = false; }
  };
}

function decodeResult(result, body) {
      if (result.status !== 'completed') return { status: 502, error: 'incomplete_result' };
      const content = (result.output ?? []).filter(item => item.type === 'message').flatMap(item => item.content ?? []);
      if (content.some(item => item.type === 'refusal')) return { status: 422, error: 'unsupported' };
      const parts = content.filter(item => item.type === 'output_text');
      if (['ask','check_claim'].includes(body.action)) {
        // Search can emit an interim assistant message before its final answer.
        const final = (result.output ?? []).filter(item => item.type === 'message' && item.phase !== 'commentary').at(-1);
        const answerParts = (final?.content ?? []).filter(item => item.type === 'output_text');
        if (answerParts.length !== 1) return {status:502,error:'invalid_result'};
        const text = askAnswer(answerParts[0], result, body.action === 'check_claim');
        return text ? {text} : {status: 502, error: 'invalid_result'};
      }
      if (parts.length !== 1) return { status: 502, error: 'invalid_result' };
      let corrected;
      try { corrected = JSON.parse(parts[0].text); } catch { return { status: 502, error: 'invalid_result' }; }
      if (!corrected || typeof corrected !== 'object') return { status: 502, error: 'invalid_result' };
      if (corrected.status === 'unsupported') return { status: 422, error: 'unsupported' };
      if (body.action === 'habit_design') {
        if (!validHabitDesign(corrected)) return {status:502,error:'invalid_result'};
        const {status, ...design} = corrected;
        return {design};
      }
      if (['task_plan','event_plan'].includes(body.action)) {
        return validateCommitments(corrected, body.selection, body.action === 'task_plan' ? 'task' : 'event')
          ? {items: corrected.items} : {status: 502, error: 'invalid_result'};
      }
      if (body.action === 'rename_files') {
        return validNames(corrected, body.files) ? {names: corrected.names} : {status:502,error:'invalid_result'};
      }
      if (body.action === 'reply_options') {
        if (corrected.status !== 'ok' || !Array.isArray(corrected.intents) || corrected.intents.length !== 3
            || new Set(corrected.intents).size !== 3 || !corrected.intents.every(isReplyIntent)) return { status: 502, error: 'invalid_result' };
        return { intents: corrected.intents };
      }
      if (body.action === 'extract_tasks') {
        const sourceField = value => value === null || (typeof value === 'string' && value.trim() && body.selection.includes(value.trim()));
        if (corrected.status !== 'ok' || !Array.isArray(corrected.tasks)
            || corrected.tasks.some(task => !task || typeof task.action !== 'string' || !task.action.trim()
              || !sourceField(task.owner) || !sourceField(task.deadline))) {
          return { status: 502, error: 'invalid_result' };
        }
        const oneLine = value => value.trim().replace(/\s+/g, ' ');
        corrected.text = corrected.tasks.length === 0 ? 'No tasks found.' : corrected.tasks.map(task => {
          const details = [task.owner, task.deadline].filter(value => value !== null).map(oneLine);
          return '- ' + oneLine(task.action) + (details.length ? ' — ' + details.join(' · ') : '');
        }).join('\n');
      }
      if (body.action === 'key_points') {
        if (corrected.status !== 'ok' || !Array.isArray(corrected.points)
            || corrected.points.length < 1 || corrected.points.length > 3
            || corrected.points.some(point => typeof point !== 'string' || !point.trim())) {
          return { status: 502, error: 'invalid_result' };
        }
        corrected.text = corrected.points.map(point => '- ' + point.trim().replace(/\s+/g, ' ')).join('\n');
      }
      if (corrected.status !== 'ok' || typeof corrected.text !== 'string'
          || !corrected.text.trim() || [...corrected.text].length > (body.action === 'explain' ? 2000 : body.action === 'ask_refine' ? 4000 : body.action === 'ask' ? 3000 : 8000)) return { status: 502, error: 'invalid_result' };
      // A common model failure is to echo the transport envelope as the correction.
      try {
        const envelope = JSON.parse(corrected.text);
        if (envelope && typeof envelope === 'object' && typeof envelope.selection === 'string'
            && !body.selection.trimStart().startsWith('{')) return { status: 502, error: 'invalid_result' };
      } catch { /* Ordinary corrected text is not JSON. */ }
      return { text: corrected.text };
}
