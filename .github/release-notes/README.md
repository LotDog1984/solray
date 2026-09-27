# GitHub release notes archive

This directory keeps the detailed notes used by `.github/workflows/mobile-apk.yml` and serves as the durable source for published GitHub Release descriptions. Keep each version file when adding newer releases; the workflow requires a matching `v<VERSION>.md` for tagged builds.

## Published releases

Every currently published GitHub release has a matching detailed notes file:

- `v1.13.1.md`, `v1.13.0.md`
- `v1.12.6.md`, `v1.12.5.md`, `v1.12.4.md`, `v1.12.2.md`, `v1.12.1.md`, `v1.12.0.md`
- `v1.10.2.md`, `v1.10.1.md`, `v1.10.0.md`
- `v1.9.3.md`, `v1.9.2.md`, `v1.9.1.md`, `v1.9.0.md`
- `v1.8.0.md`
- `v1.6.3.md`, `v1.6.2.md`, `v1.6.1.md`, `v1.6.0.md`
- `v1.5.0.md`

The v1.11.0 camera/thumbnail changes are included in v1.12.0 because there is no separate v1.11.0 GitHub Release. The v1.7.0 Nabava/mobile work is included in v1.8.0, and the v1.12.3 CI/FCM build fixes are included in v1.12.4. Those version numbers do not have separate published release entries. Earlier project history before v1.5.0 predates GitHub Releases and remains in `PROJECT.md` under **Version log**.

The published release descriptions retain their original GitHub-generated **Full Changelog** comparison notes and APK assets; these detailed summaries are appended after the existing text.
