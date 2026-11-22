-- 22: out-of-scope (OOS) activities — applied to the v2 test DB first; apply to live when releasing v2.
-- An OOS activity stays visible (tagged) but the app leaves it out of every progress %,
-- delayed / missing counts, cut-off compliance and reminders. Planning or admin marks it
-- (activities write policy is already admin + planner only: p_act_write).
alter table public.activities add column if not exists out_of_scope boolean not null default false;
alter table public.activities add column if not exists oos_note text;
alter table public.activities add column if not exists oos_at timestamptz;
alter table public.activities add column if not exists oos_by text;

-- server-side cut-off reminders skip OOS activities (same function + one extra filter)
CREATE OR REPLACE FUNCTION public.cutoff_due(p_today date DEFAULT ((now() AT TIME ZONE 'Asia/Riyadh'::text))::date)
 RETURNS TABLE(activity_id text, discipline text, project_id text, cycle_start date, cutoff date)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  with s as (
    select coalesce((select (value)::text::int from app_settings where key = 'cutoff_dow'), 4) as dow
  ), c as (
    select p_today + ((s.dow - extract(dow from p_today)::int + 7) % 7) as cutoff from s
  )
  select v.id, v.discipline::text, v.project_id, c.cutoff - 6, c.cutoff
  from v_activity_progress v, c
  where v.planned_start <= c.cutoff and v.approved_pct < 100
    and not exists (select 1 from activities a where a.id = v.id and a.out_of_scope)
    and not exists (
      select 1 from progress_updates u
      where u.activity_id = v.id and u.status in ('submitted','endorsed','approved')
        and coalesce(u.submitted_at, u.created_at)::date >= c.cutoff - 6);
$function$;
