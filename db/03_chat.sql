-- DMC Progress ERP — 03: team chat + first administrator
-- Run once in Supabase → SQL Editor. Safe to run again (idempotent).
-- Rooms: 'general' (all active users), 'proj:<project id>' (project members; planner / pm / admin see all), 'dm:<user id>:<user id>' (two people).

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  room text not null check (room ~ '^(general|proj:.+|dm:.+)$'),
  sender uuid not null default auth.uid() references auth.users(id) on delete cascade,
  body text not null default '' check (char_length(body) <= 4000),
  image text check (image is null or char_length(image) <= 400000),   -- compressed JPEG as data URL
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_room_idx on public.chat_messages (room, created_at desc);

create table if not exists public.chat_reads (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  room text not null,
  last_read timestamptz not null default now(),
  primary key (user_id, room)
);

-- Who may see / post in a room
create or replace function public.chat_room_visible(r text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles me where me.id = auth.uid() and coalesce(me.active, true)) and (
    r = 'general'
    or (r like 'proj:%' and exists (
          select 1 from public.profiles p
          where p.id = auth.uid()
            and (p.role::text in ('admin','pm','planner')
                 or exists (select 1 from public.project_members m where m.user_id = p.id and m.project_id::text = substring(r from 6)))))
    or (r like 'dm:%' and auth.uid()::text = any (string_to_array(substring(r from 4), ':')))
  );
$$;

-- Names and roles of active colleagues, for starting a private chat (profiles itself stays protected by RLS)
create or replace function public.chat_directory() returns table (id uuid, full_name text, role text, discipline text)
language sql stable security definer set search_path = public as $$
  select p.id, p.full_name, p.role::text, p.discipline::text
  from public.profiles p
  where coalesce(p.active, true)
    and exists (select 1 from public.profiles me where me.id = auth.uid() and coalesce(me.active, true))
  order by p.full_name;
$$;

alter table public.chat_messages enable row level security;
alter table public.chat_reads enable row level security;

drop policy if exists chat_msg_select on public.chat_messages;
create policy chat_msg_select on public.chat_messages for select to authenticated using (public.chat_room_visible(room));
drop policy if exists chat_msg_insert on public.chat_messages;
create policy chat_msg_insert on public.chat_messages for insert to authenticated with check (sender = auth.uid() and public.chat_room_visible(room));
drop policy if exists chat_msg_delete on public.chat_messages;
create policy chat_msg_delete on public.chat_messages for delete to authenticated using (
  sender = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role::text = 'admin'));

drop policy if exists chat_reads_select on public.chat_reads;
create policy chat_reads_select on public.chat_reads for select to authenticated using (user_id = auth.uid() or public.chat_room_visible(room));
drop policy if exists chat_reads_insert on public.chat_reads;
create policy chat_reads_insert on public.chat_reads for insert to authenticated with check (user_id = auth.uid());
drop policy if exists chat_reads_update on public.chat_reads;
create policy chat_reads_update on public.chat_reads for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, delete on public.chat_messages to authenticated;
grant select, insert, update on public.chat_reads to authenticated;
grant execute on function public.chat_room_visible(text) to authenticated;
grant execute on function public.chat_directory() to authenticated;

-- Real-time delivery of new messages and read receipts
do $$ begin
  begin alter publication supabase_realtime add table public.chat_messages; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.chat_reads; exception when duplicate_object then null; end;
end $$;

-- First administrator: confirm the Admin account (username "Admin") and give it the admin role
update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now()) where email = 'admin@dmc.local';
update public.profiles set role = 'admin', discipline = 'CIV', active = true
where id = (select id from auth.users where email = 'admin@dmc.local');

-- Check: should return one row with role = admin
select p.role, p.discipline, p.active, u.email from public.profiles p join auth.users u on u.id = p.id where u.email = 'admin@dmc.local';
