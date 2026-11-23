-- 32: AI assistant daily quota (v2 test DB). Each signed-in user may ask the AI
-- assistant a limited number of questions per day (counted per Cairo day).
-- Returns the questions left after this one (>= 0), -1 = daily limit reached, -2 = no access.
create table if not exists private.assistant_log(
  id bigserial primary key,
  user_id uuid not null,
  at timestamptz not null default now()
);
create index if not exists assistant_log_user_at on private.assistant_log(user_id, at);

create or replace function public.assistant_take(p_limit int default 60)
returns int language plpgsql security definer set search_path = public, private as $$
declare n int; d date := (now() at time zone 'Africa/Cairo')::date;
begin
  if auth.uid() is null or not app_has_access() then return -2; end if;
  select count(*) into n from private.assistant_log
   where user_id = auth.uid() and (at at time zone 'Africa/Cairo')::date = d;
  if n >= greatest(1, least(p_limit, 500)) then return -1; end if;
  insert into private.assistant_log(user_id) values (auth.uid());
  return greatest(1, least(p_limit, 500)) - n - 1;
end $$;
revoke all on function public.assistant_take(int) from public, anon;
grant execute on function public.assistant_take(int) to authenticated;
