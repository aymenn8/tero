-- Destination choice is a native authoring step, not a model clarification.
with previous as (
  update public.ai_prompts set state='archived'
  where mode_id='habit_design' and variant='default' and state='published'
  returning instructions
)
insert into public.ai_prompts(mode_id,variant,version,state,instructions,published_at)
select 'habit_design','default',(select coalesce(max(version),0)+1 from public.ai_prompts where mode_id='habit_design' and variant='default'),
'published',instructions || $prompt$

Destination handling is mandatory: a request to move selected files to a predefined/chosen folder is already complete enough to draft. Return status ok, question null, filePlan operation move, usesContents false, filters empty unless the user specified them, sample empty, and 2-3 fictional fileSamples. The user chooses the persistent destination AFTER this response through the native folder picker. Never ask which folder, its name, its location, or whether they want to open the picker; no destination information belongs in this model response. Example: "j’aimerai déplacer les fichiers sélectionnés vers un dossier prédéfini" must produce this move draft directly, not a clarification. A filename language or case transformation is operation rename with usesContents false, not a text habit.
$prompt$,now() from previous;
