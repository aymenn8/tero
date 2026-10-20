// Only provider citation annotations are converted into source links.
const hideCitations = text => text.replace(/cite[^]*/g, '').replace(/[^]*$/g, '');
export const askPreview = hideCitations;
export function askAnswer(part, result, requireCitation = false) {
  if (typeof part.text !== 'string' || !part.text.trim() || [...part.text].length > 3000) return null;
  const annotations = (part.annotations ?? []).filter(annotation => {
    if (annotation.type !== 'url_citation' || typeof annotation.url !== 'string' || annotation.url.length > 512) return false;
    try { const url = new URL(annotation.url); return ['https:', 'http:'].includes(url.protocol) && !url.username && !url.password; }
    catch { return false; }
  }).map(annotation => ({...annotation, url: new URL(annotation.url).href}));
  const searches = (result.output ?? []).filter(item => item.type === 'web_search_call');
  const retrieved = searches.flatMap(item => Array.isArray(item.action?.sources) ? item.action.sources : []);
  const feedNames = new Map([['oai-weather', 'OpenAI weather feed'], ['oai-sports', 'OpenAI sports feed'], ['oai-finance', 'OpenAI finance feed']]);
  const feeds = [...new Set(retrieved.filter(source => source?.type === 'api' && feedNames.has(source.name)).map(source => feedNames.get(source.name)))];
  // Weather/sports/finance feeds have a provider attribution rather than URL annotations.
  // Only the provider's structured sources qualify; URLs written in prose never do.
  const consulted = retrieved.filter(source => {
    if (typeof source?.url !== 'string' || source.url.length > 512) return false;
    try { const url = new URL(source.url); return ['http:', 'https:'].includes(url.protocol) && !url.username && !url.password; }
    catch { return false; }
  }).map(source => ({...source, url: new URL(source.url).href}));
  if (requireCitation && !annotations.length) return null;
  const sources = [...new Map((annotations.length ? annotations : consulted).map(a => [a.url, a])).values()].slice(0, 4);
  // Source metadata is optional for Ask, even when a lookup was completed.
  // Check a claim remains citation-gated above. Do not turn a valid answer into a stream error.
  let text = part.text;
  const codepoints = [...part.text];
  const markdownURL = url => url.replaceAll('(', '%28').replaceAll(')', '%29');
  for (const annotation of annotations) {
    const index = sources.findIndex(source => source.url === annotation.url);
    if (index < 0 || !Number.isInteger(annotation.start_index) || !Number.isInteger(annotation.end_index)) continue;
    const candidates = [codepoints.slice(annotation.start_index, annotation.end_index).join(''),
      part.text.slice(annotation.start_index, annotation.end_index)];
    const marker = candidates.find(token => /^cite[^]*$/.test(token));
    if (marker) text = text.replace(marker, `[${index + 1}](${markdownURL(annotation.url)})`);
  }
  text = hideCitations(text).trim();
  if (sources.length) {
    text += '\n\n' + sources.map((source, index) => {
      const host = new URL(source.url).hostname.replace(/^www\./, '');
      const title = (typeof source.title === 'string' && source.title.trim() ? source.title.trim() : host)
        .slice(0, 80).replace(/[\r\n]/g, ' ').replace(/[\\[\]]/g, '\\$&');
      return `[${index + 1} · ${title}](${markdownURL(source.url)})`;
    }).join('\n');
  }
  if (!annotations.length && feeds.length) text += '\n\nSource: ' + feeds.join(', ') + '.';
  return text;
}
