-- 26: working week per project, so planned % counts working days like Primavera.
-- work_days = the JS weekday digits that are working days (0=Sun … 6=Sat), e.g. '012346' = Sat–Thu (Friday off).
-- null = every day counts (old behaviour). Filled from the P6 calendar on .xer import or the CSV column work_days.
-- Applied to the v2 TEST DB only; apply to live when releasing v2.
alter table public.projects add column if not exists work_days text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'projects_work_days_chk') then
    alter table public.projects add constraint projects_work_days_chk check (work_days is null or work_days ~ '^[0-6]{1,7}$');
  end if;
end $$;
