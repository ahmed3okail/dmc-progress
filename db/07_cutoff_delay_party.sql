-- DMC Progress ERP — 07: weekly cut-off reminders + delay responsibility
-- Safe to run again. Applied via the Supabase MCP on 2026-10-30.

-- 1) Who is responsible for a delay (recorded with the delay reason on each update)
alter table public.progress_updates add column if not exists delay_party text;
do $$ begin
  alter table public.progress_updates add constraint progress_updates_delay_party_chk
    check (delay_party is null or delay_party in ('contractor','owner','consultant','subcon','other'));
exception when duplicate_object then null; end $$;

-- 2) Weekly cut-off day (0 = Sunday … 4 = Thursday … 6 = Saturday). Planning / admin can change it in the app.
insert into public.app_settings (key, value) values ('cutoff_dow', '4'::jsonb) on conflict (key) do nothing;

-- Activities that must be updated in the current cycle and have no submitted update since the cycle started
-- (cycle = the 7 days ending on the next cut-off day; "today" is Riyadh time)
create or replace function public.cutoff_due(p_today date default (now() at time zone 'Asia/Riyadh')::date)
returns table (activity_id text, discipline text, project_id text, cycle_start date, cutoff date)
language sql stable security definer set search_path = public as $$
  with s as (
    select coalesce((select (value)::text::int from app_settings where key = 'cutoff_dow'), 4) as dow
  ), c as (
    select p_today + ((s.dow - extract(dow from p_today)::int + 7) % 7) as cutoff from s
  )
  select v.id, v.discipline::text, v.project_id, c.cutoff - 6, c.cutoff
  from v_activity_progress v, c
  where v.planned_start <= c.cutoff and v.approved_pct < 100
    and not exists (
      select 1 from progress_updates u
      where u.activity_id = v.id and u.status in ('submitted','endorsed','approved')
        and coalesce(u.submitted_at, u.created_at)::date >= c.cutoff - 6);
$$;
revoke all on function public.cutoff_due(date) from public, anon;
grant execute on function public.cutoff_due(date) to authenticated;

-- Sends one reminder per discipline (in-app + phone push via the notifications trigger):
-- the day before the cut-off and on the cut-off day itself. Runs daily from pg_cron.
create or replace function public.send_cutoff_reminders()
returns int language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Riyadh')::date; dow int; kind text; n int := 0; r record;
begin
  dow := coalesce((select (value)::text::int from app_settings where key = 'cutoff_dow'), 4);
  if extract(dow from today)::int = dow then kind := 'day';
  elsif extract(dow from today + 1)::int = dow then kind := 'eve';
  else return 0; end if;
  for r in select discipline, array_agg(activity_id order by activity_id) ids, min(cutoff) cutoff
           from public.cutoff_due(today) group by discipline loop
    insert into public.notifications (id, to_discipline, from_role, type, activity_ids, note, done, created_at)
    values ('RC' || to_char(today, 'YYYYMMDD') || kind || r.discipline, r.discipline::discipline, 'PL', 'missing', r.ids,
            case when kind = 'eve'
                 then 'تذكير: آخر يوم لتحديث الأنشطة بكرة ' || r.cutoff || ' — ' || array_length(r.ids, 1) || ' نشاط محتاج تحديث'
                 else 'النهارده يوم القفل ' || r.cutoff || ' — ' || array_length(r.ids, 1) || ' نشاط لسه محتاج تحديث' end,
            false, now())
    on conflict (id) do nothing;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.send_cutoff_reminders() from public, anon, authenticated;

-- 3) Daily schedule: 06:00 UTC = 09:00 Riyadh
create extension if not exists pg_cron;
do $$ begin perform cron.unschedule('dmc-cutoff-reminders'); exception when others then null; end $$;
select cron.schedule('dmc-cutoff-reminders', '0 6 * * *', 'select public.send_cutoff_reminders()');
