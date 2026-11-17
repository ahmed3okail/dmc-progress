-- 18: only the primary admin (user "Admin" = admin@dmc.local) can set passwords from the Users tab.
-- Other admins (e.g. the IT account it.admin) get an error. Ahmed asked for this 2026-11-17.
create or replace function public.admin_set_password(p_user uuid, p_password text)
returns void
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
begin
  if app_role() is distinct from 'admin'
     or (select email from auth.users where id = auth.uid()) is distinct from 'admin@dmc.local' then
    raise exception 'Only the primary administrator can reset passwords';
  end if;
  if p_password is null or length(p_password) < 8 then
    raise exception 'Password must be at least 8 characters';
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
         updated_at = now()
   where id = p_user;
  if not found then raise exception 'User not found'; end if;
  insert into public.audit_log(table_name, row_id, action, old_row, new_row)
  values ('profiles', p_user::text, 'PASSWORD', null,
          jsonb_build_object('id', p_user, 'full_name', (select full_name from public.profiles where id = p_user)));
end $$;

revoke all on function public.admin_set_password(uuid, text) from public, anon;
grant execute on function public.admin_set_password(uuid, text) to authenticated;
