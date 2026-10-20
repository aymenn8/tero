-- Preserve the initial published prompt and publish its contextual refinement.
update public.ai_prompts set state='archived' where mode_id='rank_actions' and variant='default' and state='published';
insert into public.ai_prompts(mode_id,variant,version,state,instructions,published_at)
select mode_id,variant,2,'published',instructions || E'\nThe preferredLanguage is the user-selected response language, not a claim about the language of the selection. When reading a passage in a different language, Translate is a strong candidate. In a writing field, preserve the draft language unless translation is specifically useful.\nReply needs evidence that this is an incoming conversational message, rather than a generic passage or the user''s own draft. Editability and the observed element/context help distinguish them. Do not assume a conversation simply because a sentence addresses someone.',now()
from public.ai_prompts where mode_id='rank_actions' and variant='default' and version=1;
