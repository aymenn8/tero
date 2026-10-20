import { publicURL } from './products.ts';
// Public product pages only. DNS and every redirect are checked before fetching.
export function publicIP(ip) {
  if(ip.includes(':'))return /^[23][0-9a-f]{3}:/i.test(ip);
  const n=ip.split('.').map(Number);
  if(n.length!==4||n.some(x=>!Number.isInteger(x)||x<0||x>255))return false;
  const [a,b]=n;
  return a>0&&a<224&&a!==10&&a!==127&&!(a===169&&b===254)
    &&!(a===172&&b>=16&&b<=31)&&!(a===192&&(b===168||b===0||b===2))
    &&!(a===100&&b>=64&&b<=127)&&!(a===198&&(b===18||b===19||b===51))&&!(a===203&&b===0);
}
export async function publicHost(url, resolve) {
  if(!publicURL(url.href))return false;
  try {
    const addresses=await resolve(url.hostname);
    return addresses.length>0&&addresses.every(publicIP);
  }catch{return false;}
}
export async function productImage(raw, {fetcher=fetch,resolve}) {
  if(!resolve)return null;
  // Optional previews only from established public retail/manufacturer hosts.
  const imageHosts=["amazon.fr","amazon.com","amazon.co.uk","fnac.com","darty.com","boulanger.com","ldlc.com","materiel.net","logitech.com","logitechg.com","apple.com","samsung.com","sony.com","bose.com","keychron.com","keychron.fr","ikea.com","decathlon.fr","decathlon.com","nike.com","adidas.fr","adidas.com","razer.com","corsair.com","dell.com","hp.com","lenovo.com","bestbuy.com","walmart.com","target.com","nintendo.com","canon.fr","canon.com","fujifilm.com","nespresso.com","philips.fr","philips.com"];
  const trusted=url=>imageHosts.some(h=>url.hostname===h||url.hostname.endsWith("."+h));
  let url=publicURL(raw);if(!url||!trusted(url))return null;
  try {
    const signal=AbortSignal.timeout(3000);
    for(let hop=0;hop<3;hop++) {
      if(!trusted(url)||!await publicHost(url,resolve))return null;
      const response=await fetcher(url,{signal,redirect:'manual',headers:{Accept:'text/html'}});
      if(response.status>=300&&response.status<400) {
        const location=response.headers.get('location');await response.body?.cancel();
        if(!location)return null;url=publicURL(new URL(location,url).href);if(!url)return null;continue;
      }
      if(!response.ok||!response.headers.get('content-type')?.includes('text/html')){await response.body?.cancel();return null;}
      const reader=response.body?.getReader();if(!reader)return null;
      let text='',size=0;const decoder=new TextDecoder();
      while(true){const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>512000){await reader.cancel();break;}text+=decoder.decode(part.value,{stream:true});}
      const candidateURLs=[];
      const collect=value=>{
        if(Array.isArray(value)){value.forEach(collect);return;}
        if(!value||typeof value!=='object')return;
        if([value['@type']].flat().includes('Product')) {
          const images=[value.image].flat();
          for(const image of images) {
            const raw=typeof image==='string'?image:image?.url??image?.contentUrl;
            if(raw)candidateURLs.push(raw);
          }
        }
        if(value['@graph'])collect(value['@graph']);
      };
      for(const script of text.matchAll(/<script\b[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
        try{collect(JSON.parse(script[1]));}catch{}
      }
      for(const tag of text.match(/<meta\b[^>]*>/gi)??[]) {
        const attrs=Object.fromEntries([...tag.matchAll(/([\w:-]+)\s*=\s*(["'])(.*?)\2/gs)].map(m=>[m[1].toLowerCase(),m[3]]));
        if(!['og:image','twitter:image'].includes(attrs.property??attrs.name))continue;
        const content=attrs.content?.replaceAll('&amp;','&');if(!content)continue;
        candidateURLs.push(content);
      }
      for(const content of candidateURLs) {
        const image=publicURL(new URL(content,url).href);
        if(!image||/homepage|global[-_]og|(?:^|[\/_.-])logo(?:[\/_.-]|$)|transparent\.gif/i.test(image.pathname))continue;
        if(await publicHost(image,resolve))return image.href;
      }
      return null;
    }
  }catch{}
  return null;
}
