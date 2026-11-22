-- 20: users added by the admin can sign in straight away (no confirmation e-mail needed).
-- Applied to the v2 test DB 2026-11-22. Admin only; writes an audit_log row (CONFIRM).
create or replace function public.admin_confirm_user(p_user uuid)
 returns void language plpgsql security definer set search_path to 'public', 'auth'
as $function$
begin
  if app_role() is distinct from 'admin' then raise exception 'Only the administrator can confirm accounts'; end if;
  update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now()) where id = p_user;
  insert into audit_log(table_name, row_id, action, actor, new_row)
    values ('auth.users', p_user::text, 'CONFIRM', auth.uid(), jsonb_build_object('email', (select email from auth.users where id = p_user)));
end $function$;
revoke all on function public.admin_confirm_user(uuid) from public, anon;
grant execute on function public.admin_confirm_user(uuid) to authenticated;
