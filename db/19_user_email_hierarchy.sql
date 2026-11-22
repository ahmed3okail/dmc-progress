-- 19: users by e-mail + team hierarchy (who reports to whom) — v2 test DB first.
-- profiles.email      : copy of the sign-in e-mail (real address, or username@dmc.local)
-- profiles.job_title  : free text shown in the Users tab and team tree
-- profiles.reports_to : the user's direct manager (another profile). Display only for now —
--                       review routing still follows the project (CM of the project → Planning).
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists job_title text;
alter table public.profiles add column if not exists reports_to uuid references public.profiles(id) on delete set null;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_reports_to_self') then
    alter table public.profiles add constraint profiles_reports_to_self check (reports_to is null or reports_to <> id);
  end if;
end $$;

create index if not exists profiles_reports_to_idx on public.profiles(reports_to);

update public.profiles p set email = u.email from auth.users u where u.id = p.id and p.email is distinct from u.email;

-- new accounts get their e-mail copied
create or replace function public.handle_new_user()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$ begin
  insert into profiles(id, full_name, email) values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email), new.email)
  on conflict (id) do update set email = excluded.email;
  return new;
end $function$;

-- no loops (A reports to B reports to A)
create or replace function public.profiles_no_cycle()
 returns trigger language plpgsql set search_path to 'public'
as $function$
declare cur uuid := new.reports_to; n int := 0;
begin
  while cur is not null and n < 60 loop
    if cur = new.id then raise exception 'Reporting line would loop back to the same person'; end if;
    select reports_to into cur from profiles where id = cur;
    n := n + 1;
  end loop;
  return new;
end $function$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_profiles_no_cycle') then
    create trigger trg_profiles_no_cycle before insert or update of reports_to on public.profiles
      for each row execute function public.profiles_no_cycle();
  end if;
end $$;

-- only the admin changes these (profiles UPDATE policy is already admin-only: p_profiles_admin)
