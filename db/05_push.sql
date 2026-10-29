-- DMC Progress ERP — 05: phone / browser push notifications
-- Safe to run again (idempotent). Applied via the Supabase MCP on 2026-10-29.
-- Keys (VAPID) and the hook secret live in private.push_config and are NOT in this repo.
-- Flow: row change → trigger push_notify() → pg_net POST → Edge Function "push" → Web Push to each subscribed device.

create extension if not exists pg_net with schema extensions;

-- Devices that agreed to receive notifications (one row per browser / phone)
create table if not exists public.push_subscriptions (
  endpoint text primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  p256dh text not null,
  auth text not null,
  ua text,
  created_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions (user_id);
alter table public.push_subscriptions enable row level security;
drop policy if exists push_sub_select on public.push_subscriptions;
create policy push_sub_select on public.push_subscriptions for select to authenticated using (user_id = auth.uid());
drop policy if exists push_sub_delete on public.push_subscriptions;
create policy push_sub_delete on public.push_subscriptions for delete to authenticated using (user_id = auth.uid());
grant select, delete on public.push_subscriptions to authenticated;

-- Server-only settings (not reachable through the API)
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.push_config (
  id int primary key default 1 check (id = 1),
  fn_url text not null,
  hook_secret text not null,
  vapid_public text not null,
  vapid_private text not null,
  vapid_subject text not null default 'mailto:admin@dmc.local'
);

-- Register / remove this device for the signed-in user (a device moves to whoever signs in on it)
create or replace function public.push_subscribe(p_endpoint text, p_p256dh text, p_auth text, p_ua text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into public.push_subscriptions (endpoint, user_id, p256dh, auth, ua)
  values (p_endpoint, auth.uid(), p_p256dh, p_auth, left(p_ua, 300))
  on conflict (endpoint) do update set user_id = auth.uid(), p256dh = excluded.p256dh, auth = excluded.auth, ua = excluded.ua, created_at = now();
end $$;
create or replace function public.push_unsubscribe(p_endpoint text)
returns void language sql security definer set search_path = public as $$
  delete from public.push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
$$;
-- Public key the browser needs to subscribe (safe to share)
create or replace function public.push_public_key() returns text
language sql stable security definer set search_path = public as $$ select vapid_public from private.push_config where id = 1 $$;
-- Full settings, for the Edge Function only (service role)
create or replace function public.push_config_get()
returns table (hook_secret text, vapid_public text, vapid_private text, vapid_subject text)
language sql stable security definer set search_path = public as $$
  select hook_secret, vapid_public, vapid_private, vapid_subject from private.push_config where id = 1 $$;

revoke all on function public.push_subscribe(text, text, text, text) from public, anon;
revoke all on function public.push_unsubscribe(text) from public, anon;
revoke all on function public.push_public_key() from public, anon;
revoke all on function public.push_config_get() from public, anon, authenticated;
grant execute on function public.push_subscribe(text, text, text, text) to authenticated;
grant execute on function public.push_unsubscribe(text) to authenticated;
grant execute on function public.push_public_key() to authenticated;
grant execute on function public.push_config_get() to service_role;

-- Trigger: hand the changed row to the Edge Function (never blocks or breaks the write)
create or replace function public.push_notify() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare c record; rec jsonb; old_rec jsonb;
begin
  select fn_url, hook_secret into c from private.push_config where id = 1;
  if c is null then return new; end if;
  rec := to_jsonb(new) - 'image' - 'photos' - 'log';
  if tg_table_name = 'chat_messages' then rec := rec || jsonb_build_object('has_image', new.image is not null); end if;
  if tg_op = 'UPDATE' then old_rec := to_jsonb(old) - 'image' - 'photos' - 'log'; end if;
  perform net.http_post(
    url := c.fn_url,
    body := jsonb_build_object('table', tg_table_name, 'type', tg_op, 'record', rec, 'old_record', old_rec),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-hook-secret', c.hook_secret),
    timeout_milliseconds := 5000);
  return new;
exception when others then
  return new;
end $$;
revoke all on function public.push_notify() from public, anon, authenticated;

drop trigger if exists trg_push_pu on public.progress_updates;
create trigger trg_push_pu after insert or update of status on public.progress_updates
  for each row when (new.status in ('submitted','endorsed','returned','approved')) execute function public.push_notify();
drop trigger if exists trg_push_notif on public.notifications;
create trigger trg_push_notif after insert on public.notifications
  for each row execute function public.push_notify();
drop trigger if exists trg_push_chat on public.chat_messages;
create trigger trg_push_chat after insert on public.chat_messages
  for each row execute function public.push_notify();
