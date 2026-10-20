-- Operator-assigned account capability. Never derived from client build, email,
-- headers or editable user_metadata. Requires the normal verified Auth session.
alter table public.tero_accounts add column developer_access boolean not null default false;
revoke update on public.tero_accounts from public,anon,authenticated;

do $$
declare source text; old text;
begin
 source:=pg_get_functiondef('public.tero_account_snapshot(uuid)'::regprocedure);
 old:='select * into a from public.tero_accounts where user_id=p_user;';
 if strpos(source,old)=0 then raise exception 'snapshot_source_changed';end if;
 execute replace(source,old,old||$insert$
 if a.developer_access then
  return jsonb_build_object('plan','pro','developer',true,'rankRemaining',3,'actionRemaining',3,
   'usagePercent',0,'resetAt',(date_trunc('month',now())+interval '1 month'),
   'creditsRemainingEUR',0,'canRank',true,'canUseAI',true);
 end if;
$insert$);
 source:=pg_get_functiondef('public.tero_reserve_call(uuid,uuid,text,text,integer)'::regprocedure);
 if strpos(source,'if a.billing_review then')=0 or strpos(source,'plan:=case when (')=0 or
 strpos(source,'if lim is not null and n>=lim then')=0 or strpos(source,$old$if plan='pro' then$old$)=0 then raise exception 'reservation_source_changed';end if;
 source:=replace(source,'if a.billing_review then','if a.billing_review and not a.developer_access then');
 source:=replace(source,'plan:=case when (','plan:=case when a.developer_access or (');
 source:=replace(source,'if lim is not null and n>=lim then','if not a.developer_access and lim is not null and n>=lim then');
 execute replace(source,$old$if plan='pro' then$old$,$new$if plan='pro' and not a.developer_access then$new$);
 -- Developer calls still record provider token usage and actual cost in the ledger.
 -- They create no subscription, usage budget reservation or purchased credits.
end;$$;
