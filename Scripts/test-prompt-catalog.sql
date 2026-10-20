-- Run against the development project. All workflow mutations are rolled back.
begin;
do $$
declare original_id bigint; draft_id bigint; action_count integer; prompt_count integer;
begin
 select count(*) into action_count from public.action_definitions;
 select count(*) into prompt_count from public.ai_prompts where state='published';
 assert action_count=27, 'Unexpected action count'; assert prompt_count=31, 'Unexpected prompt count';
 select id into original_id from public.ai_prompts where mode_id='fix' and variant='default' and state='published';
 draft_id := public.create_ai_prompt_draft('fix');
 update public.ai_prompts set instructions=instructions || E'\nSynthetic draft validation.' where id=draft_id;
 assert (select state='published' from public.ai_prompts where id=original_id), 'Draft affected live prompt';
 perform public.publish_ai_prompt(draft_id);
 assert (select state='archived' from public.ai_prompts where id=original_id), 'Old prompt not archived';
 assert (select state='published' from public.ai_prompts where id=draft_id), 'Draft not published';
 begin
  update public.ai_prompts set instructions='invalid edit' where id=draft_id;
  raise exception 'Published prompt was editable';
 exception when raise_exception then
  if SQLERRM <> 'Clone a draft before editing a published or archived prompt' then raise; end if;
 end;
 perform public.publish_ai_prompt(original_id);
 assert (select state='published' from public.ai_prompts where id=original_id), 'Rollback failed';
 begin
  insert into public.ai_prompts(mode_id,variant,version,state,instructions,published_at) values('fix','default',100,'published','duplicate',now());
  raise exception 'Duplicate published prompt accepted';
 exception when unique_violation then null;
 end;
end; $$;
set local role anon;
do $$ begin
 begin perform instructions from public.ai_prompts; raise exception 'Anon read allowed'; exception when insufficient_privilege then null; end;
 begin perform public.create_ai_prompt_draft('fix'); raise exception 'Anon draft allowed'; exception when insufficient_privilege then null; end;
end; $$;
reset role;
set local role authenticated;
do $$ begin
 begin perform description from public.action_definitions; raise exception 'Client read allowed'; exception when insufficient_privilege then null; end;
 begin update public.ai_prompts set instructions='blocked'; raise exception 'Client write allowed'; exception when insufficient_privilege then null; end;
end; $$;
reset role;
set local role service_role;
do $$ begin
 assert (select count(*)=31 from public.ai_prompts where state='published'), 'Gateway cannot read';
 begin update public.ai_prompts set instructions='blocked'; raise exception 'Gateway write allowed'; exception when insufficient_privilege then null; end;
 begin perform public.publish_ai_prompt(1); raise exception 'Gateway publish allowed'; exception when insufficient_privilege then null; end;
end; $$;
reset role;
rollback;
select 'workflow and role access passed; all changes rolled back' as result;
