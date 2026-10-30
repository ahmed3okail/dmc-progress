-- DMC Progress ERP — 08: remaining duration entered by the site engineer with each update
-- Safe to run again. Applied via the Supabase MCP on 2026-10-30.
alter table public.progress_updates add column if not exists remaining_days int;
do $$ begin
  alter table public.progress_updates add constraint progress_updates_remaining_days_chk
    check (remaining_days is null or remaining_days between 0 and 3650);
exception when duplicate_object then null; end $$;
