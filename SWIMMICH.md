# Swimmich — project & release recap

Context carry-over for new Claude sessions. For day-to-day rules see `CLAUDE.md`.

## What Swimmich is
A personal **fork of Immich** (self-hosted photo manager), tracking tag
**v3.2.4** (upgraded from v3.0.3 on 2026-10-01; v2.7.5 → v3.0.3 on 2026-07-27). It
adds a Tinder-style **photo triage / "sort deck"** to the mobile app. Solo dev.
Workflow: branch off `swimmich-test` → build to phone → ready-to-merge PRs.

Note the `swimmich-test` **branch** remains the integration branch. Prod moved to
the Contabo VPS on 2026-10-01; a test stack can be brought up next to it on demand
(`deploy/contabo/test-stack/`).

- GitHub: `GreatToubib/Swimmich` (gh needs `--repo GreatToubib/Swimmich`).
- Integration branch: **`swimmich-test`** (branch features from here, not `main`).
- Feature branches: `feat/swimmich/sN-...`.

## The sort feature (built & merged into `swimmich-test`)
- Triage state lives in native asset fields, not albums: a server-side
  `sortStatus` column (`new` / `review_later` / `kept`, migration
  `1783000000000-AddAssetSortStatus`), the native `rating` (1-5 stars) and
  `isFavorite`. The original `_New` / `_Review Later` / `⭐` system albums were
  replaced by this on 2026-05-22 (s3) and no longer exist.
- Sort deck (card swipe): **Delete** (trash), **Review Later**, **Sorted**.
  "Sorted" sets `kept`, an optional star rating and favourite, and can add the
  asset to user "quick-pick" albums ("Sort into N albums" in the album picker does
  the same as a right swipe). A delete can be undone from the banner that follows it.
- Source sheet chooses which statuses × albums feed the deck (defaults: New +
  Review Later, "No album"). Each album is queried separately and the results
  unioned/deduped, because Immich's metadata search **ANDs** `albumIds`.
- Quick-pick chips: 4 pinned + 4 recent (MRU, 30-day prune). Deleted albums are
  pruned on Sort-tab open.
- Edit mode: re-sorting an already-sorted card pre-selects its current albums +
  star, and reconciles (removes de-selected). Changes are mirrored into the local
  **Drift** DB so the Photos/Albums views update without a full re-sync.
- Optional "delete local copy": swiping a card that is also on the phone queues its
  device file for the OS trash (batched, flushed on tab switch / app pause).
- Key files: `mobile/lib/services/sort_action.service.dart`,
  `mobile/lib/pages/sort/sort.page.dart`,
  `mobile/lib/pages/sort/sort_source_sheet.dart`,
  `mobile/lib/providers/{sort_queue,sort_filter,quick_pick,local_delete_queue}.provider.dart`.

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
