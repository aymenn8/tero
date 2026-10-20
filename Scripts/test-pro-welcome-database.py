#!/usr/bin/env python3
"""Disposable local PostgreSQL welcome-email integration checks. No network or real accounts."""
import subprocess,tempfile,pathlib,uuid,concurrent.futures
bin='/opt/homebrew/opt/postgresql@17/bin/'
root=pathlib.Path(tempfile.mkdtemp(prefix='tero-welcome-db-'));data=root/'data';sock=root/'socket';sock.mkdir()
def run(args):
 p=subprocess.run(args,text=True,capture_output=True)
 if p.returncode:raise RuntimeError(p.stderr)
 return p.stdout.strip()
def sql(q):return run([bin+'psql','-h',str(sock),'-p','55449','postgres','-XAt','-v','ON_ERROR_STOP=1','-c',q])
run([bin+'initdb','-D',str(data),'-A','trust','--no-locale'])
try:
 run([bin+'pg_ctl','-D',str(data),'-l',str(root/'log'),'-o',f"-k {sock} -p 55449 -h ''",'-w','start'])
 sql('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);')
 base=pathlib.Path(__file__).resolve().parents[1]/'supabase'/'migrations'
 for f in ['20261006234314_accounts_usage_v001.sql','20261006234759_billing_v001.sql','20261007181143_pro_welcome_email.sql']:sql((base/f).read_text())
 u=str(uuid.uuid4());sql(f"insert into auth.users values('{u}');insert into public.tero_accounts(user_id) values('{u}');insert into public.tero_checkout_orders(transaction_id,user_id,offer_id) values('initial','{u}','pro');")
 def bill(event,txn):return sql(f"set role service_role;select public.tero_apply_billing_event('{event}','transaction.completed',now(),'{u}','pro','{txn}','sub','ctm',now(),now()+interval '1 month','active');")
 bill('first','initial');bill('first','initial');bill('renewal','renewal');
 assert sql("select count(*) from public.tero_pro_welcome_emails")=='1'
 def claim():
  try:return sql("set role service_role;select public.tero_claim_pro_welcome('initial','{\"subject\":\"original\"}')")
  except RuntimeError as e:return str(e)
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as p:results=list(p.map(lambda _:claim(),range(4)))
 assert sum('claim_id' in v for v in results)==1,results
 assert sum('email_busy' in v for v in results)==3,results
 sql("update public.tero_pro_welcome_emails set lease_until=now()-interval '1 second'")
 frozen=sql("select public.tero_claim_pro_welcome('initial','{\"subject\":\"modified\"}')")
 assert 'original' in frozen and 'modified' not in frozen
 sql("update public.tero_pro_welcome_emails set lease_until=now()-interval '1 second',first_attempt_at=now()-interval '24 hours'")
 try:claim_result=sql("select public.tero_claim_pro_welcome('initial','{}')");raise AssertionError(claim_result)
 except RuntimeError as e:assert 'email_review_required' in str(e)
 sql("update public.tero_pro_welcome_emails set sent_at=now()")
 assert sql("select public.tero_claim_pro_welcome('initial','{}')")==''
 assert sql("select has_table_privilege('authenticated','public.tero_pro_welcome_emails','select')")=='f'
 assert sql("select has_function_privilege('anon','public.tero_claim_pro_welcome(text,jsonb)','execute')")=='f'
 assert sql("select relrowsecurity from pg_class where relname='tero_pro_welcome_emails'")=='t'
 print('PASS: actual billing RPC queues once, renewal/replay suppression, four concurrent claims, frozen retry payload, old ambiguous send blocked, sent suppression, RLS and restricted grants')
finally:
 subprocess.run([bin+'pg_ctl','-D',str(data),'-m','immediate','-w','stop'],capture_output=True)
 import shutil;shutil.rmtree(root)
