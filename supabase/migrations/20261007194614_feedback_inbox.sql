create table public.feedback (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 category text not null check (category in ('bug','idea','other')),
 description text not null check (char_length(btrim(description)) between 10 and 8000),
 app_version text check (char_length(app_version)<=40),
 os_version text check (char_length(os_version)<=100),
 created_at timestamptz not null default now(),
 seen boolean not null default false,
 seen_at timestamptz
);
alter table public.feedback enable row level security;
revoke all on public.feedback from anon, authenticated;
grant insert (id, category, description, app_version, os_version) on public.feedback to authenticated;
grant all on public.feedback to service_role;
create policy feedback_submit on public.feedback for insert to authenticated
 with check ((select auth.uid()) = user_id and not seen and seen_at is null);
create index feedback_unseen_idx on public.feedback(created_at desc) where not seen;
comment on table public.feedback is 'Explicit user feedback. Admin-only reading and seen state. Never automatic prompt or clipboard collection.';
create function public.submit_feedback(p_id uuid, p_category text, p_description text, p_app_version text default null, p_os_version text default null)
returns void language plpgsql security invoker set search_path = '' as $$
begin
 insert into public.feedback(id,category,description,app_version,os_version)
 values (p_id,p_category,p_description,p_app_version,p_os_version) on conflict do nothing;
end; $$;
revoke all on function public.submit_feedback(uuid,text,text,text,text) from public,anon;
grant execute on function public.submit_feedback(uuid,text,text,text,text) to authenticated;
notify pgrst, 'reload schema';
