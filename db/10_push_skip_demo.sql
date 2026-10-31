-- 10: don't call the push Edge Function for demo rows (sample data load inserts ~800 updates at once).
-- Same as push_notify() from 09, plus an early return for demo rows.
create or replace function public.push_notify() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare c record; rec jsonb; old_rec jsonb;
begin
  rec := to_jsonb(new) - 'image' - 'photos' - 'log' - 'html';
  if rec->>'source' = 'demo' or coalesce(rec->>'id','') like 'R_seed%' then return new; end if;
  select fn_url, hook_secret into c from private.push_config where id = 1;
  if c is null then return new; end if;
  if tg_table_name = 'chat_messages' then rec := rec || jsonb_build_object('has_image', new.image is not null); end if;
  if tg_op = 'UPDATE' then old_rec := to_jsonb(old) - 'image' - 'photos' - 'log' - 'html'; end if;
  perform net.http_post(
    url := c.fn_url,
    body := jsonb_build_object('table', tg_table_name, 'type', tg_op, 'record', rec, 'old_record', old_rec),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-hook-secret', c.hook_secret),
    timeout_milliseconds := 5000);
  return new;
exception when others then
  return new;
end $$;
