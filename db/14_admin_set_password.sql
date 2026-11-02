-- 14: admin sets a new password for any user (forgot password), from the Users tab.
-- Only an active admin can call it; the password is hashed with bcrypt (pgcrypto), never stored in plain text.
create or replace function public.admin_set_password(p_user uuid, p_password text)
returns void
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
begin
  if app_role() is distinct from 'admin' then
    raise exception 'Only an administrator can reset passwords';
  end if;
  if p_password is null or length(p_password) < 8 then
    raise exception 'Password must be at least 8 characters';
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
         updated_at = now()
   where id = p_user;
  if not found then raise exception 'User not found'; end if;
  -- shows in the admin activity log as "password"
  insert into public.audit_log(table_name, row_id, action, old_row, new_row)
  values ('profiles', p_user::text, 'PASSWORD', null,
          jsonb_build_object('id', p_user, 'full_name', (select full_name from public.profiles where id = p_user)));
end $$;

revoke all on function public.admin_set_password(uuid, text) from public, anon;
grant execute on function public.admin_set_password(uuid, text) to authenticated;
