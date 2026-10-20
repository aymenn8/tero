-- Tero now runs on the person's own AI key; managed AI is Tero Pro only.
-- Free accounts keep their account (habit sync, website) but no daily managed AI calls.
-- Apply together with the release that ships bring-your-own-key, never before.
update public.tero_plans set daily_rank_limit = 0, daily_action_limit = 0 where id = 'free';
