# SolRay mobile client (Android)

Flutter app that talks to **any SolRay instance**. The server address is entered
on first run (onboarding) — nothing is baked into the binary.

## How it works

- **Onboarding**: enter the instance URL (e.g. `https://app.mediahost.stream`) →
  validated against the public `GET /api/settings` (shows the instance's app name)
- **Login**: same accounts as the web app (JWT stored on the device)
- **Projekti tab**: projects → boards → kanban columns with tasks, checklist
  ticks (green), all-checked auto-completion, orange tint on tasks that mention you
- **Obavijesti tab**: in-app notification list with unread badge; unread count
  arrives live via the instance's ntfy WebSocket (`ntfy_base_url` from
  `/api/settings`, topic from the user's account) and a 30 s poll as backup

## Builds

You never build locally — **GitHub Actions** does it: every `v*` tag produces a
signed APK attached to the GitHub Release (`.github/workflows/mobile-apk.yml`).
The signing key lives in repo secrets; the workflow generates a throwaway
debug-grade key for test builds if secrets are absent.

One-time setup for real release signing (repo owner):

```bash
keytool -genkey -v -keystore solray-release.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias solray
# then base64-encode and add repo secrets:
#   ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD
```

## Development (optional — CI covers releases)

```bash
cd mobile
flutter create --platforms=android .   # (re)generate any missing android files
flutter pub get
flutter analyze
flutter build apk --release
```
