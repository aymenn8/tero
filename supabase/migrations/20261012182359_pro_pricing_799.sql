-- New purchases: EUR7.99/month, retaining the 60% allocation.
-- Existing subscribers keep the allowance of their actual catalog price.
create function public.tero_user_included_budget(p_user uuid,p_start timestamptz,p_end timestamptz)
returns bigint language sql stable security invoker set search_path='' as $$
 select floor((case
 when s.items->0->>'price_id'='pri_01m4ehyqcj7tymm1fk0a56qy3m' then 8990000
 when s.items->0->>'price_id'='pri_01m4ej57jf2tcajnsq3neh30b1' then 89900000
 else case when p_end-p_start>interval '40 days' then p.yearly_price_eur_micros else p.price_eur_micros end
 end)*p.budget_ratio / (case when s.items->0->>'price_id'='pri_01m4ej57jf2tcajnsq3neh30b1' then 12 when s.items->0->>'price_id'='pri_01m4ehyqcj7tymm1fk0a56qy3m' then 1 when p_end-p_start>interval '40 days' then 12 else 1 end))::bigint
 from public.tero_plans p
 left join public.tero_accounts a on a.user_id=p_user
 left join public.tero_paddle_subscriptions s on s.subscription_id=a.subscription_id and s.environment='production'
 where p.id='pro';
$$;
revoke all on function public.tero_user_included_budget(uuid,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.tero_user_included_budget(uuid,timestamptz,timestamptz) to service_role;
-- Preserve every existing reservation/authentication check and already-open usage period.
do $$
declare signature text; source text; needle text:='public.tero_included_budget(a.period_start,a.period_end)';
begin
 foreach signature in array array['public.tero_reserve_call(uuid,uuid,text,text,integer)','public.tero_account_snapshot(uuid)'] loop
  source:=pg_get_functiondef(signature::regprocedure);
  if strpos(source,needle)=0 then raise exception 'pricing_function_changed: %',signature;end if;
  execute replace(source,needle,'public.tero_user_included_budget(p_user,a.period_start,a.period_end)');
 end loop;
end;$$;
update public.tero_plans set price_eur_micros=7990000,yearly_price_eur_micros=79900000,budget_ratio=0.60 where id='pro';
