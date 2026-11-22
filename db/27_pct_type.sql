-- % complete type per activity, like Primavera P6 (2026-11-22)
-- P = Physical (engineer enters %), D = Duration (% from remaining days), U = Units (% from quantity done)
alter table public.activities add column if not exists pct_type text not null default 'P';
do $$ begin
  if not exists (select 1 from pg_constraint where conname='activities_pct_type_chk') then
    alter table public.activities add constraint activities_pct_type_chk check (pct_type in ('P','D','U'));
  end if;
end $$;
