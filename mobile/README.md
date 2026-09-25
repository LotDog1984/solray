# SolRay mobile client (Android)

Flutter app that talks to **any SolRay instance**. The server address is entered
on first run (onboarding) — nothing is baked into the binary.

## How it works

- **Onboarding**: enter the instance URL (e.g. `https://solray.mediahost.stream`) →
  validated against the public `GET /api/settings` (shows the instance's app name)
- **Login**: same accounts as the web app (JWT stored on the device)
- **Projekti tab**: projects → boards → kanban columns with tasks, checklist
  ticks (green), all-checked auto-completion, orange tint on tasks that mention you
- **Nabava tab** (v1.7.0+4): global supplies To-Do aggregated from ALL boards —
  every Stavka shows the 📁 Projekt → Ploča it came from (tap to open that
  board); tick = bought, trash = delete. Each board's kanban also ends with a
  ✅ To-Do panel for adding that board's missing supplies. Tab label and panel
  title follow the admin setting `default_todo_list` (web: Postavke).
- **Obavijesti tab**: in-app notification list with unread badge; unread count
  arrives live via the instance's ntfy WebSocket (`ntfy_base_url` from
  `/api/settings`, topic from the user's account) and a 30 s poll as backup

## Builds

You never build locally — **GitHub Actions** does it: every `v*` tag produces a
signed APK attached to the GitHub Release (`.github/workflows/mobile-apk.yml`).

Signing (since 1.9.1): the release keystore `android/app/solray-release.jks`
and `android/key.properties` are **committed to the repo** so every build —
local and CI — signs with the same stable key. Android refuses to install an
update over an app signed with a different key, which is why pre-1.9.1
releases (random per-build CI key) could not update in place. CI asserts the
APK's SHA-256 certificate fingerprint and fails the release if it ever drifts.
⚠️ Never lose or regenerate this keystore: users would have to uninstall and
reinstall. Rotate + move to GitHub Secrets before any Play Store release.

## Development (optional — CI covers releases)

```bash
cd mobile
flutter create --platforms=android .   # (re)generate any missing android files
flutter pub get
flutter analyze
flutter build apk --release
```
