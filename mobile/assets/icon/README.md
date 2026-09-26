# Android launcher icons — how to replace the app icon

The icon is generated from **one source image**; the `mipmap-*` folders are
generated artifacts and are never edited by hand.

## How to ship a new icon (drop-in, no tooling needed)

1. Save your artwork as **`mobile/assets/icon/app_icon.png`** — a square PNG,
   **1024×1024 px** (larger is fine, it gets downscaled).
2. (Optional, for the crispest Android 8+ adaptive icon) also save a version
   with the logo inside the middle ~66% of the canvas as
   **`mobile/assets/icon/app_icon_foreground.png`** — the launcher masks the
   edges into a circle/squircle, so keep important detail away from the rim.
   If you skip this file, the plain `app_icon.png` is used for the foreground
   layer too.
3. Commit both files and push a `v*` tag (or re-run the "Build Android APK"
   workflow) — CI regenerates every launcher icon automatically before
   building, so the released APK carries the new icon.

## How it works (already wired in this repo)

- `dev_dependencies` in `mobile/pubspec.yaml` includes `flutter_launcher_icons`.
- `mobile/flutter_launcher_icons.yaml` configures the generator:
  - **adaptive icon** (Android 8+): your artwork as the foreground layer over
    the app's dark-blue sidebar color `#0F172A`
  - **legacy square icons** for older devices (`ic_launcher` in every density)
- `.github/workflows/mobile-apk.yml` runs the generator after writing the
  Firebase config and before `flutter pub get`/build — *only when
  `app_icon.png` exists*, so a missing file never breaks a build.
- Regenerate locally (optional): from `mobile/`, run
  `dart run flutter_launcher_icons`.

## Old icon files

The previous hand-made mipmaps were removed from git; the generated set
replaces them on every build. Do not re-add mipmap PNGs — they would be
overwritten by the generator anyway.
