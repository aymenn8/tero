// Only action descriptions are cached. Selection/context never enter database queries or logs.
export function createCatalogStore({url,key,fetcher=fetch,now=Date.now}) {
  let cache;let expires=0;
  return async signal => {
    if(cache && now()<expires) return cache;
    if(!url || !key) throw new Error('Catalog unavailable');
    const endpoint=new URL('/rest/v1/action_definitions',url);
    endpoint.search=new URLSearchParams({is_recommendable:'eq.true',select:'id,title,description,when_to_offer,when_to_avoid',limit:'64'}).toString();
    const response=await fetcher(endpoint,{signal,headers:{apikey:key,Authorization:`Bearer ${key}`}});
    if(!response.ok) throw new Error('Catalog unavailable');
    const rows=await response.json();
    if(!Array.isArray(rows) || rows.length>64 || !rows.length) throw new Error('Catalog unavailable');
    const result=new Map();
    for(const row of rows) {
      if(!row || !/^[a-z][a-z0-9_]*$/.test(row.id) || result.has(row.id)
        || !['title','description','when_to_offer','when_to_avoid'].every(k => typeof row[k]==='string' && row[k].length<=2000)) throw new Error('Invalid catalog');
      result.set(row.id,{title:row.title,description:row.description,when_to_offer:row.when_to_offer,when_to_avoid:row.when_to_avoid});
    }
    cache=result;expires=now()+30000;return result;
  };
}
