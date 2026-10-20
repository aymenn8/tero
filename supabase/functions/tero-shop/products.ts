export function publicURL(value) {
  try {
    if (typeof value !== 'string' || value.length > 2048) return null;
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.username || url.password || !url.hostname.includes('.')
      || url.hostname.includes(':') || /^[\d.]+$/.test(url.hostname)
      || /\.(localhost|local)$/.test(url.hostname)) return null;
    return url;
  } catch { return null; }
}
export const productSchema = {
  type:'object', additionalProperties:false,
  properties:{summary:{type:'string'},products:{type:'array',maxItems:3,items:{
    type:'object',additionalProperties:false,
    properties:{name:{type:'string'},price:{type:'string'},reason:{type:'string'},tradeoff:{type:'string'},url:{type:'string'}},
    required:['name','price','reason','tradeoff','url']}}},required:['summary','products']
};
export function productsFromResponse(response) {
  if (response.status !== 'completed') return null;
  const messages = (response.output ?? []).filter(x=>x.type==='message').flatMap(x=>x.content??[]);
  const parts = messages.filter(x=>x.type==='output_text' && typeof x.text==='string');
  if(parts.length!==1 || parts[0].text.length>16000) return null;
  const sources = new Set();
  for(const part of messages) for(const a of part.annotations??[]) if(a.type==='url_citation') {
    const url=publicURL(a.url);if(url)sources.add(url.href);
  }
  const searches = (response.output??[]).filter(x=>x.type==='web_search_call');
  if(!searches.length)return null;
  for(const item of searches) for(const source of item.action?.sources??[]) {
    const url=publicURL(source.url);if(url)sources.add(url.href);
  }
  let value;try{value=JSON.parse(parts[0].text);}catch{return null;}
  if(typeof value.summary!=='string'||value.summary.length>600||!Array.isArray(value.products)||value.products.length>3)return null;
  const products=[];
  for(const p of value.products) {
    const url=publicURL(p?.url);
    if(!url||!sources.has(url.href)||products.some(x=>x.url===url.href)
      ||!['name','price','reason','tradeoff'].every(k=>typeof p[k]==='string')
      ||!p.name.trim()||p.name.length>120||p.price.length>100||!p.reason.trim()||p.reason.length>400||p.tradeoff.length>300)return null;
    products.push({name:p.name,price:p.price,reason:p.reason,tradeoff:p.tradeoff,url:url.href,imageURL:null});
  }
  return {summary:value.summary,products};
}
