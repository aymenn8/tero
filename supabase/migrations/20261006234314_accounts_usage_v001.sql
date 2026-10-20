-- v0.0.1: no user content in usage/accounting tables. All mutations are service-only.
create table public.tero_plans (
 id text primary key check(id in ('free','pro')),
 price_eur_micros bigint not null check(price_eur_micros>=0), budget_ratio numeric not null check(budget_ratio between 0 and 1),
 daily_rank_limit int, daily_action_limit int, paddle_price_id text unique,
 check(daily_rank_limit is null or daily_rank_limit>=0), check(daily_action_limit is null or daily_action_limit>=0)
);
insert into public.tero_plans values ('free',0,0,3,3,null),('pro',8990000,0.60,null,null,null);
create table public.tero_models (
 id text primary key, provider text not null check(provider in ('openai','typesafe')), enabled boolean not null default true,
 input_usd_per_million numeric not null check(input_usd_per_million>=0), cached_usd_per_million numeric not null check(cached_usd_per_million>=0),
 output_usd_per_million numeric not null check(output_usd_per_million>=0), usd_to_eur numeric not null check(usd_to_eur>0),
 max_input_tokens int not null check(max_input_tokens between 100 and 400000), max_output_tokens int not null check(max_output_tokens between 100 and 32768),
 reasoning_effort text, web_search boolean not null default false, web_call_usd numeric not null default 0.01,
 updated_at timestamptz not null default now()
);
-- FX=1 intentionally conservative until an operator supplies a dated actual rate. Never guessed as live FX.
insert into public.tero_models values
 ('gpt-6-luna','openai',true,0.10,0.01,0.50,1,128000,4096,'none',true,0.01,now()),
 ('jev-1.13.0','typesafe',true,0.042,0.042,0,1,128000,512,null,false,0,now());
create table public.tero_model_routes (
 plan_id text references public.tero_plans(id), kind text check(kind in ('rank','action')), mode_id text not null default '*',
 model_id text not null references public.tero_models(id), primary key(plan_id,kind,mode_id)
);
insert into public.tero_model_routes values ('free','rank','*','jev-1.13.0'),('pro','rank','*','jev-1.13.0'),('free','action','*','gpt-6-luna'),('pro','action','*','gpt-6-luna');
create table public.tero_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 subscription_id text unique, customer_id text, period_start timestamptz, period_end timestamptz,
 subscription_status text not null default 'none', billing_review boolean not null default false,
 beta_until timestamptz, created_at timestamptz not null default now()
);
create table public.tero_usage_periods (
 user_id uuid references public.tero_accounts(user_id) on delete cascade, period_start timestamptz, period_end timestamptz not null,
 included_micros bigint not null check(included_micros>=0), spent_micros bigint not null default 0 check(spent_micros>=0),
 reserved_micros bigint not null default 0 check(reserved_micros>=0), primary key(user_id,period_start)
);
create table public.tero_credit_packs (
 id text primary key, price_eur_micros bigint not null check(price_eur_micros>0), budget_eur_micros bigint not null check(budget_eur_micros>0 and budget_eur_micros<price_eur_micros),
 paddle_price_id text unique, active boolean not null default false
);
-- Proposed packs; disabled until the owner sets Paddle tax-inclusive prices and approves the commercial terms.
insert into public.tero_credit_packs values ('boost_3',3000000,1500000,null,false),('boost_5',5000000,2500000,null,false);
create table public.tero_credits (
 user_id uuid references public.tero_accounts(user_id) on delete cascade, transaction_id text primary key,
 granted_micros bigint not null check(granted_micros>0), spent_micros bigint not null default 0 check(spent_micros>=0),
 reserved_micros bigint not null default 0 check(reserved_micros>=0), created_at timestamptz not null default now(), revoked boolean not null default false
);
create table public.tero_actions (
 user_id uuid references public.tero_accounts(user_id) on delete cascade, request_id uuid, kind text not null check(kind in ('rank','action')),
 mode_id text not null, created_at timestamptz not null default now(), primary key(user_id,request_id,kind)
);
create index tero_actions_daily on public.tero_actions(user_id,kind,created_at);
create table public.tero_api_calls (
 id uuid primary key default gen_random_uuid(), user_id uuid references public.tero_accounts(user_id) on delete cascade,
 request_id uuid not null, kind text not null, stage text not null, model_id text not null,
 pricing_snapshot jsonb not null, reservation_micros bigint not null check(reservation_micros>=0),
 period_start timestamptz, credit_transaction_id text references public.tero_credits(transaction_id),
 status text not null default 'reserved' check(status in ('reserved','ok','failed','unknown','rejected')),
 input_tokens bigint, cached_tokens bigint, output_tokens bigint, reasoning_tokens bigint, web_calls int,
 cost_eur_micros bigint, duration_ms int, http_status int, prompt_version int,
 created_at timestamptz not null default now(), finished_at timestamptz
);
create index tero_api_calls_user on public.tero_api_calls(user_id,created_at);
create table public.tero_checkout_orders (
 transaction_id text primary key, user_id uuid not null references public.tero_accounts(user_id) on delete cascade,
 offer_id text not null, created_at timestamptz not null default now(), completed_at timestamptz
);
create table public.tero_billing_events (
 event_id text primary key, event_type text not null, occurred_at timestamptz not null, processed_at timestamptz not null default now()
);
-- Native email handoffs are encrypted on the web server, verifier-bound and single-use across instances.
create table public.tero_auth_handoffs (
 ticket_hash text primary key, challenge text not null, ciphertext text not null, expires_at timestamptz not null,
 created_at timestamptz not null default now()
);
-- RLS + explicit grants: no customer may change a plan, balance, route or ledger.
do $$ declare t text; begin
 foreach t in array array['tero_plans','tero_models','tero_model_routes','tero_accounts','tero_usage_periods','tero_credit_packs','tero_credits','tero_actions','tero_api_calls','tero_checkout_orders','tero_billing_events','tero_auth_handoffs'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public, anon, authenticated',t);
 execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end; $$;
create function public.tero_reserve_call(p_user uuid,p_request uuid,p_kind text,p_stage text,p_input_tokens int)
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
 start_at:=coalesce(a.period_start,date_trunc('month',now())); end_at:=coalesce(a.period_end,start_at+interval '1 month');
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
create function public.tero_finish_call(p_call uuid,p_status text,p_input bigint,p_cached bigint,p_output bigint,p_reasoning bigint,p_web int,p_duration int,p_http int,p_prompt int)
returns void language plpgsql security invoker set search_path='' as $$
declare c public.tero_api_calls; charge bigint; m jsonb;
begin
 if p_status not in ('ok','failed','unknown','rejected') or coalesce(p_input,0)<0 or coalesce(p_cached,0)<0 or coalesce(p_output,0)<0 or coalesce(p_reasoning,0)<0 or coalesce(p_web,0)<0 or coalesce(p_duration,0)<0 then raise exception 'invalid_accounting'; end if;
 select * into c from public.tero_api_calls where id=p_call for update;
 if c.id is null or c.status<>'reserved' then return; end if;
 m:=c.pricing_snapshot;
 charge:=case when p_status='rejected' then 0 when p_input is null or p_output is null then c.reservation_micros else
 ceil(((p_input-least(coalesce(p_cached,0),p_input))*(m->>'input_usd_per_million')::numeric +
 least(coalesce(p_cached,0),p_input)*(m->>'cached_usd_per_million')::numeric + p_output*(m->>'output_usd_per_million')::numeric +
 coalesce(p_web,0)*1000000*(m->>'web_call_usd')::numeric)*(m->>'usd_to_eur')::numeric) end;
 -- Never hide missing usage as zero. Unknown consumes the reservation until operator reconciliation.
 update public.tero_api_calls set status=p_status,input_tokens=p_input,cached_tokens=p_cached,output_tokens=p_output,reasoning_tokens=p_reasoning,
 web_calls=p_web,cost_eur_micros=charge,duration_ms=p_duration,http_status=p_http,prompt_version=p_prompt,finished_at=now() where id=p_call;
 if c.period_start is not null then update public.tero_usage_periods set reserved_micros=greatest(0,reserved_micros-c.reservation_micros),spent_micros=spent_micros+charge where user_id=c.user_id and period_start=c.period_start; end if;
 if c.credit_transaction_id is not null then update public.tero_credits set reserved_micros=greatest(0,reserved_micros-c.reservation_micros),spent_micros=spent_micros+charge where transaction_id=c.credit_transaction_id; end if;
end; $$;
create function public.tero_account_snapshot(p_user uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
declare a public.tero_accounts; plan text; ranks int; actions int; budget bigint; spent bigint; held bigint; credits bigint; finish timestamptz;
begin
 insert into public.tero_accounts(user_id) values(p_user) on conflict do nothing;
 select * into a from public.tero_accounts where user_id=p_user;
 plan:=case when not a.billing_review and ((a.subscription_status='active' and a.period_start<=now() and a.period_end>now()) or a.beta_until>now()) then 'pro' else 'free' end;
 select count(*) filter(where kind='rank'),count(*) filter(where kind='action') into ranks,actions from public.tero_actions where user_id=p_user and created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
 select included_micros,spent_micros,reserved_micros,period_end into budget,spent,held,finish from public.tero_usage_periods where user_id=p_user and period_start=coalesce(a.period_start,date_trunc('month',now()));
 if plan='pro' and budget is null then select floor(price_eur_micros*budget_ratio) into budget from public.tero_plans where id='pro'; end if;
 select coalesce(sum(greatest(0,granted_micros-spent_micros-reserved_micros)),0) into credits from public.tero_credits where user_id=p_user and not revoked;
 return jsonb_build_object('plan',plan,'rankRemaining',greatest(0,3-ranks),'actionRemaining',greatest(0,3-actions),
 'usagePercent',case when coalesce(budget,0)>0 then least(100,round(100.0*(coalesce(spent,0)+coalesce(held,0))/budget,1)) else 0 end,
 'resetAt',case when plan='pro' then coalesce(finish,a.period_end,date_trunc('month',now())+interval '1 month') else (date_trunc('day',now() at time zone 'UTC')+interval '1 day') at time zone 'UTC' end,
 'creditsRemainingEUR',credits/1000000.0,'canRank',not a.billing_review and (plan='pro' and (coalesce(spent,0)+coalesce(held,0)<coalesce(budget,0) or credits>0) or plan='free' and ranks<3),
 'canUseAI',not a.billing_review and (plan='pro' and (coalesce(spent,0)+coalesce(held,0)<coalesce(budget,0) or credits>0) or plan='free' and actions<3));
end; $$;
create function public.tero_take_handoff(p_hash text,p_challenge text) returns text language plpgsql security invoker set search_path='' as $$
declare encrypted text;
begin
 delete from public.tero_auth_handoffs where expires_at<=now();
 delete from public.tero_auth_handoffs where ticket_hash=p_hash and challenge=p_challenge and expires_at>now() returning ciphertext into encrypted;
 return encrypted;
end; $$;
revoke all on function public.tero_reserve_call(uuid,uuid,text,text,int),public.tero_finish_call(uuid,text,bigint,bigint,bigint,bigint,int,int,int,int),public.tero_account_snapshot(uuid),public.tero_take_handoff(text,text) from public,anon,authenticated;
grant execute on function public.tero_reserve_call(uuid,uuid,text,text,int),public.tero_finish_call(uuid,text,bigint,bigint,bigint,bigint,int,int,int,int),public.tero_account_snapshot(uuid),public.tero_take_handoff(text,text) to service_role;
