-- 31: accounts are created only by the administrator (Ahmed 2026-11-22: "خلي كل الاكونتس من خلال الادمن").
-- Self sign-up ("Create account") is blocked in the database: a new auth.users row is accepted only when an
-- admin allowed that e-mail a moment before (RPC admin_allow_signup, valid 10 minutes, used once).
-- The app's "Add user" calls admin_allow_signup, then signUp. Replaces db/21 (auto-confirm for everyone):
-- the same trigger on_auth_user_autoconfirm now confirms only allowed e-mails and refuses the rest.
-- To add a user by SQL / dashboard later: insert into private.signup_allow(email) first.
-- Applied to the v2 TEST DB only, 2026-11-22.
create schema if not exists private;
create table if not exists private.signup_allow(
  email text primary key,
  created_by uuid,
  expires_at timestamptz not null default now() + interval '10 minutes');
revoke all on private.signup_allow from public, anon, authenticated;

create or replace function public.admin_allow_signup(p_email text)
 returns void language plpgsql security definer set search_path to 'public', 'private'
as $function$
begin
  if app_role() is distinct from 'admin' then raise exception 'Only the administrator can create accounts'; end if;
  insert into private.signup_allow(email, created_by, expires_at)
    values (lower(trim(p_email)), auth.uid(), now() + interval '10 minutes')
    on conflict (email) do update set created_by = excluded.created_by, expires_at = excluded.expires_at;
end $function$;
revoke all on function public.admin_allow_signup(text) from public, anon;
grant execute on function public.admin_allow_signup(text) to authenticated;

create or replace function public.auto_confirm_signup()
 returns trigger language plpgsql security definer set search_path to 'public', 'private', 'auth'
as $function$
declare ok boolean;
begin
  delete from private.signup_allow where email = lower(new.email) and expires_at > now() returning true into ok;
  if ok is not true then
    raise exception 'Sign-up is disabled. Ask the administrator to create your account.';
  end if;
  if new.email_confirmed_at is null then new.email_confirmed_at := now(); end if;
  return new;
end $function$;
revoke all on function public.auto_confirm_signup() from public, anon, authenticated;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'on_auth_user_autoconfirm') then
    create trigger on_auth_user_autoconfirm before insert on auth.users for each row execute function public.auto_confirm_signup();
  end if;
end $$;
