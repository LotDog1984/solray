# SolRay — Project Handoff

Kanban app (projects → boards → tasks) built for Branko. All UI text is in **Croatian**.
App name is configurable in-app (default "Private Workspace", currently set to **"SolRay"**).

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
`ghcr.io/lotdog1984/solray-backend:latest` / `ghcr.io/lotdog1984/solray-frontend:latest`.

Deploy = paste `dockge-compose.yml` into a Dockge stack named `solray`, edit the
`x-app-env` block at the top (POSTGRES_PASSWORD, JWT_SECRET, CORS_ORIGINS, NTFY_BASE_URL)
and the frontend port, hit Deploy. No clone, no build, no .env on the server.
The backend builds its DATABASE_URL from POSTGRES_PASSWORD when DATABASE_URL is unset
(see top of `backend/app.py`) — that's why a single secret line covers db + backend.

Data lives in `/mnt/docker/apps/solray/data/{postgres,uploads,ntfy}`.
Update after pushing new code = hit Update/Redeploy in Dockge.

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
