-- Current active low-cost model replaces deprecated Nano in the public beta.
update public.tero_models set enabled=false where id='gpt-5-nano';
update public.tero_model_routes set model_id='gpt-6-luna' where plan_id='free' and kind='action';
