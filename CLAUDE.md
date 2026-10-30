# CLAUDE.md — DMC Progress ERP

Read this whole file before doing anything. It is the full project context.

## Who you work with
- Owner: Ahmed (site/planning engineer at DMC-CURVE). **Not a programmer.**
- You are the project's programmer: decide, write all code, commit and push to `main` yourself. Vercel auto-deploys from `main`.
- Reply in **Egyptian Arabic**, short and direct.
- **Never ask for passwords or secret keys.** If he pastes one (database password, `sb_secret_...`, `service_role`), tell him to revoke/reset it immediately and do not use it.

## Chat formatting rules (Arabic + English) — always apply
Mixed Arabic/English on one line flips and becomes unreadable.
1. One step = one line = one action. Numbered list.
2. Every line starts with Arabic, never with an English word.
3. English terms go at the END of the line after a colon, in backticks: `اضغط على: `Save``
4. Never chain English words with arrows (Settings ← API). Split into separate numbered steps.
5. Values to type/copy (usernames, URLs, SQL, commands) go in their own code block.
6. Max one English term per line.
7. Headings and bold labels in Arabic only.
8. Keep it short: what to do, then what to send back.

## What the app is
Construction progress tracking for DMC-CURVE. Site engineers update progress on activities imported from a Primavera P6 schedule (via CSV — **no direct P6 integration; never claim one**). Planning and management get consolidated, weighted progress reporting.

## Architecture (all free tools)
```
Browser (mobile / desktop)
   │
Vercel (Hobby, framework "Other", no build)  ← static files from this repo
   │  supabase-js via esm.sh, publishable key
Supabase (free): PostgreSQL + Auth + Storage (bucket site-photos, private) + Realtime
```
- `DMC Progress ERP.dc.html` — the whole app (one file). Opens directly in a browser. Uses `support.js` runtime (generated — **never edit support.js**).
- `config.js` — Supabase URL + publishable key (safe to publish). Never put a secret key here.
- `index.html` — redirects to the app. `vercel.json` — headers.
- `db/01_schema.sql` — full schema, already run on Supabase. `db/02_first_admin.sql` — admin helper. ⚠ Neither file is in the repo yet — ask Ahmed to upload them.
- `db/03_chat.sql` — team chat tables (`chat_messages`, `chat_reads`), `chat_room_visible()`, `chat_directory()`, RLS, realtime; also confirms + promotes `admin@dmc.local`.
- `db/04_demo_data.sql` — loads the demo data directly (generated from `seed()` + `MAP.*.to`; no photos). Re-runnable: deletes old demo rows first; pauses user triggers inside one transaction.
- `db/05_push.sql` — push notifications: `push_subscriptions`, `private.push_config` (VAPID keys + hook secret, set via MCP, **not in repo**), RPCs `push_subscribe/unsubscribe/public_key/config_get`, trigger `push_notify()` (pg_net → Edge Function). Applied 2026-10-29.
- `db/07_cutoff_delay_party.sql` — weekly cut-off: `progress_updates.delay_party` (contractor/owner/consultant/subcon/other), `app_settings.cutoff_dow` (0=Sun…4=Thu, default Thu), `cutoff_due()`, `send_cutoff_reminders()` + pg_cron `dmc-cutoff-reminders` (06:00 UTC daily → reminder to each discipline with un-updated activities on the eve and on the cut-off day; goes to phone via the notifications push trigger). Applied 2026-10-30.
- `db/08_remaining_days.sql` — `progress_updates.remaining_days` (site engineer's estimate of days to finish). Applied 2026-10-30.
- `supabase/functions/push/index.ts` — Edge Function `push` (verify_jwt off; checks `x-hook-secret`, or a user JWT for `{test:true}`). Decides recipients: submitted→CM of project (or Planning if `require_cm` off), endorsed→Planning, returned/approved→engineer, notifications→engineers of discipline, chat→room members. Skips demo inserts.
- `sw.js` (service worker: show push + open app), `manifest.json`, `icon-192.png`, `icon-512.png` — installable app (PWA). iPhone needs “Add to Home Screen” before push works.
- **Two modes:** DEMO (no config → data in browser localStorage only) and LIVE (Supabase, shared, real-time).

## File format rules for `DMC Progress ERP.dc.html`
- It's a "Design Component": template markup inside `<x-dc>…</x-dc>`, logic in `<script data-dc-script>` as `class Component extends DCLogic { renderVals(){…} }`.
- Template holes are dotted lookups only: `{{ user.name }}` — no expressions. Compute in `renderVals()`.
- Loops `<sc-for list="{{ items }}" as="item">`, conditions `<sc-if value="{{ flag }}">`. Always keep `hint-*` attributes.
- **Inline styles only**, no CSS classes. Plain JS, no imports/TypeScript.
- Keep both languages in `I18N.en` / `I18N.ar` when adding text. Arabic = RTL.

## Business rules (enforced in DB triggers + RLS, mirror them in UI)
- Roles: `site` (site engineer), `cm` (Construction Manager), `planner` (Planning Engineer), `pm` (Project Manager), `admin`.
- Site engineers are identified by **discipline**, not names: `CIV`, `ARC`, `MEC`, `ELE`.
- Workflow: `draft → submitted` (site) `→ endorsed` (CM, may adjust %/qty with a note; original values kept, engineer is notified) `→ approved` (Planning). CM can `returned` (to engineer). Planning's return goes back to the CM (`endorsed → submitted`, note in `review_comment`, `reviewer_role='PL'`) — `db/06_return_to_cm.sql`. If `require_cm` is off, Planning returns to the engineer.
- **Only approved updates affect official actual progress.** Approved rows are immutable. History is preserved (`prev_id`, `log`, `audit_log`).
- Project progress = weighted by activity `weight`. Portfolio = weighted by `contract_value`.
- Location hierarchy: **Zone first, then Building**.
- Photos attach to the update and appear in reports next to the activity.
- Weekly report can be generated **per project**.
- Demo data is always marked (`is_demo` / `src:'demo'`) and visibly labelled; admin can load/remove it from the Data screen.

## Login & users
- Login accepts a username: no `@` → `username@dmc.local`. Sign-up creates a profile with role `site` and no access.
- Admin has a **Users** tab in the app: set role, discipline, projects, active/disabled. No need to open Supabase for permissions.
- First admin: user `Admin` (→ `admin@dmc.local`), promoted with:
```sql
update profiles set role='admin', discipline='CIV' where id=(select id from auth.users where email='admin@dmc.local');
```

## Current state (2026-10-29)
- Supabase project ref `ainajecdyktkdhfzgsgd`; schema ran successfully.
- Repo `ahmed3okail/dmc-progress`, deployed on Vercel.
- ⚠ A `sb_secret_` key and the database password were pasted in chat earlier — Ahmed was told to revoke/reset both. Confirm with him that it's done.
- Pending: Ahmed creates the `Admin` account on the live site, then runs the SQL above. Supabase "Confirm email" may need to be turned off for username logins.

## Features added 2026-10-29
- Demo data v3 (localStorage key `dmc-erp:demo:v3`): 5 projects, 53 activities across CIV/ARC/MEC/ELE, pending/endorsed/returned/draft updates, labelled DEMO PHOTO placeholders, demo chat.
- Dashboard tab (`dash`) for CM, Planning, PM: KPIs, ring gauge, S-curve, weekly gain, project health / zone breakdown, discipline performance, workflow, delay reasons, most-behind list, look-ahead, activity feed.
- Users tab: role/pending/disabled filters, search, "Add user" (signUp via a second client without session, then profile update), permissions matrix.
- Team chat (header "Chat" button): general room, one group per project, private chats, unread badges, read ticks in private chats, photo attach. DEMO = browser only; LIVE needs `db/03_chat.sql`.
- CSV import column is `discipline` (old `assigned_to` still accepted).
- Look-ahead tab is available to every role (site, CM, Planning, PM, admin).
- Site "Quick update" (bulk) button removed from the activity list (2026-10-30); bulk code still in the file but unreachable.
- Weekly report redesigned (formal A4): two modes — Consultant/Client (external) and Internal (adds contract values, approval workflow, missing updates, internal sign-off); report no. `WPR-<code>-<ISO week>`, executive summary + KPIs, S-curve, zone/discipline tables, progressed this week, behind schedule, 2-week look-ahead, delay reasons, photos, remarks box (saved per device), sign-off block. Language chips in the report toolbar.
- Branding: `logo.png` (DMC | CURVE, cropped from the company image) in sidebar, header and login; brand green `#0b4a3e`/`#0e5a4b` for dark surfaces and primary buttons, gold `#c5a45a` accent, `#f1e8cf` light gold. Header ↻ refresh button (full page reload). Mobile bottom nav fits all tabs without scrolling.

## Demo users (live Supabase, 2026-10-29)
- Created directly in `auth.users` via the Supabase MCP, confirmed, sharing one demo password (told to Ahmed in chat; not stored here).
- `civil.eng` / `arch.eng` / `mech.eng` / `elec.eng` (site, CIV/ARC/MEC/ELE), `cm` (cm, CIV), `planner`, `pm`. Site + CM are members of P1–P5.

## Rules for changes
- Old versions (DMC Site Progress v1–v4) live outside this repo; don't recreate them.
- DB changes: add a new file `db/03_<name>.sql` (never edit already-run files) and give Ahmed exact steps to run it in SQL Editor — or use the Supabase MCP if connected.
- After every change: commit with a clear message, push to `main`, tell Ahmed in Arabic what changed and what to test.

## Known limitations / roadmap
- No direct P6 integration; CSV import only. Next: XER/XML import.
- No offline mode. Push notifications added 2026-10-29 (Data screen → Phone notifications; banner after login).
- Data load capped at 10,000 rows per table — add pagination before large projects.
- Vercel Hobby is non-commercial; company adoption needs IT approval or a paid/internal host.
- Don't upload real project data without company approval.

## Features added 2026-10-30
- Weekly cut-off cycle (7 days ending on the cut-off day). `derive()` sets `a.due` (planned start ≤ cut-off and not complete) and `a.updW` (non-draft, non-returned update in the cycle). Dashboard card "Weekly update compliance" per discipline + cut-off day chips (admin in LIVE writes `app_settings.cutoff_dow`; DEMO saves to localStorage `dmc-erp:cutDow`).
- Delay responsibility (`party`, default from `DPARTY` by reason) chosen with the delay reason; shown wherever the reason is shown (`dlP()`).
- Site engineer enters "Remaining duration to finish the activity" (days, `remD` → `remaining_days`) with every update; required when progress is 1–99%. Shown to CM/Planning in review and pending details.
- Activity detail "Productivity & forecast" (hidden from site engineers): remaining qty, actual and required rate per day, remaining duration, forecast finish (`prodOf()`). Forecast = date of the latest non-returned update + the engineer's remaining days; falls back to the actual production rate when no estimate exists. Red when after planned finish.
- Weekly report: section numbers are assigned automatically; new tables "Compared with last week" (▲/▼), "Top 5 risks" (weighted slippage + overdue/finishing in 14 days + forecast late + no recent update), "Delays by responsibility".
- Bottom nav / sidebar tab icons (`TAB_ICON`). Site engineer list starts with a "This week — before the cut-off" section (not-updated first), then other activities.
