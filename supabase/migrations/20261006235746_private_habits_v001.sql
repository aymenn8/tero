-- Preparatory sync storage. Clipboard and macOS bookmarks never enter this table.
create table public.tero_habits (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(length(name) between 1 and 120),
 definition jsonb not null check(jsonb_typeof(definition)='object' and octet_length(definition::text)<=16384
 and definition->>'schemaVersion'='1' and not (definition ?| array['path','filePath','bookmark','clipboard','selection','fileContents'])),
 revision bigint not null default 1 check(revision>0), enabled boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index tero_habits_user on public.tero_habits(user_id,updated_at);
alter table public.tero_habits enable row level security;
revoke all on public.tero_habits from public,anon;
grant select on public.tero_habits to authenticated;
grant select,insert,update,delete on public.tero_habits to service_role;
create policy tero_habits_read on public.tero_habits for select to authenticated using((select auth.uid())=user_id);
create policy tero_habits_insert on public.tero_habits for insert to authenticated with check((select auth.uid())=user_id);
create policy tero_habits_update on public.tero_habits for update to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);
create policy tero_habits_delete on public.tero_habits for delete to authenticated using((select auth.uid())=user_id);
-- A future editor must validate the complete typed recipe before saving it.
-- This preparatory table does NOT execute recipes, sync the retired DJ prototype, or publish a store entry.
