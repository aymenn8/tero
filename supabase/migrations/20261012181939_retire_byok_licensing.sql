-- Retire the unused licensing experiment; fail rather than deleting customer rights.
do $$ begin
 if exists(select 1 from public.tero_licenses) or exists(select 1 from public.tero_byok_trials)
 or exists(select 1 from public.tero_license_devices) or exists(select 1 from public.tero_license_adjustments)
 or exists(select 1 from public.tero_checkout_orders where offer_id='byok') then
 raise exception 'Licensing has customer data; manual reconciliation required'; end if;
end $$;
drop function public.tero_activate_app_device(uuid,text,text);
drop function public.tero_activate_byok_device(uuid,text,text,text);
drop function public.tero_deactivate_byok_device(uuid,text,text);
drop function public.tero_start_byok_trial(uuid,text);
drop function public.tero_byok_snapshot(uuid,text);
drop function public.tero_grant_byok_license(text,timestamptz,text,uuid,text);
drop function public.tero_adjust_byok_license(text,text,text,timestamptz,boolean);
drop table public.tero_license_offers,public.tero_licenses,public.tero_license_adjustments,public.tero_byok_trials,public.tero_license_devices,public.tero_licensed_releases;
