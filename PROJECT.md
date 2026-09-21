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

- Ctrl+K shortcut for search; highlight matched text in results
- Task comments (separate model) + include in search
- Board archiving instead of hard delete
- Server deployment: NOT done yet — the Dockge stack is ready (`dockge-compose.yml`,
  pull-based via GHCR); user still needs to paste it into Dockge on the server, edit
  the x-app-env secrets and hit Deploy. First push after the workflow lands triggers
  the image build.
