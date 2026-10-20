-- Signed receipts are minted only from these server-owned entitlements.
create function public.tero_activate_app_device(p_user uuid,p_device text,p_version text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare a public.tero_accounts; r public.tero_licensed_releases;
begin
 if p_device is null or p_device!~'^[a-f0-9]{64}$' then raise exception 'invalid_device';end if;
 select * into a from public.tero_accounts where user_id=p_user for update;
 if a.user_id is null then return jsonb_build_object('error','purchase_required');end if;
 select * into r from public.tero_licensed_releases where version=p_version and released_at<=now() and channel='public';
 if r.version is null then return jsonb_build_object('error','unknown_release');end if;
 if not a.billing_review and public.tero_subscription_grants_access(a.subscription_status,a.period_start,a.period_end)
 and exists(select 1 from public.tero_paddle_subscriptions s where s.subscription_id=a.subscription_id and s.environment='production') then
 return jsonb_build_object('access','subscription','deviceID',p_device,'version',p_version,'updatesUntil',null,'expiresAt',a.period_end);
 end if;
 return public.tero_activate_byok_device(p_user,'production',p_device,p_version);
end;$$;
revoke all on function public.tero_activate_app_device(uuid,text,text) from public,anon,authenticated;
grant execute on function public.tero_activate_app_device(uuid,text,text) to service_role;
update public.tero_license_offers set paddle_price_id='pri_01m4rfw3ejh23ddxtxvw6jgp4y' where id='byok' and environment='production';
-- Sales remain off until the app, signer and web checkout are deployed together.
