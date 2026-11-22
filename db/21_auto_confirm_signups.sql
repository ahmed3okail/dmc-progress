-- 21: self sign-ups ("Create account") are confirmed at once, so the confirmation e-mail link
-- (which pointed to localhost because the project's Site URL was never set) is not needed.
-- Safe because a new account gets role 'site' with no discipline / project = sees nothing
-- until the admin grants access (db/12 app_has_access).
-- Applied to the v2 TEST DB only, 2026-11-22. ⚠ Review before applying to live (Ahmed asked to re-check it).
create or replace function public.auto_confirm_signup()
 returns trigger language plpgsql security definer set search_path to 'public', 'auth'
as $function$ begin
  if new.email_confirmed_at is null then new.email_confirmed_at := now(); end if;
  return new;
end $function$;
revoke all on function public.auto_confirm_signup() from public, anon, authenticated;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'on_auth_user_autoconfirm') then
    create trigger on_auth_user_autoconfirm before insert on auth.users for each row execute function public.auto_confirm_signup();
  end if;
end $$;
update auth.users set email_confirmed_at = now() where email_confirmed_at is null;
