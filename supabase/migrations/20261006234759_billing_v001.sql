alter table public.tero_accounts add column billing_event_at timestamptz;
create function public.tero_apply_billing_event(p_event text,p_type text,p_occurred timestamptz,p_user uuid,p_offer text,p_transaction text,p_subscription text,p_customer text,p_start timestamptz,p_end timestamptz,p_status text)
returns void language plpgsql security invoker set search_path='' as $$
declare a public.tero_accounts; pack public.tero_credit_packs;
begin
 insert into public.tero_accounts(user_id) values(p_user) on conflict do nothing;
 select * into a from public.tero_accounts where user_id=p_user for update;
 if exists(select 1 from public.tero_billing_events where event_id=p_event) then return; end if;
 if p_type='transaction.completed' and p_transaction is null then raise exception 'invalid_transaction'; end if;
 if p_offer='pro' then
 if p_subscription is null or p_customer is null or (a.subscription_id is not null and a.subscription_id<>p_subscription and a.subscription_status='active' and a.period_end>now()) or
 (a.customer_id is not null and a.customer_id<>p_customer) then raise exception 'invalid_subscription'; end if;
 if p_status='active' and (p_start is null or p_end is null or p_end<=p_start) then raise exception 'invalid_period'; end if;
 if a.billing_event_at is null or p_occurred>a.billing_event_at then
 update public.tero_accounts set subscription_id=p_subscription,customer_id=p_customer,subscription_status=p_status,
 period_start=p_start,period_end=p_end,billing_event_at=p_occurred where user_id=p_user;
 end if;
 else
 select * into pack from public.tero_credit_packs where id=p_offer and active and paddle_price_id is not null;
 if pack.id is null or p_type<>'transaction.completed' or p_customer is null or (a.customer_id is not null and a.customer_id<>p_customer) then raise exception 'invalid_credit_pack'; end if;
 if not exists(select 1 from public.tero_checkout_orders where transaction_id=p_transaction and user_id=p_user and offer_id=p_offer) then raise exception 'invalid_checkout'; end if;
 insert into public.tero_credits(user_id,transaction_id,granted_micros) values(p_user,p_transaction,pack.budget_eur_micros) on conflict do nothing;
 end if;
 if p_transaction is not null then
 insert into public.tero_checkout_orders(transaction_id,user_id,offer_id,completed_at) values(p_transaction,p_user,p_offer,now())
 on conflict(transaction_id) do update set completed_at=now();
 end if;
 insert into public.tero_billing_events values(p_event,p_type,p_occurred,now());
end; $$;
revoke all on function public.tero_apply_billing_event(text,text,timestamptz,uuid,text,text,text,text,timestamptz,timestamptz,text) from public,anon,authenticated;
grant execute on function public.tero_apply_billing_event(text,text,timestamptz,uuid,text,text,text,text,timestamptz,timestamptz,text) to service_role;
-- Housekeeping is explicit and service-only. Schedule via Supabase Cron after owner deployment setup.
create function public.tero_usage_housekeeping() returns void language plpgsql security invoker set search_path='' as $$
declare stale record;
begin
 delete from public.tero_auth_handoffs where expires_at<now();
 for stale in select id from public.tero_api_calls where status='reserved' and created_at<now()-interval '10 minutes' loop
 perform public.tero_finish_call(stale.id,'unknown',null,null,null,null,null,null,null,null);
 end loop;
 -- Retain aggregates/balances; remove per-call diagnostics after 30 days, expired daily/group records after 7 days.
 delete from public.tero_api_calls where finished_at<now()-interval '30 days';
 delete from public.tero_actions where created_at<now()-interval '7 days';
end; $$;
revoke all on function public.tero_usage_housekeeping() from public,anon,authenticated;
grant execute on function public.tero_usage_housekeeping() to service_role;
