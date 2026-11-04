-- DME Progress Tracker — 15: Landscape Engineer discipline (LND), next to CIV / ARC / MEC / ELE.
-- Applied 2026-11-04 via the Supabase MCP. Additive only.
alter type public.discipline add value if not exists 'LND';
