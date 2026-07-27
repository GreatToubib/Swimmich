# Swimmich — project & release recap

Context carry-over for new Claude sessions. For day-to-day rules see `CLAUDE.md`.

## What Swimmich is
A personal **fork of Immich** (self-hosted photo manager), pinned to tag
**v2.7.5**. It adds a Tinder-style **photo triage / "sort deck"** to the mobile
app. Solo dev. Workflow: branch off `swimmich-test` → build to phone →
ready-to-merge PRs.

- GitHub: `GreatToubib/Swimmich` (gh needs `--repo GreatToubib/Swimmich`).
- Integration branch: **`swimmich-test`** (branch features from here, not `main`).
- Feature branches: `feat/swimmich/sN-...`.

## The sort feature (built & merged into `swimmich-test`)
- A bootstrap service creates 6 system albums on first login: `_New`,
  `_Review Later`, `⭐`, `⭐⭐`, `⭐⭐⭐`, and backfills existing assets into `_New`.
- Sort deck (card swipe): **Delete** (trash), **Review Later**, **Sorted**.
  "Sorted" can add the asset to user "quick-pick" albums + assign an **exclusive**
  star rating (3★ ⇒ ⭐⭐⭐ only, not cumulative).
- Source picker bottom sheet chooses which albums feed the deck (defaults:
  New + Review Later). Loads each album separately and unions/dedupes — because
  Immich's metadata search **ANDs** `albumIds` (intersection), not OR.
- Quick-pick chips: 4 pinned + 4 recent (MRU, 30-day prune). Deleted albums are
  pruned on Sort-tab open.
- Edit mode: re-sorting an already-sorted card pre-selects its current albums +
  star, and reconciles (removes de-selected). Album changes are mirrored into the
  local **Drift** DB so the Albums view updates without a full re-sync.
- Key files: `mobile/lib/services/sort_action.service.dart`,
  `mobile/lib/pages/sort/sort.page.dart`,
  `mobile/lib/pages/sort/sort_source_sheet.dart`,
  `mobile/lib/providers/{sort_queue,sort_source_filter,quick_pick,system_album_ids}.provider.dart`.

## Release status (Android only, Firebase App Distribution)
- ✅ **Rebrand merged** (PR #9): `applicationId app.swimmich` (Kotlin namespace
  left as `app.alextran.immich`), launcher label "Swimmich"/"Swimmich-Debug".
  Coexists with a real Immich install.
- ✅ **Signing keystore** at `mobile/android/key.jks` (gitignored), alias
  `swimmich`. **Must stay backed up — lost key = no in-place updates ever.**
- ✅ **Signed release APK** built (172 MB, version `2.7.5+3047`), verified
  `CN=Swimmich` (V2 signature). At `mobile/build/app/outputs/flutter-apk/app-release.apk`.
- 🔄 **Firebase App Distribution** — project `swimmich-afe59` (free Spark plan);
  Android app registered as `app.swimmich`. **In progress:** add the `family`
  tester group + upload the APK via the console (drag-and-drop; no Node/npm
  installed, so no Firebase CLI yet).
- ⏳ **Server admin (pending):** create an Immich account per family member on the
  existing public HTTPS server.

## On-disk relocation (2026-05)
Moved from `C:\Users\basil\Swimmich-flutter\…` to:
- Repo: `C:\Users\basil\dev\Swimmich Stack\Swimmich app`
- Flutter SDK: `C:\Users\basil\dev\dev tools\flutter`
PATH and `mobile/android/local.properties` were updated to the new SDK path.

## Next steps
1. Finish Firebase upload + distribute to the `family` group.
2. Verify install on phone (`adb install -r app-release.apk` or via the App
   Tester app); confirm "Swimmich" launcher, login to the public URL, sort deck works.
3. Per future release: bump `pubspec.yaml` `+build` → `flutter build apk --release` → re-upload.
