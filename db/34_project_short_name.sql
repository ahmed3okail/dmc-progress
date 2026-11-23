-- 34: short project name shown on project buttons / group headers (Ahmed 2026-11-23: P6 codes like "-NCE-Skala-Zone2.1-BL-REV.01 UP25.10" are too long).
-- Empty = the app shortens the code itself. v2 test DB only for now — apply to live when releasing v2.
alter table public.projects add column if not exists short_name text check (short_name is null or char_length(short_name) <= 30);
