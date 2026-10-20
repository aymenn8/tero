-- Keep the Pro entitlement until the annual renewal, but replenish AI monthly.
alter table public.tero_plans add column yearly_price_eur_micros bigint check(yearly_price_eur_micros>0);
update public.tero_plans set yearly_price_eur_micros=89900000 where id='pro';
alter table public.tero_checkout_orders add column billing_interval text not null default 'monthly' check(billing_interval in ('monthly','yearly'));
alter table public.tero_checkout_orders add column paddle_environment text not null default 'sandbox' check(paddle_environment in ('sandbox','production'));

create function public.tero_usage_window(p_start timestamptz,p_end timestamptz,p_at timestamptz)
returns table(starts_at timestamptz,ends_at timestamptz) language plpgsql stable set search_path='' set timezone='UTC' as $$
declare n integer;
begin
 if p_start is null or p_end is null or p_end<=p_start then raise exception 'invalid_period'; end if;
 if p_end-p_start<=interval '40 days' then return query select p_start,p_end;return;end if;
 n:=greatest(0,(extract(year from p_at)::integer-extract(year from p_start)::integer)*12+extract(month from p_at)::integer-extract(month from p_start)::integer);
 if p_start+make_interval(months=>n)>p_at then n:=greatest(0,n-1);end if;
 return query select p_start+make_interval(months=>n),least(p_end,p_start+make_interval(months=>n+1));
end;$$;
create function public.tero_current_usage_window(p_user uuid)
returns table(starts_at timestamptz,ends_at timestamptz) language sql stable set search_path='' as $$
 select w.* from public.tero_accounts a cross join lateral public.tero_usage_window(
 case when a.subscription_status='active' and a.period_end>now() then a.period_start else date_trunc('month',now()) end,
 case when a.subscription_status='active' and a.period_end>now() then a.period_end else date_trunc('month',now())+interval '1 month' end,now()) w where a.user_id=p_user;
$$;
create function public.tero_included_budget(p_start timestamptz,p_end timestamptz)
returns bigint language sql stable set search_path='' as $$
 select floor((case when p_end-p_start>interval '40 days' then yearly_price_eur_micros/12.0 else price_eur_micros end)*budget_ratio)::bigint from public.tero_plans where id='pro';
$$;
revoke all on function public.tero_usage_window(timestamptz,timestamptz,timestamptz),public.tero_current_usage_window(uuid),public.tero_included_budget(timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.tero_usage_window(timestamptz,timestamptz,timestamptz),public.tero_current_usage_window(uuid),public.tero_included_budget(timestamptz,timestamptz) to service_role;

-- Preserve the deployed reservation/account checks and grants; change only the usage window.
do $$
declare source text; old text; replacement text;
begin
 source:=pg_get_functiondef('public.tero_reserve_call(uuid,uuid,text,text,integer)'::regprocedure);
 old:=$old$start_at:=case when a.subscription_status='active' and a.period_end>now() then a.period_start else date_trunc('month',now()) end;
 end_at:=case when a.subscription_status='active' and a.period_end>now() then a.period_end else start_at+interval '1 month' end;$old$;
 if strpos(source,old)=0 then raise exception 'usage_reservation_source_changed';end if;
 source:=replace(source,old,'select starts_at,ends_at into start_at,end_at from public.tero_current_usage_window(p_user);');
 old:=$old$select floor(price_eur_micros*budget_ratio) into budget from public.tero_plans where id='pro';$old$;
 if strpos(source,old)=0 then raise exception 'usage_budget_source_changed';end if;
 execute replace(source,old,'budget:=public.tero_included_budget(a.period_start,a.period_end);');
 source:=pg_get_functiondef('public.tero_account_snapshot(uuid)'::regprocedure);
 old:=$old$period_start=(case when a.subscription_status='active' and a.period_end>now() then a.period_start else date_trunc('month',now()) end)$old$;
 if strpos(source,old)=0 then raise exception 'usage_snapshot_source_changed';end if;
 source:=replace(source,old,'period_start=(select starts_at from public.tero_current_usage_window(p_user))');
 old:=$old$select floor(price_eur_micros*budget_ratio) into budget from public.tero_plans where id='pro';$old$;
 if strpos(source,old)=0 then raise exception 'snapshot_budget_source_changed';end if;
 source:=replace(source,old,'budget:=public.tero_included_budget(a.period_start,a.period_end);');
 old:=$old$case when a.subscription_status='active' and a.period_end>now() then a.period_end else date_trunc('month',now())+interval '1 month' end$old$;
 if strpos(source,old)=0 then raise exception 'snapshot_reset_source_changed';end if;
 execute replace(source,old,'(select ends_at from public.tero_current_usage_window(p_user))');
end;$$;
