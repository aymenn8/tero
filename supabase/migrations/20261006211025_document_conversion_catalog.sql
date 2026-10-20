-- Native converters need descriptions for ranking, but no provider prompts.
insert into public.action_definitions (id,title,description,when_to_offer,when_to_avoid,accepted_inputs,output_kind,positive_examples,negative_examples,is_recommendable)
values ('convert_document','Convert','Convert downloaded documents, spreadsheets and presentations locally using LibreOffice. Offer only common supported output formats, preview filenames, then create copies without overwriting. PDF to Word is editable text only; CSV/TSV exports the first sheet as values.',
'DOC/DOCX/ODT/RTF/TXT, XLS/XLSX/ODS/CSV/TSV, PPT/PPTX/ODP or text PDF files selected in Finder and needing a different format.',
'Live Google Sheets pages, Numbers or Pages bundles, unavailable cloud files, mixed selections with no common format, locked PDFs or scanned PDFs without selectable text.',
ARRAY['document_files'],'new_files','["A DOCX selected in Finder → PDF", "An XLSX selected in Finder → CSV", "A text PDF selected → editable DOCX"]'::jsonb,
'["An online Google Sheet without a downloaded file", "A ZIP archive"]'::jsonb,true)
on conflict (id) do update set description=excluded.description,when_to_offer=excluded.when_to_offer,when_to_avoid=excluded.when_to_avoid,accepted_inputs=excluded.accepted_inputs;
update public.action_definitions set description='Explain one image, PDF, Word document, spreadsheet or presentation in a concise reading card. Office files are converted to PDF locally before the existing explicit AI upload; the original file and its path are not uploaded.',
when_to_offer='One downloaded image/PDF or supported office document selected in Finder, with readable contents.',
when_to_avoid='Unsupported formats, locked files, or a prepared PDF exceeding 4 MB or 30 pages.',
accepted_inputs=ARRAY['image','pdf','document','spreadsheet','presentation'] where id='summarize_file';
