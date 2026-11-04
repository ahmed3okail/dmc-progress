-- 16_opening_balance.sql (2026-11-04)
-- Opening balance: when Planning imports a schedule CSV that already has progress
-- (actual_start / actual_finish / actual_pct from the latest P6 update), the app
-- inserts one APPROVED update per activity with source = 'opening'.
-- Only Planning (or admin) may do this, only as an insert, and only when the
-- activity has no approved update yet. Push notifications are skipped for these rows.

create or replace function public.enforce_update_workflow()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r app_role := app_role(); d discipline := app_discipline();
        need_cm boolean := coalesce((select (value)::text::boolean from app_settings where key='require_cm'), true);
        a_disc discipline; a_proj text;
begin
  if r is null then raise exception 'No active profile for this user'; end if;
  new.updated_at := now();
  if r = 'admin' then return new; end if;

  if tg_op = 'INSERT' then
    -- Planning: opening balance from the P6 import
    if r = 'planner' and new.source = 'opening' then
      if new.status <> 'approved' then raise exception 'Opening balance must be approved'; end if;
      select discipline, project_id into a_disc, a_proj from activities where id = new.activity_id;
      if a_proj is null then raise exception 'Activity not found'; end if;
      if not can_see_project(a_proj) then raise exception 'You are not a member of this project'; end if;
      if exists (select 1 from progress_updates where activity_id = new.activity_id and status = 'approved') then
        raise exception 'Activity already has approved progress'; end if;
      new.discipline := a_disc;
      new.by_user := auth.uid();
      new.reviewer_user := auth.uid();
      new.reviewer_role := 'PL';
      new.reviewed_at := coalesce(new.reviewed_at, now());
      return new;
    end if;
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

-- No phone notifications for demo rows or opening-balance rows (an import can add hundreds)
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
    timeout_milliseconds := 5000);
  return new;
exception when others then
  return new;
end $function$;
