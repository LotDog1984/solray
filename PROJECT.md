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
| 1.12.2 | **Foreground push silence fixed + one-tap push diagnostic (mobile v1.12.2+16, backend):** after 1.12.1 the pipeline worked only when the app was killed — with the app OPEN no banner ever appeared. Root cause introduced in 1.12.1: `listenForeground` skipped displaying messages carrying a notification block ("the OS integration shows it"), but FCM **data** messages are never auto-displayed by the OS integration regardless of the notification block — foreground delivery lands in `onMessage` and only the app can show something. The foreground listener now ALWAYS posts the local notification (background/terminated display stays with the OS integration; background handler remains as fallback). New diagnostic: `POST /api/me/push/test` reports exactly where the chain stands for the calling account (FCM not configured / this phone not registered / key invalid / sent / Google's verbatim error, e.g. mismatched sender) and actually sends a test message to the registered device; Postavke → Obavijesti gains a "Testiraj Google push" button (re-registers first, then reports ✅/⚠️/❌ in Croatian). Deployment fact discovered while diagnosing: from CI logs the v1.12.1 release **was built WITH the Firebase config** (`GOOGLE_SERVICES_JSON` secret is set), so if Testiraj still reports "nije registriran" after installing 1.12.2+16 and opening the app once, the backend compose env/mount is the thing to check. Verified: `py_compile` + AST route check (`/api/me/push/test` present), `flutter analyze` clean, 17/17 tests in containerized Flutter 3.24.3. |
| 1.12.1 | **Push notifications fixed — they never actually reached Google (backend v1.12.1 / mobile v1.12.1+15):** 1.12.0 shipped the whole FCM pipeline **except the two endpoints that feed it** — `POST /api/me/push-token` and `POST /api/me/push-token/remove` did not exist in `backend/app.py`, so every device registration silently 404'd, `push_tokens` stayed empty, and `send_fcm()` had nothing to send to (symptom: in-app Obavijesti always filled, lock-screen notifications arriving "only when something wakes the phone"). Both endpoints added (`/api/me/push-token` upserts the token — a token re-registered under another account moves to it, token echoed so the app detects rotation; `/remove` deletes the caller's own row). Second fix: `send_fcm()` sent **data-only** FCM messages, which Android queues while the app is killed and often delivers only when a later message or app start wakes the process — exactly the observed "one push, then never again / delayed by minutes"; messages now carry a **notification block** (title/body + `channel_id: solray`, HIGH priority), so Google's OS integration displays the banner immediately and wakes the process itself, data fields keep the tap deep-link, and the foreground listener skips local display when a notification block is present (no double banners while the app is open; the background handler remains as a data-only fallback). Mobile hardening: token registration now retries 3× with re-read token (boot raced the phone waking its network — one silent failure left the device unregistered until the next resume). Verified: backend `py_compile` + AST route check (55 endpoints, both push routes present, notification block in `send_fcm`), `flutter analyze` clean, 17/17 tests in containerized Flutter 3.24.3. Deploy note: the FCM fix needs BOTH sides — pull the new backend image **and** install the v1.12.1 APK, then let the app run once in the foreground so the token registers; check with `SELECT count(*) FROM push_tokens;` |
| 1.12.0 | **Real push notifications (FCM) — mobile v1.12.0+14:** tagged users now get a **true Google push notification** on their phone even when the SolRay app is closed/killed (the old ntfy WebSocket only worked while the app was alive, which is why the ntfy app showed pushes but SolRay didn't). Backend: `push_tokens` table + `POST /api/me/push-token` / `POST /api/me/push-token/remove` (one device = one row; token re-registered by another account moves to it), `send_fcm()` pushes a **data-only** FCM HTTP v1 message (google-auth service-account OAuth, token cached + auto-refreshed; stale/unregistered tokens pruned; every failure swallowed so notifications can never break the triggering API call) fired from `notify_task_users` alongside the existing ntfy/in-app notification. Opt-in per instance: set `FCM_PROJECT_ID` + `GOOGLE_APPLICATION_CREDENTIALS` (mounted Firebase service-account JSON) — without them everything behaves exactly as before. CI release APKs include FCM when the `GOOGLE_SERVICES_JSON` GitHub secret is set (the workflow writes it to `mobile/android/app/google-services.json` before building). Mobile: firebase_core/firebase_messaging; background isolate handler converts data messages into local system notifications (same channel/payload convention `boardId:boardName` → tap opens the board); token registered at login and re-registered on every app resume (handles rotation); duplicate foreground listeners guarded; token removed on logout/change-server. Android: `com.google.gms.google-services` Gradle plugin applied **only when `google-services.json` exists** — builds without a Firebase config (CI before the secret is added, fresh clones) keep working. iOS-ready: the same token rows/pipeline drive APNs — an Apple Developer account only adds the `ios/` folder + APNs key in Firebase (no backend changes). Setup steps in PROJECT.md § Firebase Cloud Messaging setup. Verified: backend `py_compile`, `flutter analyze` clean, 17/17 tests in containerized Flutter 3.24.3. |
| 1.11.0 | **Camera photos + working thumbnails (mobile v1.11.0+13):** the Datoteke tab gains a **Slikaj** button next to Datoteka — take a photo with the camera, get a naming dialog pre-filled with today's date ("Slika 25.9.2026"), edit or keep it, photo uploads as JPEG (auto-downscaled to max 1600px, best-effort) with proper `image/jpeg` content type, and cancel anywhere throws the shot away. The name makes photos findable in the list instead of opening pictures one by one. **Thumbnails now actually work:** two real bugs fixed — (1) backend gated thumbnail generation on the browser-supplied Content-Type header, so any upload sent as `application/octet-stream` (everything from mobile) silently got NO thumbnail: the stored bytes are now sniffed for JPEG/PNG/GIF/BMP magic and mislabeled camera JPEGs are stored as `image/jpeg` so they render as pictures; duplicate `is_image` definition removed. (2) the mobile app rendered **full-size originals** in list/grid rows (huge downloads on cellular); it now decodes the server's 420px thumbnails (`cacheWidth` for list rows, placeholder background while loading in grid). New deps: image_picker, flutter_image_compress, image, http_parser. Verified in containerized Flutter 3.24.3: analyze clean, 17/17 tests (new files_screen_test.dart exercises the real camera flow via an injected picker — naming dialog, filename, content-type, cancel paths — and asserts thumbnails point at the token-authenticated `/api/files/{id}/thumb` endpoint). |
| 1.10.2 | **Mobile Projects tab never goes stale (v1.10.2+12):** fixed "empty on cold start / stale after a while — must pull to refresh" on the Projekti tab. Four root causes, all fixed: (1) nothing subscribed to the SyncBus's 20 s fallback tick — it fires only to `'tick'` listeners, so with the sync socket asleep (phone sleep, network switch) nothing reloaded; the tick now refreshes the active Projects/Nabava tab. (2) `SyncBus.poke()` (force immediate reconnect, "e.g. app resumed") was never called — the app now pokes the bus on every resume, skipping the up-to-5-min reconnect backoff after phone sleep. (3) The first projects fetch raced the phone waking its network and failed silently, leaving an empty list until a manual pull — boot now retries (up to 3 attempts with short backoff) and every automatic refresh is silent (no error snackbars from background refreshes). (4) Opening the Projects tab never reloaded — the tab now fetches fresh data on every switch, and the app refreshes on `AppLifecycleState.resumed` via `WidgetsBindingObserver`. Live WebSocket sync (1.8.0) still handles instant updates while the socket is healthy; these fixes cover every path it misses. Verified in containerized Flutter 3.24.3: analyze clean, 9/9 tests. |
| 1.10.1 | **Cleaner supplier export (web + mobile v1.10.1+11):** the ✉️ "Pošalji e-mailom" / share export now contains only the item text the user typed — one line per Stavka (`- lada 400x150 bijela`), with the `(Projekt — Ploča)` origin suffix removed from the order text (origin stays visible in the list UI, just not in the e-mail). Same open-only rule as 1.10.0. Verified in the browser (mailto body + clipboard captured) and in containerized Flutter 3.24.3 (analyze clean, 9/9 tests). |
| 1.10.0 | **Supplier order export + Nabava housekeeping (web + mobile v1.10.0+10):** ✉️ "Pošalji e-mailom" builds a plain-text order from the OPEN (unchecked) Stavke only — so re-sending an order never repeats bought items — and opens the user's own mail app via `mailto:` with the list prefilled in the body (subject "Nabava — dd.mm.yyyy."); the same text is copied to the clipboard as a fallback ("✓ Kopirano — otvaram poštu…" on the button, paste-prompt if clipboard is blocked). Mobile uses the native share sheet (pick Gmail/Outlook, body prefilled). "Izbriši Preuzete Stvari" (bottom of the list, both UIs, disabled when nothing is checked, confirm dialog) deletes every checked Stavka across ALL lists — new `DELETE /api/nabava/checked` — and fires board + nabava sync events so open boards refresh. Checked items now sit right below the unchecked ones with the most recently checked first (new `todo_entries.checked_at` stamp + idempotent migration; ordering `is_done, checked_at DESC NULLS FIRST, created_at`). Bug fixed en route: renaming a done Stavka silently unticked it (PATCH reset `is_done`) — title and is_done are now independently optional on both PATCH routes, so tick-only and rename-only requests both work. Verified via API + browser (mailto body and clipboard captured, ordering after ticks, rename-preserves-done on both routes, clear deleted exactly the done ones) and in containerized Flutter 3.24.3 (analyze clean, 9/9 tests incl. export-format tests). APK via CI on the v1.10.0 tag. |
| 1.9.3 | **Search finds Nabava entries (web + mobile v1.9.3+9):** the search bar now also matches Stavke from every board's To-Do list plus the manually added ones — new `nabava` result type in `/api/search` (case-insensitive match on the title, origin shown in the detail as "Projekt → Ploča" or "Ručno dodano", "· nabavljeno ✔" suffix when ticked, capped at 50 like tasks). Both UIs render a green NABAVA/🛒 chip; tapping a board-origin hit opens that board, a manual hit opens the global Nabava view (mobile jumps straight to the Nabava tab). Bonus fix found while verifying: clicking ANY search result kept the results on screen instead of rendering the destination (search state was never cleared on navigation) — every result click now lands on its target immediately. Search placeholders updated ("Traži projekte, ploče, zadatke, nabavu…"). Verified via API + browser for both hit types and in containerized Flutter 3.24.3 (analyze clean, 7/7 tests). APK via CI on the v1.9.3 tag. |
| 1.9.2 | **Every Nabava line is editable after creation (web + mobile v1.9.2+8):** typos and wrong quantities in a Stavka — whether it lives on a board's ✅ To-Do list or was added manually in the global 🛒 view — can now be fixed in place. Web: the Stavka title is a button in both views (click → edit prompt, the same convention as project/board rename; hover underlines it), Esc/cancel leaves the text untouched. Mobile: an edit pencil on every Nabava row opens the "Uredi stavku" dialog (tapping the row works too), and in the board's To-Do panel tapping the title edits it — manual entries PATCH `/api/nabava/items/{id}`, board entries PATCH the board route. Backend unchanged (the 1.7.0/1.9.0 PATCH endpoints already accepted title edits); `nabava`/`board` sync events fire on edit so web + mobile reload live. Verified in the browser (all three edit paths persisted through their correct endpoints) and in containerized Flutter 3.24.3 (analyze clean, 7/7 tests incl. new rename assertions). APK via CI on the v1.9.2 tag. |
| 1.9.1 | **In-app updater fixed — stable signing key (mobile v1.9.1+7):** updates have been failing since the first CI-built release with Android's "app has the same signature / signature doesn't match" error, forcing an uninstall before every install. Root cause: CI had no signing secrets, so its fallback generated a **fresh random keystore for every tag** — each release was signed with a different key, and Android (by design) refuses to install a differently-signed APK over an installed one. Fixed en route: the secrets path could never have worked either (`key.properties` pointed at `app/app/solray-release.jks`, which doesn't resolve from the app module → silent fallback to debug signing = yet another random key per runner), and `versionCode` was hardcoded to 1 on every build (now derived from the build date, strictly monotonic). The fix: the release keystore `mobile/android/app/solray-release.jks` (the same key that signed the locally built 1.5.0–1.6.1) + `key.properties` are now **committed** and used by local and CI builds alike; CI verifies the keystore loads and **asserts the built APK's SHA-256 cert fingerprint**, failing the release instead of shipping one that phones would refuse to update. Postavke → Ažuriranja now installs straight over the installed app. ⚠️ Never lose or regenerate the keystore; rotate + move to GitHub Secrets before any Play Store release. |
| 1.9.0 | **Manual items directly in the global Nabava list (web + mobile):** the aggregated 🛒 Nabava view (which still collects Stavke from every board's To-Do list) now also has its own "Dodaj" form — add items without opening any board. A single global To-Do list (the 1.7.0 schema's `todo_lists.board_id` became nullable, NULL = global; idempotent startup migration keeps the one-time 1.7.0 backfill working) holds manual entries, so they sync to the same rows the board lists use. New API: `POST/PATCH/DELETE /api/nabava/items` (manual entries only — global routes deliberately 404 on board entries so the two stay isolated); `GET /api/nabava` rows now carry `board_id: null` + `board_name: ""` for manual items. Web: Nabava view gains the add form (Enter or "Dodaj"), manual rows show a muted "✍️ Ručno dodano" marker instead of the tappable 📁 origin chip, tick/delete route to the right endpoint per row type. Mobile: "Dodaj stavku ručno" button in NabavaTab opens the same add dialog as the board panel, same ✍️ marker (new widget test for the manual card). Live sync untouched — every mutation fires the `nabava` event so web+mobile reload instantly. Verified end-to-end via API + browser (add/tick/delete as manual and board rows, isolation 404s, 401 unauth) and in containerized Flutter 3.24.3 (analyze clean, 7/7 tests). APK ships via CI on the v1.9.0 tag. |
| 1.8.0 | **Real-time sync everywhere (web stack + mobile v1.8.0+5):** the backend broadcasts lightweight "something changed" events over a new authenticated WebSocket `/api/ws?token=JWT` (in-process hub; events carry no data — clients re-fetch via REST, so permissions are untouched). 26 mutating endpoints notify: projects, board (task create/edit/delete/complete/checklist/move, columns, board To-Do), nabava, files. nginx got Upgrade/Connection headers + 1h read timeout for the proxy. Mobile: `SyncBus` (per-server singleton, one WS) with scoped listeners — Projects tab refreshes on projects events, open BoardScreen silently reloads on its board events (no spinner), NabavaTab refetches on nabava, FilesScreen on files; dropped sockets reconnect 5s→5min and while offline a 20s tick acts as slow-poll fallback, so screens never go stale without manual refresh. Verified end-to-end: WS event received (board+nabava) after a REST mutation inside the backend container, WS handshake works through the nginx proxy, analyze clean + 6/6 tests on Flutter 3.24.3. Mobile APK ships via CI on the v1.8.0 tag. |
| 1.7.0 (mobile) | **Mobile Nabava parity (v1.7.0+4):** the Android app gains everything the web Nabava feature offers — a 5th bottom tab named after `settings.default_todo_list` (🛒 shopping icon) aggregating Stavke from ALL boards with the 📁 Projekt → Ploča origin chip on every row (tap to open the board, tick = bought, delete), the ✅ To-Do panel as the last column of every board (add via dialog, tick, delete), and the admin settings field for the list name alongside app name/columns. Verified in containerized Flutter 3.24.3 (the CI-pinned version): `flutter analyze` clean, all 6 tests pass (new `nabava_test.dart` exercises the real entry card). APK is built by CI on the next `v1.7.0` tag as usual. |
| 1.7.0 | **Nabava — automatic supplies To-Do list:** every board now gets a supplies To-Do list created together with its default columns; the admin names it in Postavke → "Naziv To-Do popisa za nabavu" (default **Nabava**, renames it on all boards + the global view at once). Stavke added on any board are aggregated in the new **Nabava** button (under Obavijesti) — a one-stop shopping list across ALL projects, where every Stavka carries the project + board it came from (click the origin to open that board). Tick/del/delete synced both ways (same DB rows). New backend: `todo_lists`/`todo_entries` tables (backfilled for existing boards), `GET /api/nabava`, `POST/PATCH/DELETE /api/boards/{id}/todo[/{entry_id}]`, `GET /api/boards/{id}` returns `todo_list`, `default_todo_list` added to settings API (additive). |
| 1.6.3 | **In-app updater (mobile):** Postavke gains an "Ažuriranja" section — shows the installed version, checks GitHub Releases (the channel CI publishes APKs to), and when a newer version exists offers "Preuzmi i instaliraj" with a live download-progress bar; the APK is handed to Android's package installer (REQUEST_INSTALL_PACKAGES declared; Android asks once to allow installs from the app). Version comparison is semver-style with unit tests; download is streamed with progress and size sanity-checked before install. New deps: package_info_plus. Verified: analyze clean, tests pass (incl. updater tests), release APK built (53.0MB).
| 1.6.2 | **Mobile notifications actually arrive (root-cause fix):** the production backend exposed no `ntfy_base_url` because the compose files set `NTFY_BASE_URL` while the backend only read `NTFY_PUBLIC_URL` — mobile clients silently got no WebSocket. Backend now accepts either var (NTFY_PUBLIC_URL preferred, NTFY_BASE_URL fallback) without breaking existing stacks. Mobile: ntfy envelope events filtered (only `message`/bare messages become system notifications — open/keepalive ignored), socket auto-reconnect with exponential backoff (5s→5min) on drop, and a "Provjeri vezu" diagnostic in Postavke that connects to the instance's ntfy and reports exactly what's wrong (missing server URL → admin hint, missing topic, or proxy blocking WebSockets). Verified: analyze clean, tests pass, release APK built (53.0MB), local stack rebuilt on 1.6.2.
| 1.6.1 | **Real device notifications (the Android toggle now works):** the app declares `POST_NOTIFICATIONS` + `VIBRATE`, requests the Android 13+ runtime permission shortly after login (once), posts actual system notifications when the ntfy WebSocket delivers a push (title + message from the envelope), and tapping a system notification opens the notification's board (payload `boardId:boardName`; without payload → Obavijesti tab). Postavke gained an "Obavijesti na uređaju" section: master switch (stored on device, cancels shown notifications when off), permission detection, and an "Otvori sistemske postavke" deep link when permission was denied. Gradle: enabled core library desugaring + `desugar_jdk_libs` (required by flutter_local_notifications). New deps: flutter_local_notifications 17.x, app_settings. Verified: analyze clean, tests pass, release APK built locally (52.9MB).
| 1.6.0 | **Mobile app full feature parity:** the Android app now does everything the web app does — **Projects**: create/rename/delete; **Boards**: create/rename/delete/move between projects (per-project layer); **Kanban**: create tasks (with checklist + assignee + column), edit, delete, move between columns, tick checklist items (green rows, auto-complete when all ticked), complete/reopen simple tasks, add/rename/delete columns (backend addition: `PATCH/DELETE /api/columns/{id}` — additive); **Search** tab (`GET /api/search`, tap result → board); **Datoteke** tab: per-project file picker upload, image thumbnails, list/grid toggle, open/share (new deps: file_picker, open_filex, path_provider, share_plus); **Postavke**: logout/change server, ntfy topic + test push, admin: app name, default columns, user create/delete. Backend rebuilt and all CRUD verified end-to-end via API (temp user, cleaned up); local APK `dist/solray-1.6.0.apk` (52MB) built with analyze clean + tests passing.
| 1.5.0 | **Mobile Android app (v1) + ntfy public URL setting:** new Flutter app in `mobile/` — server-address onboarding (URL validated via public `GET /api/settings`, nothing baked in), login with the same accounts, projects → boards → kanban with checklist ticks and completion, Obavijesti tab with unread badge fed by the instance's ntfy WebSocket + 30s poll. Backend: `GET /api/settings` now also returns `ntfy_base_url` (env `NTFY_PUBLIC_URL`, empty by default — set it to the public https ntfy domain so the app can subscribe; additive/frozen contract). CI: `.github/workflows/mobile-apk.yml` builds a signed APK on every `v*` tag and attaches it to the GitHub Release (secrets optional — a build key is generated when absent; add `ANDROID_KEYSTORE_BASE64/PASSWORD/KEY_ALIAS/KEY_PASSWORD` for a stable release key). Verified locally: `flutter analyze` clean, release APK built (50MB). First APK: `dist/solray-1.5.0.apk` (not committed) / release asset on GitHub.
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

### Mobile Android app — status: v1.5.0 shipped, full parity in 1.6.0

Shipped: onboarding (server URL → validated via public `/api/settings`), login, layered projects → boards → kanban with full CRUD (projects, boards, columns, tasks, checklists), search, per-project files (upload/thumbnails/list-grid/open-share), notifications tab with badge (ntfy WebSocket + poll), settings (account/ntfy/admin users/app name/default columns). Nothing baked in — every instance address is user-entered; API changes stay additive (frozen contract).

Build: `.github/workflows/mobile-apk.yml` — tag `vX.Y.Z` → signed APK on the GitHub Release (`solray-X.Y.Z.apk`). Flutter pinned to 3.24.3 in CI (matches local verification). Signing (since 1.9.1): the release keystore `mobile/android/app/solray-release.jks` + `mobile/android/key.properties` are **committed** so every build signs with the same stable key (in-app updates must match the installed app's signature); CI asserts the APK's SHA-256 cert fingerprint and fails the release if it drifts. Rotate + move to GitHub Secrets before any Play Store release.

Original plan (kept for reference):

Decisions made with the user (do not re-litigate):

- **Distribution & builds: GitHub Actions.** Add a workflow (sibling of `docker-publish.yml`)
  that on every `v*` tag builds a signed APK and attaches it to the GitHub Release
  (same tag → Docker images on GHCR + `solray-x.y.z.apk` on the Releases page).
  User never builds locally. Simple generated signing key stored as a GitHub secret.
- **Notifications: level 4 (1.12.0) — FCM push.** Real Google push that arrives even
  when the app is killed: the backend sends data-only FCM messages to registered
  device tokens (`push_tokens` table), the app turns them into system notifications
  and deep-links to the board on tap. The older ntfy WebSocket layer (in-app while
  open + slow-poll) remains as automatic fallback and still drives live board
  refresh. iOS rides the same pipeline later via APNs (see the setup section).
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

### Firebase Cloud Messaging setup (one-time, enables 1.12.0 push)

The backend and app are ready; push activates as soon as these steps are done.
Everything below is free and does not require an Apple account.

1. **Firebase project** — go to console.firebase.google.com → "Add project"
   (name it e.g. `solray`; Google Analytics optional/off).
2. **Android app in Firebase** — Project settings → your apps → Android icon:
   package name **exactly** `hr.mediahost.solray` (from `mobile/android/app/build.gradle`).
   Download `google-services.json`.
3. **App builds** — save the file as `mobile/android/app/google-services.json`
   (it is gitignored — never commit it). The Gradle plugin activates
   automatically when the file exists. Locally: `flutter build apk --release`.
   For **CI APKs**: add the file's contents as the GitHub secret
   `GOOGLE_SERVICES_JSON` and extend `.github/workflows/mobile-apk.yml` to write
   it to `mobile/android/app/google-services.json` before building.
4. **Service account for the backend** — Firebase console → Project settings →
   Service accounts → "Generate new private key" → save as
   `fcm-service-account.json`.
5. **Backend env** (local: `.env` / server: the `x-app-env` block in Dockge or
   `.env` for docker-compose):
   ```
   FCM_PROJECT_ID=<the firebase project id, shown in Project settings>
   GOOGLE_APPLICATION_CREDENTIALS=/secrets/fcm.json
   ```
   and mount the JSON (uncomment the prepared volume lines in
   `docker-compose.yml` / `dockge-compose.yml`). Then recreate the backend.
6. **Verify** — log into the app on a phone (accept the notification
   permission), tag a user in a task → the tagged phone gets a system
   notification even with the app closed; tapping it opens the board.
   If nothing arrives: check backend logs for FCM errors, confirm the token
   reached the server (`SELECT count(*) FROM push_tokens;`), and that Firebase
   shows the Android app with the exact package name.

**iOS later:** buy the Apple Developer account, add an iOS app in Firebase
(bundle id from the future `ios/` folder), upload the APNs key in Firebase
console, register the token with `platform: 'ios'` — the backend `push_tokens`
rows and `send_fcm` pipeline already support it; no backend changes needed.

### Smaller ideas

- Ctrl+K shortcut for search; highlight matched text in results
- Task comments (separate model) + include in search
- Board archiving instead of hard delete
- Server deployment: NOT done yet — the Dockge stack is ready (`dockge-compose.yml`,
  pull-based via GHCR); user still needs to paste it into Dockge on the server, edit
  the x-app-env secrets and hit Deploy. First push after the workflow lands triggers
  the image build.
