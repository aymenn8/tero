-- Match the shared Rewrite delivery contract: replace validated input selections,
-- show a copyable result card for reading/unknown editability.
update public.action_definitions set output_kind='replace_or_read' where id='improve_prompt';
