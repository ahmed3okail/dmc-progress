-- 13: admin activity log (2026-11-02) — who signed in, who changed what.
create table if not exists public.login_log (
  id bigserial primary key,
  user_id uuid not null default auth.uid(),
  at timestamptz not null default now(),
  ua text
);
alter table public.login_log enable row level security;
create index if not exists login_log_at on public.login_log(at desc);
create index if not exists audit_log_at on public.audit_log(at desc);

-- the app calls this once after each sign-in
create or replace function public.log_login(p_ua text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  -- one row per user per 10 minutes is enough (page refreshes)
  if exists (select 1 from login_log where user_id = auth.uid() and at > now() - interval '10 minutes') then return; end if;
  insert into login_log(user_id, ua) values (auth.uid(), left(p_ua, 200));
end $$;
revoke execute on function public.log_login(text) from anon, public;
grant execute on function public.log_login(text) to authenticated;

-- generic audit for tables without a single id column too
create or replace function public.audit_row_any() returns trigger
language plpgsql security definer set search_path = public as $$
declare r jsonb := to_jsonb(coalesce(new, old));
begin
  insert into audit_log(table_name, row_id, action, old_row, new_row)
  values (tg_table_name, coalesce(r->>'id', r->>'key', (r->>'project_id') || ':' || (r->>'user_id')), tg_op,
          case when tg_op <> 'INSERT' then to_jsonb(old) - 'html' end,
          case when tg_op <> 'DELETE' then to_jsonb(new) - 'html' end);
  return coalesce(new, old);
end $$;
revoke execute on function public.audit_row_any() from anon, authenticated, public;
create or replace trigger trg_audit_profiles after insert or update or delete on public.profiles for each row execute function public.audit_row_any();
create or replace trigger trg_audit_projects after insert or update or delete on public.projects for each row execute function public.audit_row_any();
create or replace trigger trg_audit_members after insert or update or delete on public.project_members for each row execute function public.audit_row_any();
create or replace trigger trg_audit_wr after insert or delete on public.weekly_reports for each row execute function public.audit_row_any();
create or replace trigger trg_audit_settings after insert or update or delete on public.app_settings for each row execute function public.audit_row_any();

-- admin only: merged log, newest first; demo rows hidden unless asked
create or replace function public.admin_activity(p_limit int default 300, p_demo boolean default false)
returns table(at timestamptz, user_id uuid, who text, role text, kind text, tbl text, row_id text, old_row jsonb, new_row jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if app_role() is distinct from 'admin' then raise exception 'Admins only'; end if;
  return query
  select * from (
    select l.at, l.user_id, p.full_name, p.role::text, 'login'::text, null::text, null::text, null::jsonb, jsonb_build_object('ua', l.ua)
    from login_log l left join profiles p on p.id = l.user_id
    union all
    select a.at, a.actor, p.full_name, p.role::text, lower(a.action), a.table_name, a.row_id,
           a.old_row - 'photos' - 'log' - 'html' - 'image',
           a.new_row - 'photos' - 'log' - 'html' - 'image'
    from audit_log a left join profiles p on p.id = a.actor
    where p_demo or not (coalesce(a.new_row, a.old_row)->>'source' = 'demo' or coalesce((coalesce(a.new_row, a.old_row)->>'is_demo')::boolean, false)
                         or a.row_id like 'R_seed%')
  ) x order by 1 desc limit greatest(1, least(p_limit, 2000));
end $$;
revoke execute on function public.admin_activity(int, boolean) from anon, public;
grant execute on function public.admin_activity(int, boolean) to authenticated;
