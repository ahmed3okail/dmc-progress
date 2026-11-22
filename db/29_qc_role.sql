-- 29: QC engineer role (run alone — a new enum value can't be used in the same transaction)
alter type public.app_role add value if not exists 'qc';
