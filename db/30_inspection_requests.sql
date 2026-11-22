-- 30: QC inspection requests (IR) for activities that reached 100 %
-- Progress % is never changed by QC: a rejected IR only flags the activity and notifies the engineer.
create table if not exists public.inspection_requests (
  id text primary key,
  activity_id text not null references public.activities(id) on delete cascade,
  project_id text not null,
  ir_no text not null,
  status text not null default 'open' check (status in ('open','passed','comments','rejected')),
  inspect_date date,
  notes text default '',
  result_note text default '',
  created_by uuid default auth.uid(),
  created_at timestamptz default now(),
  result_at timestamptz,
  result_by uuid,
  is_demo boolean default false
);
create index if not exists ir_activity_idx on public.inspection_requests(activity_id);
alter table public.inspection_requests enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='inspection_requests' and policyname='p_ir_read') then
    create policy p_ir_read on public.inspection_requests for select using (public.can_see_project(project_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='inspection_requests' and policyname='p_ir_insert') then
    create policy p_ir_insert on public.inspection_requests for insert
      with check (public.app_role() in ('qc','admin') and public.can_see_project(project_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='inspection_requests' and policyname='p_ir_update') then
    create policy p_ir_update on public.inspection_requests for update
      using (public.app_role() in ('qc','admin') and public.can_see_project(project_id))
      with check (public.app_role() in ('qc','admin'));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='inspection_requests' and policyname='p_ir_delete') then
    create policy p_ir_delete on public.inspection_requests for delete using (public.app_role() = 'admin');
  end if;
  -- QC may send "rejected inspection" notifications to the discipline
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='notifications' and policyname='p_n_insert_qc') then
    create policy p_n_insert_qc on public.notifications for insert with check (public.app_role() = 'qc' and type = 'qc');
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='inspection_requests') then
    alter publication supabase_realtime add table public.inspection_requests;
  end if;
end $$;

grant select, insert, update, delete on public.inspection_requests to authenticated;
