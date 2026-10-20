-- Paddle mirrors are permanent server-only billing state, not disposable fixtures.
-- Environment is part of each key so Sandbox cannot overwrite Live records.
create table public.tero_paddle_customers(
 environment text not null check(environment in ('sandbox','production')),
 customer_id text not null check(customer_id ~ '^ctm_[a-z0-9]{26}$'),
 email text not null,
 created_at timestamptz not null,
 updated_at timestamptz not null,
 primary key(environment,customer_id)
);
create table public.tero_paddle_subscriptions(
 environment text not null,
 subscription_id text not null check(subscription_id ~ '^sub_[a-z0-9]{26}$'),
 customer_id text not null,
 status text not null check(status in ('active','trialing','past_due','paused','canceled')),
 items jsonb not null check(jsonb_typeof(items)='array' and jsonb_array_length(items)>0),
 scheduled_change_action text,
 scheduled_change_at timestamptz,
 period_start timestamptz,
 period_end timestamptz,
 created_at timestamptz not null,
 updated_at timestamptz not null,
 primary key(environment,subscription_id),
 foreign key(environment,customer_id) references public.tero_paddle_customers(environment,customer_id)
);
create index tero_paddle_subscriptions_customer on public.tero_paddle_subscriptions(environment,customer_id);
alter table public.tero_paddle_customers enable row level security;
alter table public.tero_paddle_subscriptions enable row level security;
revoke all on public.tero_paddle_customers,public.tero_paddle_subscriptions from public,anon,authenticated,service_role;
grant select,insert,update on public.tero_paddle_customers,public.tero_paddle_subscriptions to service_role;

create function public.tero_mirror_paddle_customer(p_environment text,p_id text,p_email text,p_created timestamptz,p_updated timestamptz)
returns void language sql security invoker set search_path='' as $$
 insert into public.tero_paddle_customers(environment,customer_id,email,created_at,updated_at)
 values(p_environment,p_id,p_email,p_created,p_updated)
 on conflict(environment,customer_id) do update set email=excluded.email,updated_at=excluded.updated_at
 where excluded.updated_at>tero_paddle_customers.updated_at;
$$;
create function public.tero_mirror_paddle_subscription(p_environment text,p_id text,p_customer text,p_status text,p_items jsonb,p_action text,p_effective timestamptz,p_start timestamptz,p_end timestamptz,p_created timestamptz,p_updated timestamptz)
returns void language sql security invoker set search_path='' as $$
 insert into public.tero_paddle_subscriptions(environment,subscription_id,customer_id,status,items,scheduled_change_action,scheduled_change_at,period_start,period_end,created_at,updated_at)
 values(p_environment,p_id,p_customer,p_status,p_items,p_action,p_effective,p_start,p_end,p_created,p_updated)
 on conflict(environment,subscription_id) do update set
 status=excluded.status,items=excluded.items,scheduled_change_action=excluded.scheduled_change_action,
 scheduled_change_at=excluded.scheduled_change_at,period_start=excluded.period_start,period_end=excluded.period_end,updated_at=excluded.updated_at
 where excluded.updated_at>tero_paddle_subscriptions.updated_at and excluded.customer_id=tero_paddle_subscriptions.customer_id;
$$;
-- Scheduled changes are deliberately absent from the access gate. Current status
-- and current period determine entitlement; paused/past_due retain the existing no-access rule.
create function public.tero_subscription_grants_access(p_status text,p_start timestamptz,p_end timestamptz,p_at timestamptz default now())
returns boolean language sql stable security invoker set search_path='' as $$
 select coalesce(p_status in ('active','trialing') and p_start<=p_at and p_end>p_at,false);
$$;
revoke all on function public.tero_mirror_paddle_customer(text,text,text,timestamptz,timestamptz),public.tero_mirror_paddle_subscription(text,text,text,text,jsonb,text,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz),public.tero_subscription_grants_access(text,timestamptz,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.tero_mirror_paddle_customer(text,text,text,timestamptz,timestamptz),public.tero_mirror_paddle_subscription(text,text,text,text,jsonb,text,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz),public.tero_subscription_grants_access(text,timestamptz,timestamptz,timestamptz) to service_role;

-- Preserve all deployed reservation, budget, ownership and event-ledger checks.
do $$
declare source text; signature text;
begin
 foreach signature in array array['public.tero_account_snapshot(uuid)','public.tero_reserve_call(uuid,uuid,text,text,integer)'] loop
  source:=pg_get_functiondef(signature::regprocedure);
  if strpos(source,$old$a.subscription_status='active' and a.period_start<=now() and a.period_end>now()$old$)=0 then raise exception 'access_source_changed';end if;
  execute replace(source,$old$a.subscription_status='active' and a.period_start<=now() and a.period_end>now()$old$,'public.tero_subscription_grants_access(a.subscription_status,a.period_start,a.period_end)');
 end loop;
 source:=pg_get_functiondef('public.tero_current_usage_window(uuid)'::regprocedure);
 if strpos(source,$old$a.subscription_status='active'$old$)=0 then raise exception 'window_source_changed';end if;
 execute replace(source,$old$a.subscription_status='active'$old$,$new$a.subscription_status in ('active','trialing')$new$);
 source:=pg_get_functiondef('public.tero_apply_billing_event(text,text,timestamptz,uuid,text,text,text,text,timestamptz,timestamptz,text)'::regprocedure);
 if strpos(source,$old$p_status='active'$old$)=0 then raise exception 'billing_source_changed';end if;
 source:=replace(source,$old$p_status='active'$old$,$new$p_status in ('active','trialing')$new$);
 execute replace(source,$old$a.subscription_status='active'$old$,$new$a.subscription_status in ('active','trialing')$new$);
end;$$;
