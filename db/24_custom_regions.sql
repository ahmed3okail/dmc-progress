-- 24: custom regions (Ahmed 2026-11-22: "if there is a new region, add it").
-- projects.region keeps the short keys nc / wc / ec for the 3 built-in regions,
-- and may now also hold any other region name typed in the app (max 60 chars).
-- Applied to the v2 TEST DB only; apply to live when releasing v2.
do $$ begin
  if exists (select 1 from pg_constraint where conname = 'projects_region_chk') then
    alter table public.projects drop constraint projects_region_chk;
  end if;
  alter table public.projects add constraint projects_region_chk
    check (region is null or (length(btrim(region)) between 1 and 60));
end $$;
