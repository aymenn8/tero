const bounded = (value, max) => typeof value === 'string' && value.trim().length > 0 && [...value].length <= max;
const safeName = name => bounded(name,180) && new TextEncoder().encode(name).length <= 180 && name === name.trim() && !name.startsWith('.') && !/[\x00-\x1f\x7f/:\\]/.test(name);
export function validFilePlan(plan) {
  return plan && typeof plan === 'object' && Object.keys(plan).every(k=>['operation','extensions','nameContains','usesContents'].includes(k))
    && (plan.operation !== 'move' || plan.usesContents !== true) && (plan.usesContents === undefined || typeof plan.usesContents === 'boolean') && ['rename','move'].includes(plan.operation) && Array.isArray(plan.extensions) && plan.extensions.length <= 8
    && new Set(plan.extensions).size === plan.extensions.length && plan.extensions.every(e=>typeof e==='string' && /^[a-zA-Z0-9]{1,12}$/.test(e))
    && Array.isArray(plan.nameContains) && plan.nameContains.length <= 5 && plan.nameContains.every(n=>bounded(n,60));
}
export function validDesignRequest(selection) {
  try {
    const input = JSON.parse(selection);
    if (!input || !bounded(input.request, 2500) || Object.keys(input).some(key => !['request','current'].includes(key))) return false;
    return input.current == null || typeof input.current === 'object' && bounded(input.current.name, 40)
      && bounded(input.current.instruction, 1000) && (input.current.filePlan == null || validFilePlan(input.current.filePlan))
      && Object.keys(input.current).every(key => ['name','instruction','filePlan'].includes(key));
  } catch { return false; }
}
export const habitDesignSchema = {
  type:'object', additionalProperties:false,
  properties:{status:{type:'string',enum:['ok','clarify','unsupported']}, name:{type:'string'},instruction:{type:'string'},summary:{type:'string'},sample:{type:'string'},question:{type:['string','null']},
    filePlan:{anyOf:[{type:'null'},{type:'object',additionalProperties:false,properties:{operation:{type:'string',enum:['rename','move']},usesContents:{type:'boolean'},extensions:{type:'array',maxItems:8,items:{type:'string'}},nameContains:{type:'array',maxItems:5,items:{type:'string'}}},required:['operation','extensions','nameContains','usesContents']}]},
    fileSamples:{type:'array',maxItems:3,items:{type:'object',additionalProperties:false,properties:{name:{type:'string'},content:{type:'string'}},required:['name','content']}}},
  required:['status','name','instruction','summary','sample','question','filePlan','fileSamples'],
};
export function validHabitDesign(value) {
  if (!value || Object.keys(value).some(key => !habitDesignSchema.required.includes(key))) return false;
  if (value.status === 'clarify') return bounded(value.question,240) && ['name','instruction','summary','sample'].every(key=>value[key]==='') && value.filePlan == null && (value.fileSamples ?? []).length === 0;
  if (value.status !== 'ok' || value.question !== null || !bounded(value.name,40) || !bounded(value.instruction,1000) || !bounded(value.summary,240)) return false;
  if (value.filePlan == null) return bounded(value.sample,1000) && (value.fileSamples ?? []).length === 0;
  const plan=value.filePlan, samples=value.fileSamples;
  return validFilePlan(plan) && value.sample === '' && Array.isArray(samples) && samples.length > 0 && samples.length <= 3
    && new Set(samples.map(s=>s?.name?.toLowerCase())).size === samples.length
    && samples.every(s=>s && Object.keys(s).every(k=>['name','content'].includes(k)) && safeName(s.name) && typeof s.content==='string' && [...s.content].length <= 1000
      && (plan.extensions.length===0 || plan.extensions.some(e=>s.name.toLowerCase().endsWith('.'+e.toLowerCase())))
      && (plan.nameContains.length===0 || plan.nameContains.some(n=>s.name.toLowerCase().includes(n.toLowerCase()))));
}
