// Trusted action definitions; selections and revision requests remain separate data.
export const translationLanguages = new Map([
  ['en','English'], ['fr','French'], ['es','Spanish'], ['de','German'],
  ['it','Italian'], ['pt','Portuguese'], ['nl','Dutch'], ['ar','Arabic'],
  ['zh','Chinese (Simplified)'], ['ja','Japanese'], ['ko','Korean'], ['hi','Hindi'],
]);
export function validTextOptions(body) {
  if (body.action === 'rewrite') return body.style === undefined || ['natural','professional','casual'].includes(body.style);
  if (body.action === 'tone') return ['warm','direct','diplomatic'].includes(body.style);
  if (body.style !== undefined) return false;
  return true;
}
