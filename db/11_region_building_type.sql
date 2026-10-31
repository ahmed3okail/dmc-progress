-- 11: location hierarchy Region → Project → Zone → Building type → Building/plot.
-- projects.region: nc = North Coast, wc = West Cairo, ec = East Cairo (null = not set).
-- activities.building_type: e.g. CH3, CH6 (optional).
alter table public.projects add column if not exists region text;
alter table public.activities add column if not exists building_type text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'projects_region_chk') then
    alter table public.projects add constraint projects_region_chk check (region is null or region in ('nc','wc','ec'));
  end if;
end $$;
