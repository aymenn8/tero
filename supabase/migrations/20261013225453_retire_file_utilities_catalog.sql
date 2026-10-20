-- File utilities removed from the app on 13 October 2026. Rows stay for prompt history
-- (ai_prompts.mode_id references them); they simply stop being offered for ranking.
-- tero-rank scores these ids as unsupported for released builds that still send them.
update public.action_definitions set is_recommendable = false
where id in ('compress_files','extract_archive','compress_images','extract_text','merge_pdfs',
             'extract_pdf_pages','convert_document','convert','resize');
update public.ai_prompts set state = 'archived'
where state = 'published'
  and mode_id in ('compress_files','extract_archive','compress_images','extract_text','merge_pdfs',
                  'extract_pdf_pages','convert_document','convert','resize');
