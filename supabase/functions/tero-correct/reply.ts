// Typed user choices, not free-form model instructions or executable plans.
export const replyIntents = Object.fromEntries(['accept', 'decline', 'clarify', 'thank', 'acknowledge', 'alternative', 'more_time', 'apologize', 'support', 'offer_help', 'follow_up'].map(id => [id, true]));
export const isReplyIntent = value => typeof value === 'string' && Object.hasOwn(replyIntents, value);

export const replyOptionsSchema = {
  type: 'object', additionalProperties: false,
  properties: { status: { type: 'string', enum: ['ok', 'unsupported'] },
    intents: { type: ['array', 'null'], minItems: 3, maxItems: 3,
      items: { type: 'string', enum: Object.keys(replyIntents) } } },
  required: ['status', 'intents']
};

export function validReplyContext(value) {
  if (value === undefined || value === null) return true;
  if (typeof value !== 'object' || Array.isArray(value)) return false;
  const fields = { applicationName: 100, webHost: 253, nearbyText: 960 };
  if (Object.keys(value).some(key => !Object.hasOwn(fields, key) && key !== 'surface')) return false;
  if (!['writing', 'reading', 'unknown'].includes(value.surface)) return false;
  return Object.entries(fields).every(([key, limit]) => value[key] === undefined || value[key] === null
    || (typeof value[key] === 'string' && [...value[key]].length <= limit));
}
