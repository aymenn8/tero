-- Foundation only: do not enable sales until the native signed-receipt gate is shipped.
-- Provider credentials are never accepted or stored by this schema.
create table public.tero_license_offers (
 id text not null check(id='byok'), environment text not null check(environment in ('sandbox','production')),
 price_eur_micros bigint not null check(price_eur_micros=15000000),
 paddle_price_id text unique, active boolean not null default false,
 primary key(id,environment)
);
insert into public.tero_license_offers values ('byok','sandbox',15000000,null,false),('byok','production',15000000,null,false);
create table public.tero_licenses (
 transaction_id text primary key references public.tero_checkout_orders(transaction_id),
 user_id uuid not null references public.tero_accounts(user_id) on delete cascade,
 environment text not null check(environment in ('sandbox','production')),
 purchased_at timestamptz not null, updates_until timestamptz not null,
 revoked_at timestamptz, check(updates_until>purchased_at)
);
create unique index tero_one_active_license on public.tero_licenses(user_id,environment) where revoked_at is null;
create table public.tero_license_adjustments (
 adjustment_id text primary key, transaction_id text not null references public.tero_checkout_orders(transaction_id),
 environment text not null check(environment in ('sandbox','production')),
 occurred_at timestamptz not null, revokes boolean not null
);
create table public.tero_byok_trials (
 user_id uuid not null references public.tero_accounts(user_id) on delete cascade,
 environment text not null check(environment in ('sandbox','production')),
 started_at timestamptz not null default now(), expires_at timestamptz not null default (now()+interval '14 days'),
 primary key(user_id,environment), check(expires_at=started_at+interval '14 days')
);
create table public.tero_license_devices (
 user_id uuid not null references public.tero_accounts(user_id) on delete cascade,
 environment text not null check(environment in ('sandbox','production')),
 device_id text not null check(device_id~'^[a-f0-9]{64}$'),
 activated_at timestamptz not null default now(), deactivated_at timestamptz,
 primary key(user_id,environment,device_id)
);
-- The release date is operator-owned, never supplied as an eligibility timestamp by a client.
create table public.tero_licensed_releases (
 version text primary key check(length(version) between 1 and 40), released_at timestamptz not null,
 channel text not null check(channel in ('development','public'))
);

do $$ declare t text; begin
 foreach t in array array['tero_license_offers','tero_licenses','tero_license_adjustments','tero_byok_trials','tero_license_devices','tero_licensed_releases'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end;$$;

-- Only the verified webhook calls this after exact amount, price and environment validation.
create function public.tero_grant_byok_license(p_event text,p_occurred timestamptz,p_transaction text,p_user uuid,p_environment text)
returns void language plpgsql security invoker set search_path='' set timezone='UTC' as $$
declare o public.tero_checkout_orders;
begin
 if p_occurred is null or p_occurred>now()+interval '5 minutes' then raise exception 'invalid_purchase_date';end if;
 perform 1 from public.tero_accounts where user_id=p_user for update;
 select * into o from public.tero_checkout_orders where transaction_id=p_transaction for update;
 if o.transaction_id is null or o.user_id<>p_user or o.offer_id<>'byok' or o.paddle_environment<>p_environment then raise exception 'invalid_checkout';end if;
 if exists(select 1 from public.tero_billing_events where event_id=p_event) then return;end if;
 -- Replays never extend the year and never restore a revoked purchase.
 insert into public.tero_licenses(transaction_id,user_id,environment,purchased_at,updates_until,revoked_at)
 values(p_transaction,p_user,p_environment,p_occurred,p_occurred+interval '1 year',
 case when exists(select 1 from public.tero_license_adjustments where transaction_id=p_transaction and environment=p_environment and revokes) then now() else null end)
 on conflict(transaction_id) do nothing;
 update public.tero_checkout_orders set completed_at=coalesce(completed_at,now()) where transaction_id=p_transaction;
 insert into public.tero_billing_events values(p_event,'transaction.completed',p_occurred,now());
end;$$;

-- Keep adjustment tombstones even if the refund arrives before transaction.completed.
-- Only approved full refunds/chargebacks revoke; pending or partial refunds do not.
create function public.tero_adjust_byok_license(p_adjustment text,p_transaction text,p_environment text,p_occurred timestamptz,p_revokes boolean)
returns void language plpgsql security invoker set search_path='' as $$
declare o public.tero_checkout_orders;
begin
 select * into o from public.tero_checkout_orders where transaction_id=p_transaction;
 if o.transaction_id is null or o.offer_id<>'byok' or o.paddle_environment<>p_environment then raise exception 'invalid_checkout';end if;
 perform 1 from public.tero_accounts where user_id=o.user_id for update;
 insert into public.tero_license_adjustments values(p_adjustment,p_transaction,p_environment,p_occurred,p_revokes)
 on conflict(adjustment_id) do update set occurred_at=excluded.occurred_at,revokes=excluded.revokes
 where public.tero_license_adjustments.occurred_at<excluded.occurred_at
 and public.tero_license_adjustments.transaction_id=excluded.transaction_id and public.tero_license_adjustments.environment=excluded.environment;
 if exists(select 1 from public.tero_license_adjustments where transaction_id=p_transaction and environment=p_environment and revokes) then
 update public.tero_licenses set revoked_at=coalesce(revoked_at,now()) where transaction_id=p_transaction;
 end if;
end;$$;

create function public.tero_byok_snapshot(p_user uuid,p_environment text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare l public.tero_licenses; t public.tero_byok_trials; devices jsonb;
begin
 if p_environment not in ('sandbox','production') or p_environment is null then raise exception 'invalid_environment';end if;
 select * into l from public.tero_licenses where user_id=p_user and environment=p_environment and revoked_at is null;
 select * into t from public.tero_byok_trials where user_id=p_user and environment=p_environment;
 select coalesce(jsonb_agg(jsonb_build_object('id',device_id,'activatedAt',activated_at) order by activated_at),'[]') into devices
 from public.tero_license_devices where user_id=p_user and environment=p_environment and deactivated_at is null;
 return jsonb_build_object('licensed',l.transaction_id is not null,'purchasedAt',l.purchased_at,'updatesUntil',l.updates_until,
 'trialStartedAt',t.started_at,'trialEndsAt',t.expires_at,'trialActive',coalesce(t.expires_at>now(),false) and not exists(select 1 from public.tero_licenses where user_id=p_user and environment=p_environment),
 'trialAvailable',t.user_id is null and not exists(select 1 from public.tero_licenses where user_id=p_user and environment=p_environment),
 'deviceLimit',2,'devices',devices);
end;$$;

-- One explicit start per account/environment; no auto-start on page views/sign-in.
create function public.tero_start_byok_trial(p_user uuid,p_environment text)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if p_environment not in ('sandbox','production') or p_environment is null then raise exception 'invalid_environment';end if;
 insert into public.tero_accounts(user_id) values(p_user) on conflict do nothing;
 perform 1 from public.tero_accounts where user_id=p_user for update;
 if not exists(select 1 from public.tero_licenses where user_id=p_user and environment=p_environment) then
 insert into public.tero_byok_trials(user_id,environment) values(p_user,p_environment) on conflict do nothing;
 end if;
 return public.tero_byok_snapshot(p_user,p_environment);
end;$$;

create function public.tero_activate_byok_device(p_user uuid,p_environment text,p_device text,p_version text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare l public.tero_licenses; r public.tero_licensed_releases; t public.tero_byok_trials; n int;
begin
 if p_environment not in ('sandbox','production') or p_environment is null or p_device is null or p_device!~'^[a-f0-9]{64}$' then raise exception 'invalid_device';end if;
 perform 1 from public.tero_accounts where user_id=p_user for update;
 if not found then return jsonb_build_object('error','purchase_required');end if;
 select * into r from public.tero_licensed_releases where version=p_version and released_at<=now() and (channel='public' or p_environment='sandbox');
 if r.version is null then return jsonb_build_object('error','unknown_release');end if;
 select * into l from public.tero_licenses where user_id=p_user and environment=p_environment and revoked_at is null;
 select * into t from public.tero_byok_trials where user_id=p_user and environment=p_environment;
 if l.transaction_id is not null then
 if r.released_at>l.updates_until then return jsonb_build_object('error','update_not_included');end if;
 elsif t.user_id is null or t.expires_at<=now() or exists(select 1 from public.tero_licenses where user_id=p_user and environment=p_environment) then
 return jsonb_build_object('error','purchase_required');
 end if;
 if not exists(select 1 from public.tero_license_devices where user_id=p_user and environment=p_environment and device_id=p_device and deactivated_at is null) then
 select count(*) into n from public.tero_license_devices where user_id=p_user and environment=p_environment and deactivated_at is null;
 if n>=2 then return jsonb_build_object('error','device_limit');end if;
 insert into public.tero_license_devices(user_id,environment,device_id) values(p_user,p_environment,p_device)
 on conflict(user_id,environment,device_id) do update set activated_at=now(),deactivated_at=null;
 end if;
 return jsonb_build_object('access',case when l.transaction_id is not null then 'license' else 'trial' end,
 'deviceID',p_device,'version',p_version,'updatesUntil',l.updates_until,
 'expiresAt',case when l.transaction_id is null then t.expires_at else null end);
end;$$;

create function public.tero_deactivate_byok_device(p_user uuid,p_environment text,p_device text)
returns void language sql security invoker set search_path='' as $$
 update public.tero_license_devices set deactivated_at=now() where user_id=p_user and environment=p_environment and device_id=p_device and deactivated_at is null;
$$;

revoke all on function public.tero_grant_byok_license(text,timestamptz,text,uuid,text),public.tero_adjust_byok_license(text,text,text,timestamptz,boolean),public.tero_byok_snapshot(uuid,text),public.tero_start_byok_trial(uuid,text),public.tero_activate_byok_device(uuid,text,text,text),public.tero_deactivate_byok_device(uuid,text,text) from public,anon,authenticated;
grant execute on function public.tero_grant_byok_license(text,timestamptz,text,uuid,text),public.tero_adjust_byok_license(text,text,text,timestamptz,boolean),public.tero_byok_snapshot(uuid,text),public.tero_start_byok_trial(uuid,text),public.tero_activate_byok_device(uuid,text,text,text),public.tero_deactivate_byok_device(uuid,text,text) to service_role;
