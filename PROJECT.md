# SolRay — Project Handoff

Kanban app (projects → boards → tasks) built for Branko. All UI text is in **Croatian**.
App name is configurable in-app (default "Private Workspace", currently set to **"SolRay"**).

## Versioning (IMPORTANT)

**`VERSION` file at the repo root holds the current version (semver). `1.0.0` is the
base release.** Every user-facing change going forward is a NEW VERSION: bump the
number in `VERSION` in the same commit/push as the change, and add a line to the
version log below. The Actions workflow tags images with that version, `latest`,
and the commit sha. Server stacks pin an exact version (see dockge-compose.yml).

### Version log

| Version | What changed |
|---------|--------------|
| 1.4.0 | **Per-project file folders + thumbnails + list/grid view:** every project now has its own uploads folder named after the project (`uploads/<Projekt>/uuid_datoteka`), created automatically when the project is created; renaming a project renames the folder and rewrites stored paths. Uploads go to the project the board belongs to (Datoteke tab is per project: `GET/POST /api/projects/{id}/files`; legacy `/api/files` upload still works and accepts an optional `project_id` form field). Image uploads get JPEG thumbnails (Pillow, max 420px, stored next to the file as `*.thumb.jpg`) served by `GET /api/files/{id}/thumb?token=JWT` — query-token auth because `<img>` tags cannot send headers; legacy/non-image files get a 1px placeholder (or an icon in the UI). Files view has a **Lista / Mreža** toggle (persisted in localStorage): list rows with small thumbs, grid cards with big thumbs. `storage_path()` helper centralizes path resolution + guards against path escape.
| 1.3.2 | **Visible checklist on task cards:** checklist items now render **directly on the task card** (collapsed view) with a real checkbox per item — tick one and the row turns **green** (tinted background, green text, strike-through). Root rendering bug fixed: checkboxes were inheriting the generic text-input style (dark background + padding → invisible dark square). All checkboxes now have a clean 16px native look with green accent. Tasks **auto-open after creation** so the fresh checklist is immediately visible and tickable. Full checklist editor (add/rename/delete items) remains in Uredi. When every item is ticked, the task auto-completes (all-checked rule from 1.3.0). |
| 1.3.2 | **Checklist completion bug fix + card checklists:** found the real root cause of tasks never auto-completing: the SQLAlchemy session runs with `autoflush=False`, so the tick that triggered the recompute was still in memory when the completion COUNT ran — the flag always lagged one tick behind. Fixed with `db.flush()` inside `recompute_task_completion`. Also: the full checklist (item + checkbox) now renders **directly on the task card** and inside the editor (every row has a visible checkbox); a new task auto-opens after creation so the whole list is visible immediately; ticking a checkbox turns the row green; all checked → task auto-completes (green card, bottom of column), unchecking any item reopens it. Verified end-to-end through the UI: 0/5 → 5/5 → auto-complete → untick → reopen.
| 1.3.1 | **Phone keyboard fix + search relocation:** the search input moved from the content area into the **sidebar, right under the app name** (dark blue area), visible on every layer. The old code **autofocused** the search input on every render — on a phone, tapping a project re-rendered the view, focused the input, and forced the keyboard open. Autofocus is now completely gone; the keyboard only opens when the user taps the search field. Search results still render in the content area (main page shows results OR notifications, never both). |
| 1.3.0 | **Tasks: to-do checklists + completion.** New `TaskItem` model (`task_items` table: title, is_done, position). Tasks can have a checklist created inline in the new-task form (+ Stavka popisa) and edited in the expanded task (add/rename/toggle/delete per item). **A task with items auto-completes only when ALL items are checked** — the manual checkbox is disabled for such tasks (toggle endpoint returns 400). Tasks without items complete via the checkbox. Completed tasks render **green** (tinted card, green struck title) and **sort to the bottom** of their column (open first by position, then completed by completed_at). New API: `PATCH /api/tasks/{id}/completed`, `POST/PATCH/DELETE /api/tasks/{id}/items[/{item_id}]`. `TaskIn.items` is `None` = leave checklist untouched, list = replace it. Migration adds `tasks.completed` + `tasks.completed_at`. |
| 1.2.2 | Fix: "Cannot read properties of null (reading 'reset')" alert after creating a user — the handler read `event.currentTarget` *after* `await` (it's nulled by then). The user was always created; only the form-clear crashed. Pattern to remember: capture `const form = event.currentTarget` before any `await`. |
| 1.2.1 | **CRITICAL FIX — shared workspace:** every logged-in user now sees ALL projects, boards, and tasks and can work with them (create/edit/move/delete). Previously everything was filtered by owner/membership, so new users saw an empty app. Admin-only remains: user management (create/delete users), app settings (name, default columns, Postavke sections are hidden in the UI for non-admins). `ensure_board_access` / `ensure_project_manage` no longer restrict by owner; `/api/projects`, `/api/boards`, and search return everything; boards created without a project go into the first project instead of a per-user "Glavni projekt"; board-members endpoint kept as a no-op. |
| 1.2.0 | Notifications feature pack: tagging yourself or being assigned a task now creates a notification (self-notify no longer excluded); **Obavijesti badge** with unread count (orange, phone-style, refreshed on load/save/30s poll + after marking read); clicking a notification opens the task's board and marks it read; "Označi sve kao pročitano"; new API: `/api/notifications/unread-count`, `/api/notifications/read-all`, `/api/me/ntfy/test`; Settings ntfy panel got a **Testiraj** button returning the exact failure reason. ntfy topic note: any topic string works; phone app must subscribe to the identical topic on the same ntfy server URL. |
| 1.1.7 | Refined 1.1.6: narrow windows now get the **same desktop layout, scaled** — sidebar is fluid (`clamp(200px, 28vw, 260px)`), paddings/columns keep normal sizes, kanban min-column lowered to 190px so 2–3 columns fit at any width. Phone stacking only ≤480px. (1.1.6's separate compact look with 170px sidebar was too cramped — user wants the image-1 desktop look at every width.) |
| 1.1.6 | (Refined by 1.1.7) Narrow windows kept two-pane layout with a compact 170px sidebar tier. |
| 1.1.5 | (Superseded by 1.1.6) Reverted 1.1.4: restored the original 820px breakpoint. | |
| 1.1.4 | (Superseded by 1.1.6) Lowered breakpoint to 640px. |
| 1.1.3 | Version badge moved to the top-left corner beside the app name (small chip `vX.Y.Z`, per mockup). |
| 1.1.2 | Version badge in the sidebar (`vX.Y.Z` under the logged-in name): the frontend image bakes `VERSION` in at build time, nginx serves it at `/version.txt` (no-cache), and the sidebar fetches it fresh on every render — making server/browser staleness instantly visible. Workflow syncs the root VERSION into the frontend build context on every build. |
| 1.1.1 | Fix: Postavke button (left bar) opened the Files page instead of settings — a regression from the 1.1.0 tab cleanup; settings view is its own branch again. |
| 1.1.0 | UI overhaul: dark-blue sidebar / light-blue content / pink-purple buttons / white text; tasks where the current user is tagged (@username in text or assignee) render ORANGE (`mentions_me` flag from backend, `.task.mentions-me`); Postavke tab removed from board topbar (settings button stays in the left bar); Obavijesti moved to the main page (below search, projects layer only); board topbar now has only Ploča and Datoteke. |
| 1.0.0 | Base version: layered sidebar navigation (projects → boards → kanban), global search with click-through, app name + default columns settings, files, @mention push notifications via ntfy, user management. Deploy = paste dockge-compose.yml into Dockge, edit x-app-env, Deploy. |

## Stack

| Layer    | Tech |
|----------|------|
| Backend  | Python FastAPI + SQLAlchemy 2.0 (`backend/app.py` — single file) |
| Database | PostgreSQL 16 (`POSTGRES_DB=workspace`) |
| Frontend | Vanilla JS SPA (`frontend/app.js` + `index.html` + `styles.css`), nginx serves it |
| Push     | ntfy container for phone notifications (mention tagging via `@username`) |

## How to run locally (Windows, Docker Desktop)

```bash
docker compose up -d --build        # secrets come from .env (gitignored)
# app on http://localhost:9999
```

`.env` holds DB_PASSWORD / JWT_SECRET / CORS_ORIGINS / APP_PORT. `.env.example` is the template.
After code changes only: `docker compose up -d --build backend frontend`.

## Deploying to the server with Dockge (pulls prebuilt images)

Images are built automatically by GitHub Actions (`.github/workflows/docker-publish.yml`)
on every push to `main` and published to GHCR as
`ghcr.io/lotdog1984/solray-backend:<VERSION>` (+ `latest`, + commit sha). The version
comes from the repo's `VERSION` file — **bump it with every change**.

Deploy = paste `dockge-compose.yml` into a Dockge stack named `solray`, edit the
`x-app-env` block at the top (POSTGRES_PASSWORD, JWT_SECRET, CORS_ORIGINS, NTFY_BASE_URL)
and the frontend port, hit Deploy. No clone, no build, no .env on the server.
The backend builds its DATABASE_URL from POSTGRES_PASSWORD when DATABASE_URL is unset
(see top of `backend/app.py`) — that's why a single secret line covers db + backend.

Data lives in `/mnt/docker/apps/solray/data/{postgres,uploads,ntfy}`.

**Server update flow (learned the hard way):** editing the YAML + stop/start does NOT
change what runs — stopped containers just restart with the same old image, and
compose never re-checks the registry on its own. After bumping the image tags in
Dockge, run in the stack's terminal:

    docker compose pull                      # fetch the new images
    docker compose up -d --force-recreate    # recreate containers from current YAML
    docker compose images                    # verify tags are the new version

Then Ctrl+F5 in the browser once (old tab may hold stale JS). No stopping needed —
force-recreate swaps containers with a few seconds of downtime.

**Reverse proxy (HTTPS) gotchas:** the production site sits behind an NGINX HTTPS
reverse proxy. When "direct access shows the new version but HTTPS shows old":
(1) the proxy's `proxy_pass` may still target the OLD app's port — it must point at
the solray frontend port; if nginx itself runs in a container (Nginx Proxy Manager),
`127.0.0.1` does not reach the host — use the server's LAN IP instead; (2) a site
using `root` to serve copied static files never sees container updates — use
proxy_pass; (3) strip `proxy_cache` or add proxy_no_cache. Diagnose with
`curl -s http://127.0.0.1:<port>/version.txt` vs `curl -sk https://127.0.0.1/version.txt -H "Host: <domain>"`.
After switching the browser origin to HTTPS, add `https://<domain>` to the stack's
CORS_ORIGINS (comma-separated) and update NTFY_BASE_URL — otherwise login breaks.
Keep `client_max_body_size 200m` on the proxy for file uploads.

**Per-server customization is expected:** the ports, volume paths and the anchor name
in dockge-compose.yml are EXAMPLES. The production stack intentionally differs
(different free ports, uploads on slow HDD/NAS storage, DB placed for speed/durability
by the owner). Never "fix" a deployed stack back to the template values — only the
image version lines are meant to be bumped on updates. Secrets live only in the
deployed stack, never in the repo. JWT secrets should avoid spaces (whitespace is
preserved by YAML but easily mangled by copy/paste, silently invalidating logins).

**Pull access:** the GHCR packages inherit the repo's visibility. If the repo is
private, the server needs a docker login (PAT with read:packages) before deploying;
if public, pulls work anonymously.

The old deploy-key SSH clone flow (`solray-deploy-key`) is obsolete — files kept
locally only, gitignored, and can be deleted once the server is on the image flow.

## Architecture notes (things that surprised us before)

- **Backend is a single file** `backend/app.py` (~950 lines). `backend/main.py` is a leftover
  dev stub — the Dockerfile correctly runs `uvicorn app:app`, do not switch back to main.py.
- **First registered user becomes admin**; registration is then closed
  (`GET /api/auth/status` → `registration_open: false`, the login form hides it).
  New users are created by admin in Postavke → Korisnici.
- **Settings** live in a key/value `settings` table, served publicly by `GET /api/settings`:
  `app_name` (login page + sidebar brand + tab title) and `default_columns`
  (one per line; every NEW board is created with these columns).
- **Layered navigation happens in the sidebar** (blue): Projects → (click project) →
  Boards → (click board) → kanban. The white content area stays EMPTY on the first two
  layers except for the global search box + results. Back buttons: `← Projekti`.
- **Search**: `GET /api/search?q=` searches projects, boards, tasks (title + description
  — there is no separate comment model). Permission-filtered. Frontend renders results
  under the search box; clicking a project result opens its boards, a board/task result
  opens the kanban and expands the task (`openSearchResult`).
- **Project/board edit UI**: each sidebar row is `[name button][✎ button]`; ✎ toggles a
  `.edit-menu` (Preimenuj / Obriši). IMPORTANT: `.edit-menu[hidden] { display: none }`
  must stay in styles.css — the JS toggles the HTML `hidden` attribute and the
  `display: grid` rule otherwise overrides it (this bug already bit us once).
- **Permissions**: boards are visible to owner + board members
  (`ensure_board_access`, `board_members` table). Project management is owner/admin only.
- **nginx.conf** sets `Cache-Control: no-cache` on static files — keep it, browsers
  otherwise cache app.js/styles.css and users see stale UI after deploys.

## Testing habits that worked

- Rebuild + wait ~3s, then `curl http://localhost:9999/api/...` with a token.
- For API tests needing an account, create a temp admin directly via the backend container:
  `docker exec solray-backend-1 python -c "from passlib.context import CryptContext; ..."`
  then INSERT via `docker exec solray-db-1 psql -U workspace -d workspace` — note the
  users table columns are `password_hash` (not hashed_password) and `created_at` is NOT
  NULL — set `now()` explicitly. DELETE the temp user afterwards.
- Verify UI via the preview tools (preview_evaluate driving clicks); check
  `preview_logs` for console errors.
- NEVER test destructive calls (delete) against real data — use throwaway objects.
  (One board was accidentally deleted this way once; don't repeat it.)
- **2026-09-21 incident (do not repeat):** during v1.2.1 testing a real user
  account (`ruta`, id 9) was deleted — the temp-user cleanup guessed the id
  instead of looking it up first. Nothing else was lost (no boards/projects/
  tasks referenced that user), but the account and its password were. RULE:
  before ANY delete-by-id, SELECT the row and verify its identity; never
  guess ids; always clean up by username, not id.
- Users table column names: `password_hash`, `ntfy_topic`, `is_admin`.

## Git / GitHub

- Repo: https://github.com/LotDog1984/solray (branch `main`)
- Remote `origin` is configured; push with `git push -u origin main`.
- Secrets are NOT in the repo (`.env` gitignored; compose files use env vars).
- Old scratch compose files were deleted on purpose; `docker-compose.yml` = local,
  `dockge-compose.yml` = server.

## Current feature set (all verified working)

1. Auth: register (first-run only), login, JWT sessions, admin-managed users
2. Projects layer → Boards layer → Kanban (create/rename/delete at both levels)
3. Kanban: default columns from settings, tasks with title/description/assignee,
   drag & drop between columns, edit inline
4. Files: upload/download per board (`StoredFile`, uploads volume)
5. Notifications: in-app + ntfy push on `@mention` in task title/description
6. Settings: app name, default columns, ntfy topic, user management (admin)
7. Global search (projects/boards/tasks) with click-through navigation

## Known ideas / next steps

### Mobile Android app — the agreed plan (planned, NOT started)

Decisions made with the user (do not re-litigate):

- **Distribution & builds: GitHub Actions.** Add a workflow (sibling of `docker-publish.yml`)
  that on every `v*` tag builds a signed APK and attaches it to the GitHub Release
  (same tag → Docker images on GHCR + `solray-x.y.z.apk` on the Releases page).
  User never builds locally. Simple generated signing key stored as a GitHub secret.
- **Notifications: level 2.** The app itself subscribes to the user's ntfy topic via
  **WebSocket** (`wss://<instance-ntfy>/topic/ws`) — pushes appear inside the app while
  it's open, with live board refresh when a `task_changed` event arrives. Team is all
  Android except ONE iPhone → that device keeps the ntfy app as fallback (iOS forbids
  persistent background sockets); UnifiedPush/APNs only if ever needed later.
- **Server-address onboarding (no baked domains).** First run: single input for the
  team's URL (e.g. `https://tim-a.mediahost.stream`) → validate via public
  `GET /api/settings` (shows the instance's app_name as confirmation) → login → store
  base URL + JWT. Multiple instances can be stored; "switch team" = switch pair.
  **Contract rule: `GET /api/settings` is frozen and may only gain optional fields.**
- **Multi-instance ready:** the backend is already env-driven (no baked domains);
  deploying team B = same stack yaml with a new name, different port, new nginx block.
  Prefer per-instance ntfy (each stack brings its own) — no topic collisions.
- **API stability rule (keep forever): additive only — never rename/reuse fields,
  new fields must be optional.** 401 → re-login screen; tolerate unknown JSON fields.
- Suggested client: Flutter (or RN) from the same repo (`mobile/` folder), API docs
  live at `/docs` on any instance (FastAPI auto-generated).

### Smaller ideas

- Ctrl+K shortcut for search; highlight matched text in results
- Task comments (separate model) + include in search
- Board archiving instead of hard delete
- Server deployment: NOT done yet — the Dockge stack is ready (`dockge-compose.yml`,
  pull-based via GHCR); user still needs to paste it into Dockge on the server, edit
  the x-app-env secrets and hit Deploy. First push after the workflow lands triggers
  the image build.
