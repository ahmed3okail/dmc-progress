-- DMC Progress ERP — 09: weekly reports issued by Planning (snapshot) to CM / PM / Consultant
-- Safe to run again. Applied via the Supabase MCP on 2026-10-31.
create table if not exists public.weekly_reports (
  id text primary key,
  project_id text references public.projects(id) on delete cascade,   -- null = all projects (portfolio)
  report_no text not null,
  period text not null,
  mode text not null check (mode in ('ext','int')),
  lang text not null default 'en' check (lang in ('en','ar')),
  sent_to text[] not null check (sent_to <@ array['cm','pm','consultant'] and cardinality(sent_to) > 0),
  note text not null default '',
  html text not null,                                   -- frozen copy of the report as issued
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists weekly_reports_created_idx on public.weekly_reports (created_at desc);
alter table public.weekly_reports enable row level security;

-- Planning / admin issue reports; CM and PM read the ones sent to them (CM only for projects they can see)
drop policy if exists p_wr_insert on public.weekly_reports;
create policy p_wr_insert on public.weekly_reports for insert to authenticated
  with check (app_role() in ('planner','admin') and created_by = auth.uid());
drop policy if exists p_wr_read on public.weekly_reports;
create policy p_wr_read on public.weekly_reports for select to authenticated using (
  app_role() in ('planner','admin')
  or (app_role() = 'pm' and 'pm' = any(sent_to))
  or (app_role() = 'cm' and 'cm' = any(sent_to) and (project_id is null or can_see_project(project_id))));
grant select, insert on public.weekly_reports to authenticated;

-- Phone push to the recipients (the html is not sent to the Edge Function)
create or replace function public.push_notify() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare c record; rec jsonb; old_rec jsonb;
begin
  select fn_url, hook_secret into c from private.push_config where id = 1;
  if c is null then return new; end if;
  rec := to_jsonb(new) - 'image' - 'photos' - 'log' - 'html';
  if tg_table_name = 'chat_messages' then rec := rec || jsonb_build_object('has_image', new.image is not null); end if;
  if tg_op = 'UPDATE' then old_rec := to_jsonb(old) - 'image' - 'photos' - 'log' - 'html'; end if;
  perform net.http_post(
    url := c.fn_url,
    body := jsonb_build_object('table', tg_table_name, 'type', tg_op, 'record', rec, 'old_record', old_rec),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-hook-secret', c.hook_secret),
    timeout_milliseconds := 5000);
  return new;
exception when others then
  return new;
end $$;
revoke all on function public.push_notify() from public, anon, authenticated;
drop trigger if exists trg_push_wr on public.weekly_reports;
create trigger trg_push_wr after insert on public.weekly_reports
  for each row execute function public.push_notify();
