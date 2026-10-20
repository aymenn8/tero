-- Only a completed, previously pending Pro checkout queues a welcome email.
-- Renewals insert completed orders directly and do not trigger this queue.
create table public.tero_pro_welcome_emails (
 subscription_id text primary key,
 transaction_id text not null unique references public.tero_checkout_orders(transaction_id) on delete cascade,
 user_id uuid not null references public.tero_accounts(user_id) on delete cascade,
 created_at timestamptz not null default now(),
 first_attempt_at timestamptz,
 lease_until timestamptz,
 claim_id uuid,
 payload jsonb,
 sent_at timestamptz,
 provider_email_id text
);
alter table public.tero_pro_welcome_emails enable row level security;
revoke all on public.tero_pro_welcome_emails from public, anon, authenticated;
grant select,insert,update,delete on public.tero_pro_welcome_emails to service_role;

create function public.tero_queue_pro_welcome() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 insert into public.tero_pro_welcome_emails(subscription_id,transaction_id,user_id)
 select a.subscription_id,new.transaction_id,new.user_id from public.tero_accounts a
 where a.user_id=new.user_id and a.subscription_status='active' and a.subscription_id is not null
 on conflict do nothing;
 return new;
end; $$;
revoke all on function public.tero_queue_pro_welcome() from public,anon,authenticated;
grant execute on function public.tero_queue_pro_welcome() to service_role;
create trigger tero_pro_welcome_after_payment after update of completed_at on public.tero_checkout_orders
for each row when (new.offer_id='pro' and old.completed_at is null and new.completed_at is not null)
execute function public.tero_queue_pro_welcome();

create function public.tero_claim_pro_welcome(p_transaction text,p_payload jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare e public.tero_pro_welcome_emails; claim uuid;
begin
 select * into e from public.tero_pro_welcome_emails where transaction_id=p_transaction for update;
 if not found or e.sent_at is not null then return null; end if;
 if e.lease_until>now() then raise exception 'email_busy'; end if;
 -- Resend deduplicates for 24h. An ambiguous older send needs manual reconciliation.
 if e.first_attempt_at<now()-interval '23 hours' then raise exception 'email_review_required'; end if;
 if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'invalid_email'; end if;
 claim:=gen_random_uuid();
 update public.tero_pro_welcome_emails set claim_id=claim,lease_until=now()+interval '60 seconds',
 first_attempt_at=coalesce(first_attempt_at,now()),payload=coalesce(payload,p_payload)
 where transaction_id=p_transaction returning * into e;
 return jsonb_build_object('claim_id',claim,'subscription_id',e.subscription_id,'payload',e.payload);
end; $$;
revoke all on function public.tero_claim_pro_welcome(text,jsonb) from public,anon,authenticated;
grant execute on function public.tero_claim_pro_welcome(text,jsonb) to service_role;
