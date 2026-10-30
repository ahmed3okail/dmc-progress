-- DMC Progress ERP — 06: Planning returns go back to the Construction Manager
-- When require_cm is on, Planning can no longer send an update straight back to the site engineer:
-- "return" moves it endorsed → submitted (CM queue again), with Planning's note in review_comment.
-- The CM then fixes/adjusts and endorses again, or returns it to the engineer.
-- When require_cm is off there is no CM step, so Planning still returns to the engineer.
-- Safe to run again. Applied via the Supabase MCP on 2026-10-30.

create or replace function public.enforce_update_workflow()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare r app_role := app_role(); d discipline := app_discipline();
        need_cm boolean := coalesce((select (value)::text::boolean from app_settings where key='require_cm'), true);
begin
  if r is null then raise exception 'No active profile for this user'; end if;
  new.updated_at := now();
  if r = 'admin' then return new; end if;

  if tg_op = 'INSERT' then
    if r <> 'site' then raise exception 'Only site engineers create updates'; end if;
    if new.discipline <> d then raise exception 'Discipline mismatch'; end if;
    if new.status not in ('draft','submitted') then raise exception 'New updates must be draft or submitted'; end if;
    if (select discipline from activities where id = new.activity_id) <> d then raise exception 'Activity not assigned to your discipline'; end if;
    new.by_user := auth.uid();
    return new;
  end if;

  if old.status = 'approved' then raise exception 'Approved updates cannot be changed'; end if;

  if r = 'site' then
    if old.discipline <> d then raise exception 'Not your update'; end if;
    if not ((old.status = 'draft' and new.status in ('draft','submitted'))
         or (old.status = 'submitted' and new.status = 'draft')) then
      raise exception 'Site engineer cannot move % → %', old.status, new.status; end if;
    if new.cm_at is distinct from old.cm_at or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'Review fields are read-only'; end if;
    return new;
  end if;

  if r = 'cm' then
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
