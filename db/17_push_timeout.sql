-- 17_push_timeout.sql (2026-11-05)
-- The push Edge Function takes 7-8 s on a cold start; pg_net gave up at 5 s and logged a timeout
-- although the function returned 200. Wait up to 15 s so the response log is accurate.
create or replace function public.push_notify()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare c record; rec jsonb; old_rec jsonb;
begin
  rec := to_jsonb(new) - 'image' - 'photos' - 'log' - 'html';
  if rec->>'source' in ('demo','opening') or coalesce(rec->>'id','') like 'R_seed%' then return new; end if;
  select fn_url, hook_secret into c from private.push_config where id = 1;
  if c is null then return new; end if;
  if tg_table_name = 'chat_messages' then rec := rec || jsonb_build_object('has_image', new.image is not null); end if;
  if tg_op = 'UPDATE' then old_rec := to_jsonb(old) - 'image' - 'photos' - 'log' - 'html'; end if;
  perform net.http_post(
    url := c.fn_url,
    body := jsonb_build_object('table', tg_table_name, 'type', tg_op, 'record', rec, 'old_record', old_rec),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-hook-secret', c.hook_secret),
    timeout_milliseconds := 15000);
  return new;
exception when others then
  return new;
end $function$;
