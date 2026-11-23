-- 35: admin deletes a whole project from the app (Import › Projects & regions), Ahmed 2026-11-23.
-- Admin only, and the caller must type the project code (p_code) to confirm.
-- Works in batches so one call stays under the API statement timeout:
-- each call deletes up to p_batch activities (their updates, IRs cascade) and returns
-- how many activities are left; when 0 are left it deletes the project itself
-- (members, locations, weekly reports cascade) and its saved P6 choices, and returns 0.
create or replace function public.admin_delete_project(p_id text, p_code text, p_batch int default 1500)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_code text; v_left int;
begin
  if app_role() is distinct from 'admin' then raise exception 'Admins only'; end if;
  select code into v_code from public.projects where id = p_id;
  if not found then return 0; end if;
  if lower(regexp_replace(coalesce(v_code,''),'\s','','g')) is distinct from lower(regexp_replace(coalesce(p_code,''),'\s','','g')) then raise exception 'Project code does not match'; end if;
  delete from public.activities
   where id in (select id from public.activities where project_id = p_id limit greatest(1, least(p_batch, 3000)));
  select count(*) into v_left from public.activities where project_id = p_id;
  if v_left > 0 then return v_left; end if;
  delete from public.app_settings where key = 'p6map:' || v_code;
  delete from public.projects where id = p_id;
  insert into public.audit_log(table_name, row_id, action, old_row, new_row)
  values ('projects', p_id, 'DELETE_PROJECT', jsonb_build_object('id', p_id, 'code', v_code), null);
  return 0;
end $$;

revoke all on function public.admin_delete_project(text, text, int) from public, anon;
grant execute on function public.admin_delete_project(text, text, int) to authenticated;
