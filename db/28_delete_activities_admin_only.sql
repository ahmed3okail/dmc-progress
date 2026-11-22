-- Only the administrator can delete activities (2026-11-22, Ahmed).
-- Planner can still insert / update (import). Restrictive policy = ANDed with the existing permissive ones.
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='activities' and policyname='p_act_delete_admin_only') then
    create policy p_act_delete_admin_only on public.activities as restrictive for delete using (public.app_role() = 'admin');
  end if;
end $$;
