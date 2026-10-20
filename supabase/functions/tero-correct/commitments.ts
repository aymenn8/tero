const nullable = {type:['string','null']};
export const commitmentSchema = {
  type:'object',additionalProperties:false,
  properties:{status:{type:'string',enum:['ok','unsupported']},items:{type:['array','null'],maxItems:8,items:{
    type:'object',additionalProperties:false,properties:{
      kind:{type:'string',enum:['task','event']},title:{type:'string'},owner:nullable,deadline:nullable,
      condition:nullable,evidence:{type:'string'},date:nullable,time:nullable,endDate:nullable,endTime:nullable,timeZone:nullable,scheduleIssue:{type:['string','null'],enum:['ambiguous_date','ambiguous_zone','missing_date','missing_end','dst_time',null]}
    },required:['kind','title','owner','deadline','condition','evidence','date','time','endDate','endTime','timeZone','scheduleIssue']
  }}},required:['status','items']
};
export const validPlanningReference = value => value && typeof value==='object' && typeof value.localDate==='string'
  && /^\d{4}-\d{2}-\d{2}$/.test(value.localDate) && !isNaN(Date.parse(value.localDate+'T12:00:00Z')) && new Date(value.localDate+'T12:00:00Z').toISOString().startsWith(value.localDate) && typeof value.timeZone==='string' && value.timeZone.length<=100
  && (()=>{try {new Intl.DateTimeFormat('en',{timeZone:value.timeZone});return true;}catch{return false;}})();
export function validateCommitments(result,source,kind) {
  const quote=value=>value===null||(typeof value==='string'&&value.length>0&&source.includes(value));
  const date=value=>value===null||(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&!isNaN(Date.parse(value+'T12:00:00Z'))&&new Date(value+'T12:00:00Z').toISOString().startsWith(value));
  const zone=value=>value==null||(typeof value==='string'&&value.length<=100&&(()=>{try{new Intl.DateTimeFormat('en',{timeZone:value});return true;}catch{return false;}})());
  const issue=value=>value==null||['ambiguous_date','ambiguous_zone','missing_date','missing_end','dst_time'].includes(value);
  const time=value=>value===null||(typeof value==='string'&&/^([01]\d|2[0-3]):[0-5]\d$/.test(value));
  if (!result||result.status!=='ok'||!Array.isArray(result.items)||result.items.length>8) return false;
  return result.items.every(item=>item&&item.kind===kind&&typeof item.title==='string'&&item.title.trim()&&item.title.length<=300
    &&typeof item.evidence==='string'&&item.evidence.length>0&&item.evidence.length<=1000&&source.includes(item.evidence)
    &&zone(item.timeZone)&&issue(item.scheduleIssue)
    &&[item.owner,item.deadline,item.condition].every(quote)&&[item.date,item.endDate].every(date)&&[item.time,item.endTime].every(time)
    &&(!item.time||item.date)&&(!item.endTime||item.endDate)&&(!item.date||item.deadline)&&(!item.endDate||item.deadline));
}
