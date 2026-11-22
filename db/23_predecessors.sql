-- 23: activity logic for out-of-sequence checks — applied to the v2 test DB first; apply to live when releasing v2.
-- predecessors = activity codes (same project) of finish-to-start predecessors, from the schedule import.
-- The app flags an activity "out of sequence" when it has progress while a predecessor is below 100%.
alter table public.activities add column if not exists predecessors text[];

-- note: db/22 (out-of-scope) was applied to the test DB on 2026-11-22 and then dropped from the app at Ahmed's request;
-- its unused columns (out_of_scope, oos_note, oos_at, oos_by) remain on the test DB only. Do not apply db/22 to live.
