-- Remove Supabase default write grants: the execution gateway only needs reads.
revoke all on public.action_definitions, public.ai_prompts from public, service_role;
revoke all on sequence public.ai_prompts_id_seq from public, service_role;
grant select on public.action_definitions, public.ai_prompts to service_role;
