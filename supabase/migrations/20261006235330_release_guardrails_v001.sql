-- Cheapest published OpenAI text tier. Deprecated upstream: verify availability/quality before opening the beta.
insert into public.tero_models values ('gpt-5-nano','openai',true,0.05,0.005,0.40,1,128000,8192,'minimal',false,0,now());
update public.tero_model_routes set model_id='gpt-5-nano' where plan_id='free' and kind='action' and mode_id='*';
-- Nano cannot run the live-search tool; use the inexpensive supported Luna route for these two capabilities.
insert into public.tero_model_routes values ('free','action','ask','gpt-6-luna'),('free','action','check_claim','gpt-6-luna');
revoke execute on function public.rls_auto_enable() from public,anon,authenticated;
create or replace function public.tero_reserve_call(p_user uuid,p_request uuid,p_kind text,p_stage text,p_input_tokens int)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare a public.tero_accounts; m public.tero_models; plan text; group_mode text; n int; lim int; previous int;
 start_at timestamptz; end_at timestamptz; budget bigint; charge bigint; c public.tero_credits; period public.tero_usage_periods; call_id uuid;
begin
 if p_kind not in ('rank','action') or p_stage !~ '^[a-z_]{1,40}$' or p_input_tokens<0 then raise exception 'invalid_input'; end if;
 insert into public.tero_accounts(user_id) values(p_user) on conflict do nothing;
 select * into a from public.tero_accounts where user_id=p_user for update;
 if a.billing_review then return jsonb_build_object('error','billing_review'); end if;
 plan:=case when (a.subscription_status='active' and a.period_start<=now() and a.period_end>now()) or a.beta_until>now() then 'pro' else 'free' end;
 select models.* into m from public.tero_model_routes routes join public.tero_models models on models.id=routes.model_id
 where routes.plan_id=plan and routes.kind=p_kind and routes.mode_id in ('*',p_stage)
 order by (routes.mode_id=p_stage) desc limit 1;
 if m.id is null or not m.enabled then return jsonb_build_object('error','model_unavailable'); end if;
 if p_input_tokens>m.max_input_tokens then return jsonb_build_object('error','too_long'); end if;
 group_mode:=case when p_stage='reply_options' then 'reply' else p_stage end;
 if exists(select 1 from public.tero_actions where user_id=p_user and request_id=p_request and kind=p_kind and mode_id<>group_mode) then return jsonb_build_object('error','invalid_group'); end if;
 select count(*) into previous from public.tero_api_calls where user_id=p_user and request_id=p_request and kind=p_kind and stage=p_stage;
 if previous>=(case when p_stage in ('task_plan','event_plan') then 2 else 1 end)
 or exists(select 1 from public.tero_api_calls where user_id=p_user and request_id=p_request and kind=p_kind and stage=p_stage and status in ('reserved','ok')) then
 return jsonb_build_object('error','duplicate_request'); end if;
 if not exists(select 1 from public.tero_actions where user_id=p_user and request_id=p_request and kind=p_kind) then
 select count(*) into n from public.tero_actions where user_id=p_user and kind=p_kind and created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
 select case when p_kind='rank' then daily_rank_limit else daily_action_limit end into lim from public.tero_plans where id=plan;
 if lim is not null and n>=lim then return jsonb_build_object('error','daily_limit'); end if;
 end if;
 -- Conservative: assume all input tokens uncached; reserve max output and up to two search calls plus search text.
 charge:=ceil((p_input_tokens*m.input_usd_per_million + m.max_output_tokens*m.output_usd_per_million +
 case when p_stage in ('ask','check_claim') and m.web_search then 16000*m.input_usd_per_million + 2000000*m.web_call_usd else 0 end)*m.usd_to_eur);
 if plan='pro' then
 start_at:=case when a.subscription_status='active' and a.period_end>now() then a.period_start else date_trunc('month',now()) end;
 end_at:=case when a.subscription_status='active' and a.period_end>now() then a.period_end else start_at+interval '1 month' end;
 select floor(price_eur_micros*budget_ratio) into budget from public.tero_plans where id='pro';
 insert into public.tero_usage_periods(user_id,period_start,period_end,included_micros) values(p_user,start_at,end_at,budget) on conflict do nothing;
 select * into period from public.tero_usage_periods where user_id=p_user and period_start=start_at for update;
 if period.spent_micros+period.reserved_micros+charge>period.included_micros then
 select * into c from public.tero_credits where user_id=p_user and not revoked and spent_micros+reserved_micros+charge<=granted_micros order by created_at for update limit 1;
 if c.transaction_id is null then return jsonb_build_object('error','monthly_limit'); end if;
 update public.tero_credits set reserved_micros=reserved_micros+charge where transaction_id=c.transaction_id;
 start_at:=null;
 else update public.tero_usage_periods set reserved_micros=reserved_micros+charge where user_id=p_user and period_start=start_at; end if;
 end if;
 insert into public.tero_actions values(p_user,p_request,p_kind,group_mode,now()) on conflict do nothing;
 insert into public.tero_api_calls(user_id,request_id,kind,stage,model_id,pricing_snapshot,reservation_micros,period_start,credit_transaction_id)
 values(p_user,p_request,p_kind,p_stage,m.id,to_jsonb(m),charge,start_at,c.transaction_id) returning id into call_id;
 return jsonb_build_object('call_id',call_id,'plan',plan,'model',to_jsonb(m));
end; $$;
create or replace function public.tero_account_snapshot(p_user uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
declare a public.tero_accounts; plan text; ranks int; actions int; budget bigint; spent bigint; held bigint; credits bigint; finish timestamptz;
begin
 insert into public.tero_accounts(user_id) values(p_user) on conflict do nothing;
 select * into a from public.tero_accounts where user_id=p_user;
 plan:=case when not a.billing_review and ((a.subscription_status='active' and a.period_start<=now() and a.period_end>now()) or a.beta_until>now()) then 'pro' else 'free' end;
 select count(*) filter(where kind='rank'),count(*) filter(where kind='action') into ranks,actions from public.tero_actions where user_id=p_user and created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
 select included_micros,spent_micros,reserved_micros,period_end into budget,spent,held,finish from public.tero_usage_periods where user_id=p_user and period_start=(case when a.subscription_status='active' and a.period_end>now() then a.period_start else date_trunc('month',now()) end);
 if plan='pro' and budget is null then select floor(price_eur_micros*budget_ratio) into budget from public.tero_plans where id='pro'; end if;
 select coalesce(sum(greatest(0,granted_micros-spent_micros-reserved_micros)),0) into credits from public.tero_credits where user_id=p_user and not revoked;
 return jsonb_build_object('plan',plan,'rankRemaining',greatest(0,3-ranks),'actionRemaining',greatest(0,3-actions),
 'usagePercent',case when coalesce(budget,0)>0 then least(100,round(100.0*(coalesce(spent,0)+coalesce(held,0))/budget,1)) else 0 end,
 'resetAt',case when plan='pro' then coalesce(finish,case when a.subscription_status='active' and a.period_end>now() then a.period_end else date_trunc('month',now())+interval '1 month' end) else (date_trunc('day',now() at time zone 'UTC')+interval '1 day') at time zone 'UTC' end,
 'creditsRemainingEUR',credits/1000000.0,'canRank',not a.billing_review and (plan='pro' and (coalesce(spent,0)+coalesce(held,0)<coalesce(budget,0) or credits>0) or plan='free' and ranks<3),
 'canUseAI',not a.billing_review and (plan='pro' and (coalesce(spent,0)+coalesce(held,0)<coalesce(budget,0) or credits>0) or plan='free' and actions<3));
end; $$;

create extension if not exists pg_cron;
select cron.schedule('tero-usage-housekeeping','*/15 * * * *','select public.tero_usage_housekeeping(); delete from public.tero_product_events where created_at < now()-interval ''30 days'';');
