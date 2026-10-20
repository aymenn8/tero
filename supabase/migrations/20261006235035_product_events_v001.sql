create table public.tero_product_events (
 id uuid primary key, user_id uuid not null references public.tero_accounts(user_id) on delete cascade,
 event text not null check(event in ('action_selected','panel_opened','panel_closed','result_copied','result_pasted')),
 mode_id text check(mode_id is null or mode_id ~ '^[a-zA-Z_]{1,40}$'),
 app_version text not null check(length(app_version)<=24), os_version text not null check(length(os_version)<=32), created_at timestamptz not null default now()
);
create index tero_product_events_user on public.tero_product_events(user_id,created_at);
alter table public.tero_product_events enable row level security;
revoke all on public.tero_product_events from public,anon,authenticated;
grant select,insert,delete on public.tero_product_events to service_role;
create function public.tero_record_event(p_user uuid,p_id uuid,p_event text,p_mode text,p_version text,p_os text)
returns void language plpgsql security invoker set search_path='' as $$
begin
 insert into public.tero_accounts(user_id) values(p_user) on conflict do nothing;
 perform 1 from public.tero_accounts where user_id=p_user for update;
 if (select count(*) from public.tero_product_events where user_id=p_user and created_at>now()-interval '1 minute')>=60 then return; end if;
 insert into public.tero_product_events(id,user_id,event,mode_id,app_version,os_version) values(p_id,p_user,p_event,p_mode,p_version,p_os) on conflict do nothing;
 delete from public.tero_product_events where user_id=p_user and created_at<now()-interval '30 days';
end; $$;
revoke all on function public.tero_record_event(uuid,uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.tero_record_event(uuid,uuid,text,text,text,text) to service_role;
