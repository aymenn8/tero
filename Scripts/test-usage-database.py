#!/usr/bin/env python3
"""Disposable local PostgreSQL only. Real SQL, concurrent sessions, no remote accounts."""
import subprocess,json,uuid,concurrent.futures
PSQL='/opt/homebrew/opt/postgresql@17/bin/psql'
def sql(query):
 p=subprocess.run([PSQL,'-h','/tmp','-p','55439','postgres','-XAt','-v','ON_ERROR_STOP=1','-c',query],capture_output=True,text=True)
 if p.returncode:raise RuntimeError(p.stderr)
 return p.stdout.strip()
def call(user,kind='action',stage='fix',request=None):
 return json.loads(sql(f"select public.tero_reserve_call('{user}','{request or uuid.uuid4()}','{kind}','{stage}',1000)"))
u=str(uuid.uuid4());sql(f"insert into auth.users values('{u}')")
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:r=list(pool.map(lambda _:call(u),range(8)))
assert sum('call_id' in v for v in r)==3,r
assert sum(v.get('error')=='daily_limit' for v in r)==5
assert sum('call_id' in call(u,'rank','rank_actions') for _ in range(3))==3
assert call(u,'rank','rank_actions').get('error')=='daily_limit'
v=str(uuid.uuid4());sql(f"insert into auth.users values('{v}')")
rid=str(uuid.uuid4());first=call(v,stage='reply_options',request=rid)
sql(f"select public.tero_finish_call('{first['call_id']}','ok',100,0,20,0,0,100,200,1)")
assert 'call_id' in call(v,stage='reply',request=rid)
assert sql(f"select count(*) from public.tero_actions where user_id='{v}'")=='1'
assert call(v,stage='translate',request=rid)['error']=='invalid_group'
assert call(v,stage='reply',request=rid)['error']=='duplicate_request'
p=str(uuid.uuid4());sql(f"insert into auth.users values('{p}');insert into public.tero_accounts(user_id,beta_until) values('{p}',now()+interval '7 days')")
first=call(p);assert first['plan']=='pro'
sql(f"select public.tero_finish_call('{first['call_id']}','ok',100,25,20,0,0,100,200,1)")
assert sql(f"select included_micros from public.tero_usage_periods where user_id='{p}'")=='5394000'
assert json.loads(sql(f"select public.tero_account_snapshot('{p}')"))['usagePercent']>=0
sql(f"update public.tero_usage_periods set spent_micros=included_micros where user_id='{p}'")
assert call(p)['error']=='monthly_limit'
sql(f"insert into public.tero_credits(user_id,transaction_id,granted_micros) values('{p}','fixture_credit',1500000)")
next_call=call(p);assert 'call_id' in next_call
sql(f"select public.tero_finish_call('{next_call['call_id']}','unknown',null,null,null,null,null,10,504,1)")
assert int(sql("select spent_micros from public.tero_credits where transaction_id='fixture_credit'"))>0
# New period keeps top-ups, resets the included budget, and does not edit previous usage.
sql(f"update public.tero_accounts set subscription_status='active',period_start=now()-interval '1 day',period_end=now()+interval '29 days' where user_id='{p}'")
assert 'call_id' in call(p)
assert sql(f"select count(*) from public.tero_usage_periods where user_id='{p}'")=='2'
assert sql("select has_function_privilege('authenticated','public.tero_reserve_call(uuid,uuid,text,text,integer)','execute')")=='f'
assert sql("select has_table_privilege('anon','public.tero_accounts','select')")=='f'
assert sql("select bool_and(relrowsecurity) from pg_class where relname like 'tero_%' and relkind='r'")=='t'
sql("insert into public.tero_auth_handoffs values('hash','bound','encrypted',now()+interval '1 minute',now())")
assert sql("select public.tero_take_handoff('hash','wrong')")==''
assert sql("select public.tero_take_handoff('hash','bound')")=='encrypted'
assert sql("select public.tero_take_handoff('hash','bound')")==''
# Billing replays and out-of-order events must not double-grant or revert entitlements.
b=str(uuid.uuid4()); prefix=str(uuid.uuid4()); sql(f"insert into auth.users values('{b}')")
def billing(event,occurred,offer='pro',transaction=None,status='active'):
 transaction=transaction or prefix+'_subscription_transaction'
 return sql(f"select public.tero_apply_billing_event('{prefix}_{event}','transaction.completed',{occurred},'{b}','{offer}','{transaction}','{prefix}_subscription','{prefix}_customer',now()-interval '1 day',now()+interval '29 days','{status}')")
billing('new','now()')
billing('new','now()')
billing('old',"now()-interval '1 day'",status='canceled')
assert sql(f"select subscription_status from public.tero_accounts where user_id='{b}'")=='active'
sql("update public.tero_credit_packs set active=true,paddle_price_id='fixture_price' where id='boost_3'")
txn=prefix+'_credits'
sql(f"insert into public.tero_checkout_orders(transaction_id,user_id,offer_id) values('{txn}','{b}','boost_3')")
billing('credit1','now()',offer='boost_3',transaction=txn)
billing('credit2','now()',offer='boost_3',transaction=txn)
assert sql(f"select count(*) from public.tero_credits where user_id='{b}'")=='1'
assert sql(f"select granted_micros from public.tero_credits where user_id='{b}'")=='1500000'
try:
 billing('unmapped','now()',offer='boost_3',transaction=prefix+'_wrong')
 raise AssertionError('unmapped payment accepted')
except RuntimeError as error:
 assert 'invalid_checkout' in str(error)
sql("update public.tero_credit_packs set active=false,paddle_price_id=null where id='boost_3'")
sql(f"delete from public.tero_billing_events where event_id like '{prefix}_%'; delete from auth.users where id='{b}'")
sql(f"delete from auth.users where id in ('{u}','{v}','{p}')")
print('PASS: concurrent daily 3+3, reply grouping, cross-mode/replay denial, 60% monthly budget, top-ups, unknown cost reservation, renewal, RLS/permissions atomic handoff, billing replay/order and trusted credit grants')
