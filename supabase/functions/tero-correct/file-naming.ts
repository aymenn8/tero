import { validSummaryFile } from './file-summary.ts';
export function validNamingFiles(files) {
  if (!Array.isArray(files) || files.length < 1 || files.length > 20) return false;
  let bytes = 0;
  return files.every((item, index) => {
    if (!item || typeof item !== 'object' || Array.isArray(item)
      || Object.keys(item).some(k => !['id','text','file','name'].includes(k)) || item.id !== `file-${index}` || item.name !== undefined && (typeof item.name !== 'string' || item.name.length > 180 || !item.name.trim() || /[\x00-\x1f\x7f/:\\]/.test(item.name))) return false;
    if (item.text !== undefined) {
      if (item.file !== undefined || typeof item.text !== 'string' || !item.text.trim()) return false;
      const size = new TextEncoder().encode(item.text).length;
      if (size > 120000) return false;
      bytes += size;
    } else {
      if (!validSummaryFile(item.file)) return false;
      bytes += atob(item.file.data).length;
    }
    return bytes <= 4000000;
  });
}
export const namingSchema = {
  type:'object', additionalProperties:false,
  properties: {status:{type:'string',enum:['ok','unsupported']}, names:{type:'array',minItems:1,maxItems:20,items:{
    type:'object',additionalProperties:false,properties:{id:{type:'string'},stem:{type:'string'}},required:['id','stem']
  }}}, required:['status','names']
};
export function namingContent(files) {
  return files.flatMap(item => [{type:'input_text',text:JSON.stringify({id:item.id,name:item.name ?? null,content:item.text ?? null})},
    ...(item.file ? [item.file.mime === 'application/pdf'
      ? {type:'input_file', filename:`${item.id}.pdf`,file_data:`data:application/pdf;base64,${item.file.data}`}
      : {type:'input_image', image_url:`data:image/jpeg;base64,${item.file.data}`,detail:'auto'}] : [])]);
}
export function validNames(result, files) {
  return result.status === 'ok' && Array.isArray(result.names) && result.names.length === files.length
    && new Set(result.names.map(n=>n?.id)).size === files.length
    && result.names.every(n => n && Object.keys(n).length === 2 && files.some(f=>f.id===n.id)
      && typeof n.stem === 'string' && n.stem === n.stem.trim() && new TextEncoder().encode(n.stem).length <= 180
      && n.stem.length > 0 && !n.stem.startsWith('.') && !/[\x00-\x1f\x7f/:\\]/.test(n.stem));
}
