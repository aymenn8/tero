-- Keep ranking metadata consistent with the native choice → execution flow.
update public.action_definitions
set description=replace(description, 'preview filenames, then create copies', 'create copies immediately after an explicit format choice')
where id='convert_document';
