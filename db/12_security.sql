-- 12: security hardening (2026-11-02). Create / alter / revoke only (no drops).
-- 1) "Has access" = active profile that is not a bare new sign-up (site role with no discipline).
create or replace function public.app_has_access() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles p where p.id = auth.uid() and p.active
                 and (p.role <> 'site' or p.discipline is not null));
$$;

-- 2) Progress update rules: a site engineer needs a discipline, must match it, and must be a member of the activity's project.
create or replace function public.enforce_update_workflow() returns trigger
language plpgsql security definer set search_path = public as $function$
declare r app_role := app_role(); d discipline := app_discipline();
        need_cm boolean := coalesce((select (value)::text::boolean from app_settings where key='require_cm'), true);
        a_disc discipline; a_proj text;
begin
  if r is null then raise exception 'No active profile for this user'; end if;
  new.updated_at := now();
  if r = 'admin' then return new; end if;

  if tg_op = 'INSERT' then
    if r <> 'site' then raise exception 'Only site engineers create updates'; end if;
    if d is null then raise exception 'Your account has no discipline yet — ask the administrator'; end if;
    if new.discipline is distinct from d then raise exception 'Discipline mismatch'; end if;
    if new.status not in ('draft','submitted') then raise exception 'New updates must be draft or submitted'; end if;
    select discipline, project_id into a_disc, a_proj from activities where id = new.activity_id;
    if a_disc is distinct from d then raise exception 'Activity not assigned to your discipline'; end if;
    if not can_see_project(a_proj) then raise exception 'You are not a member of this project'; end if;
    new.by_user := auth.uid();
    return new;
  end if;

  if old.status = 'approved' then raise exception 'Approved updates cannot be changed'; end if;

  if r = 'site' then
    if d is null or old.discipline is distinct from d then raise exception 'Not your update'; end if;
    if new.discipline is distinct from old.discipline or new.activity_id is distinct from old.activity_id then raise exception 'Activity and discipline cannot change'; end if;
    if not ((old.status = 'draft' and new.status in ('draft','submitted'))
         or (old.status = 'submitted' and new.status = 'draft')) then
      raise exception 'Site engineer cannot move % → %', old.status, new.status; end if;
    if new.cm_at is distinct from old.cm_at or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'Review fields are read-only'; end if;
    return new;
  end if;

  if r = 'cm' then
    if not can_see_project((select project_id from activities where id = old.activity_id)) then raise exception 'You are not a member of this project'; end if;
    if not (old.status = 'submitted' and new.status in ('endorsed','returned')) then
      raise exception 'Construction Manager can only act on submitted updates'; end if;
    if (new.pct <> old.pct or new.qty <> old.qty) and (new.orig_pct is null or coalesce(new.adj_note,'') = '') then
      raise exception 'Adjustments need original values and a note'; end if;
    new.cm_by := case when new.status = 'endorsed' then auth.uid() else old.cm_by end;
    if new.status = 'returned' then new.reviewer_user := auth.uid(); end if;
    return new;
  end if;

  if r = 'planner' then
    if need_cm then
      if not (old.status = 'endorsed' and new.status in ('approved','submitted')) then
        raise exception 'Planning can approve, or return to the Construction Manager, updates approved by the CM'; end if;
      if new.status = 'submitted' then
        if coalesce(new.review_comment,'') = '' then raise exception 'A note is required when returning to the Construction Manager'; end if;
        new.cm_at := null; new.cm_by := null; new.reviewer_role := 'PL';
      end if;
    else
      if not (old.status in ('submitted','endorsed') and new.status in ('approved','returned')) then
        raise exception 'Planning can only approve or return submitted updates'; end if;
    end if;
    if new.pct <> old.pct or new.qty <> old.qty then raise exception 'Planning cannot change values — return instead'; end if;
    new.reviewer_user := auth.uid();
    return new;
  end if;

  raise exception 'Role % cannot change progress updates', r;
end $function$;

-- 3) Chat: bare new sign-ups (no discipline / no role yet) see nothing.
create or replace function public.chat_room_visible(r text) returns boolean
language sql stable security definer set search_path = public as $$
  select app_has_access() and (
    r = 'general'
    or (r like 'proj:%' and exists (
          select 1 from public.profiles p
          where p.id = auth.uid()
            and (p.role::text in ('admin','pm','planner')
                 or exists (select 1 from public.project_members m where m.user_id = p.id and m.project_id::text = substring(r from 6)))))
    or (r like 'dm:%' and auth.uid()::text = any (string_to_array(substring(r from 4), ':')))
  );
$$;
create or replace function public.chat_directory() returns table(id uuid, full_name text, role text, discipline text)
language sql stable security definer set search_path = public as $$
  select p.id, p.full_name, p.role::text, p.discipline::text
  from public.profiles p
  where coalesce(p.active, true) and app_has_access()
  order by p.full_name;
$$;

-- 4) Read access for people / memberships: yourself, or anyone with access.
alter policy p_profiles_read on public.profiles using (id = auth.uid() or app_has_access());
alter policy p_members_read on public.project_members using (user_id = auth.uid() or app_has_access());

-- 5) Site photos: only people with access; overwrite only your own files (or admin).
alter policy sp_read on storage.objects using (bucket_id = 'site-photos' and public.app_has_access());
alter policy sp_write on storage.objects with check (bucket_id = 'site-photos' and public.app_has_access());
alter policy sp_update on storage.objects using (bucket_id = 'site-photos' and (owner = auth.uid() or owner_id = auth.uid()::text or public.app_role() = 'admin'));

-- 6) Functions: nothing callable without signing in; internal helpers not callable as RPC.
revoke execute on function public.app_role(), public.app_discipline(), public.app_has_access(), public.can_see_project(text),
  public.chat_directory(), public.chat_room_visible(text) from anon, public;
grant execute on function public.app_role(), public.app_discipline(), public.app_has_access(), public.can_see_project(text),
  public.chat_directory(), public.chat_room_visible(text) to authenticated;
revoke execute on function public.audit_row(), public.enforce_update_workflow(), public.handle_new_user(), public.push_notify()
  from anon, authenticated, public;
revoke execute on function public.cutoff_due(date) from anon, authenticated, public;
