// Server-only published prompts. No selected content enters a database request.
export class PromptUnavailable extends Error {
  constructor() { super('Published prompt unavailable'); this.name = 'PromptUnavailable'; }
}
export function createPromptStore({ url, key, fetcher = fetch, now = Date.now, ttl = 30000 }) {
  const cache = new Map();
  return async function loadPrompt(mode, variant, signal) {
    if (!url || !key || !/^[a-z][a-z0-9_]*$/.test(mode) || !/^[a-z][a-z0-9_]*$/.test(variant)) throw new PromptUnavailable();
    const cacheKey = mode + ':' + variant;
    const hit = cache.get(cacheKey);
    if (hit && now() < hit.expiresAt) return hit.value;
    try {
      const endpoint = new URL('/rest/v1/ai_prompts', url);
      endpoint.search = new URLSearchParams({ mode_id: 'eq.' + mode, variant: 'eq.' + variant,
        state: 'eq.published', select: 'id,version,instructions', limit: '2' }).toString();
      const response = await fetcher(endpoint, { headers: { apikey: key, Authorization: `Bearer ${key}` },
        signal: AbortSignal.any([...(signal ? [signal] : []), AbortSignal.timeout(3000)]) });
      if (!response.ok) throw new PromptUnavailable();
      const rows = await response.json();
      const row = Array.isArray(rows) && rows.length === 1 ? rows[0] : null;
      if (!row || !Number.isSafeInteger(row.id) || row.id < 1 || !Number.isSafeInteger(row.version) || row.version < 1
        || typeof row.instructions !== 'string' || !row.instructions.trim() || row.instructions.length > 32000) throw new PromptUnavailable();
      const value = Object.freeze({ id: row.id, version: row.version, instructions: row.instructions });
      if (cache.size >= 64) cache.delete(cache.keys().next().value);
      cache.set(cacheKey, { value, expiresAt: now() + ttl });
      return value;
    } catch { throw new PromptUnavailable(); }
  };
}

// Only validated, explicitly supported parameters may fill prompt placeholders.
export function promptVariant(body) {
  return body.action === 'rewrite' ? body.style ?? 'natural'
    : body.action === 'tone' ? body.style : body.action === 'reply' ? body.replyIntent : 'default';
}
export function renderPrompt(template, body, languages, currentDate) {
  const values = { target_language: languages.get(body.targetLanguage),
    output_language: languages.get(body.responseLanguage ?? 'en'), current_date: currentDate,
    reference_date: body.planningReference?.localDate, time_zone: body.planningReference?.timeZone };
  const required = body.action === 'translate' ? ['target_language']
    : ['explain','summarize_file'].includes(body.action) ? ['output_language']
    : ['ask','check_claim'].includes(body.action) ? ['current_date']
    : ['task_plan','event_plan'].includes(body.action) ? ['reference_date','time_zone'] : [];
  if (required.some(key => !template.includes('{{' + key + '}}'))) throw new PromptUnavailable();
  return template.replace(/\{\{([^{}]+)\}\}/g, (_token, key) => {
    if (!Object.hasOwn(values, key) || typeof values[key] !== 'string') throw new PromptUnavailable();
    return values[key];
  });
}
