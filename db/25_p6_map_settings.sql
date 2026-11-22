-- 25: let Planning save its Primavera import choices per project in app_settings
-- (keys 'p6map:<project code>'); admins could already write every key.
-- Applied to the v2 TEST DB only; apply to live when releasing v2.
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='app_settings' and policyname='p_set_p6map') then
    create policy p_set_p6map on public.app_settings as permissive for all to authenticated
      using (key like 'p6map:%' and app_role() in ('admin'::app_role,'planner'::app_role))
      with check (key like 'p6map:%' and app_role() in ('admin'::app_role,'planner'::app_role));
  end if;
end $$;
