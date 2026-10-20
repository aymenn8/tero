import { askPreview } from './ask-web.ts';
// Only explicit provider output is exposed; reasoning and provider metadata stay private.
export function previewJSON(source, action) {
  const values = key => {
    const pattern = new RegExp('"' + key + '"\\s*:\\s*"', 'g');
    const results = []; let match;
    while ((match = pattern.exec(source))) {
      const start = pattern.lastIndex; let end = start; let escaped = false;
      for (; end < source.length; end++) {
        const char = source[end];
        if (!escaped && char === '"') break;
        if (!escaped && char === '\\') escaped = true; else escaped = false;
      }
      // Decode only a complete JSON string prefix, including Unicode escapes.
      let prefix = source.slice(start, end);
      while (prefix.length) {
        try { results.push(JSON.parse('"' + prefix + '"')); break; }
        catch { prefix = prefix.slice(0, -1); }
      }
      pattern.lastIndex = end + 1;
    }
    return results;
  };
  if (action === 'extract_tasks') return values('action').map(text => '- ' + text).join('\n');
  if (action === 'key_points') {
    const array = source.match(/"points"\s*:\s*\[/);
    if (!array) return '';
    // Reuse the string decoder without interpreting unfinished JSON as an object.
    const items = source.slice(array.index + array[0].length);
    const normalized = items.replace(/(^|,\s*)"/g, '$1"point":"');
    return previewJSON(normalized, 'points');
  }
  const result = values(action === 'points' ? 'point' : 'text');
  return action === 'points' ? result.map(text => '- ' + text).join('\n') : result.join('');
}

export function readingStream(response, requestID, action, validate, finished) {
  const encoder = new TextEncoder(); const decoder = new TextDecoder();
  const reader = response.body?.getReader();
  let cancelled = false;
  const stream = new ReadableStream({
    async start(controller) {
      let pending = ''; let raw = ''; let last = ''; let complete = false;
      const emit = (type, text = '') => {
        if (!cancelled) controller.enqueue(encoder.encode(JSON.stringify({ requestID, type, text }) + '\n'));
      };
      try {
        if (!reader) throw new Error('missing_stream');
        while (!complete && !cancelled) {
          const chunk = await reader.read();
          if (chunk.done) break;
          pending += decoder.decode(chunk.value, { stream: true });
          pending = pending.replace(/\r\n/g, '\n');
          if (pending.length > 131072) throw new Error('oversized_event');
          let boundary;
          while (!complete && (boundary = pending.indexOf('\n\n')) >= 0) {
            const block = pending.slice(0, boundary); pending = pending.slice(boundary + 2);
            const data = block.split('\n').filter(line => line.startsWith('data:'))
              .map(line => line.slice(5).trimStart()).join('\n');
            if (!data || data === '[DONE]') continue;
            const event = JSON.parse(data);
            if (event.type === 'response.output_text.delta') {
              if (typeof event.delta !== 'string') throw new Error('invalid_delta');
              raw += event.delta;
              if (raw.length > 65536) throw new Error('oversized_output');
              const text = ['ask','check_claim'].includes(action) ? askPreview(raw) : previewJSON(raw, action);
              if (text && text !== last) { emit('progress', text); last = text; }
            } else if (event.type === 'response.completed') {
              const text = validate(event.response);
              emit('done', text); complete = true;
            } else if (['error', 'response.failed', 'response.incomplete', 'response.refusal.delta'].includes(event.type)) {
              throw new Error('provider_failed');
            }
          }
        }
        if (!complete && !cancelled) throw new Error('incomplete_stream');
      } catch {
        emit('error');
      } finally {
        try { await reader?.cancel(); } catch { /* Already closed. */ }
        finished();
        if (!cancelled) controller.close();
      }
    },
    cancel() { cancelled = true; return reader?.cancel(); },
  });
  return new Response(stream, { headers: {
    'Content-Type': 'application/x-ndjson; charset=utf-8', 'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  } });
}
