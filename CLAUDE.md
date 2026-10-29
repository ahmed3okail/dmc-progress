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
- `db/01_schema.sql` — full schema, already run on Supabase. `db/02_first_admin.sql` — admin helper.
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
- Workflow: `draft → submitted` (site) `→ endorsed` (CM, may adjust %/qty with a note; original values kept, engineer is notified) `→ approved` (Planning). CM or Planning can `returned`. Setting `require_cm` in `app_settings`.
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

## Rules for changes
- Old versions (DMC Site Progress v1–v4) live outside this repo; don't recreate them.
- DB changes: add a new file `db/03_<name>.sql` (never edit already-run files) and give Ahmed exact steps to run it in SQL Editor — or use the Supabase MCP if connected.
- After every change: commit with a clear message, push to `main`, tell Ahmed in Arabic what changed and what to test.

## Known limitations / roadmap
- No direct P6 integration; CSV import only. Next: XER/XML import.
- No offline mode, no push notifications.
- Data load capped at 10,000 rows per table — add pagination before large projects.
- Vercel Hobby is non-commercial; company adoption needs IT approval or a paid/internal host.
- Don't upload real project data without company approval.
