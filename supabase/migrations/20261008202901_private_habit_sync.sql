-- Private CRUD through the authenticated Data API. RLS remains authoritative.
alter table public.tero_habits enable row level security;
revoke all on public.tero_habits from public, anon, authenticated;
grant select, insert, update, delete on public.tero_habits to authenticated;
create or replace function public.tero_habit_revision() returns trigger
language plpgsql set search_path = '' as $$
begin
 if TG_OP = 'UPDATE' then
  new.revision := old.revision + 1;
  new.created_at := old.created_at;
 else
  new.revision := 1;
  new.created_at := now();
 end if;
 new.updated_at := now();
 return new;
end;
$$;
revoke all on function public.tero_habit_revision() from public, anon, authenticated;
create trigger tero_habit_revision before insert or update on public.tero_habits
for each row execute function public.tero_habit_revision();
