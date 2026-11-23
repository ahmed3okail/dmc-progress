-- 33: delay responsibility "supplier" (Ahmed 2026-11-23). The site engineer now always picks the party (no default in the app).
-- v2 test DB only for now — apply to live when releasing v2.
alter table public.progress_updates drop constraint if exists progress_updates_delay_party_chk;
alter table public.progress_updates add constraint progress_updates_delay_party_chk
  check (delay_party is null or delay_party = any (array['contractor','subcon','supplier','owner','consultant','other']));
