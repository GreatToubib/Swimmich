# CLAUDE.md — Swimmich Mobile

Project instructions for Claude. Read `SWIMMICH.md` for the narrative project/
release recap. This file is the operational "house rules."

## What this is
- A personal **fork of [Immich](https://github.com/immich-app/immich)** (self-hosted photo manager), tracking tag **v3.0.3** (migrated from v2.7.5 on 2026-07-27).
- Swimmich adds a Tinder-style **photo triage / "sort deck"** to the mobile app (`mobile/`).
- Solo developer. Goal loop: branch → build to phone → ready-to-merge PR.

## Locations (paths contain spaces — always quote them)
- **Repo root:** `C:\Users\basil\dev\Swimmich Stack\Swimmich app`
- **Flutter app:** `mobile/`
- **Flutter SDK:** `C:\Users\basil\dev\dev-tools\flutter` (call `…\flutter\bin\flutter.bat`)
  - Pinned to **exactly 3.44.1** (detached tag checkout, so `flutter --version`
    reports channel `[user-branch]`). `mobile/pubspec.yaml` pins `flutter: 3.44.1`
    as an exact match — 3.44.8 is rejected. Do not run `flutter upgrade`.
  - The folder was renamed from `dev tools` → `dev-tools` on 2026-07-27: the space
    broke Dart's native-assets build hooks (the hook runner invokes `dart.exe`
    unquoted, splitting the path), which blocked i18n codegen and `build_runner`.
    A directory junction does **not** work around it — Dart resolves the real path.

## Branching & GitHub
- Branch from **`swimmich-test`** (the integration branch) — **never** `main`.
- Feature branches: `feat/swimmich/sN-...`. Open PRs **into `swimmich-test`**.
- `gh` requires the explicit repo flag: `gh ... --repo GreatToubib/Swimmich`.

## Building & codegen (Windows / PowerShell)
- Run Flutter via the **full `flutter.bat` path** in PowerShell (MSYS2/bash `build_runner` fails).
- If `build_runner` / `router.gr.dart` output is stale, delete `mobile\.dart_tool\build` and re-run.
- Run `dart analyze` before committing.

## Generated-files rule (CRITICAL)
- Only `git add` **deliberate source edits**. Never stage the dozens of
  `*.g.dart`, `*.g.kt`, `*.g.swift`, or `*.drift.dart` files.
- **Exception:** `mobile/lib/routing/router.gr.dart` (auto_route artifact) **must**
  be committed — the app won't compile without it.
- Also never stage: `mobile/android/local.properties`, `mobile/pubspec.lock`, `.claude/`.

## Android release
- Signing keystore: `mobile/android/key.jks` (gitignored), alias **`swimmich`**.
- App id **`app.swimmich`**; launcher label **Swimmich**. Kotlin namespace stays
  `app.alextran.immich`. **Do not** rename the Dart package `immich_mobile` (breaks imports).
- Per release: bump `mobile/pubspec.yaml` `+build` number, then
  `flutter build apk --release` → `mobile/build/app/outputs/flutter-apk/app-release.apk`.
- Distribute via **Firebase App Distribution**, project `swimmich-afe59` (free Spark plan).

## Known gotchas
- `androidx.glance`: the fork's manual `resolutionStrategy` pin was **removed** in
  the v3 migration — upstream now enforces the identical 1.1.1 via a `strictly`
  constraint in `build.gradle` + `gradle/libs.versions.toml`. Don't re-add it.
- The v3 Dart client is generated with `useOptional=true`, so every optional DTO
  field is `Optional<T>`, not a bare nullable. Two traps: `x != null` on an
  `Optional` is **always true** (analyzer says warning, not error), and
  `Optional.present(null)` serialises as explicit JSON `null` — which is a
  different request from omitting the field. Use `Optional.absent()` to omit.
- Asset `rating`: v3 rejects `0` (must be -1, 1-5, or null). Swimmich uses 0 for
  "unrated", so `setSortStatus` maps 0 → null.
- Immich metadata search **ANDs** `albumIds` (intersection, not OR) — to load a
  union across albums, query each album separately and merge/dedupe.

## Servers
- Local dev: Docker Desktop, then `cd ~/immich-app && docker compose up -d`.
- **Deployed on the OVH VPS (141.94.77.202) since 2026-05** — **one live stack**:
  | Env  | Branch     | URL                                 | Port |
  |------|------------|-------------------------------------|------|
  | prod | `swimmich` | https://swimmich.azestysolution.com | 2283 |
- The **test stack was decommissioned 2026-07-28** to reclaim disk on the shared
  VPS. `swimmich-test` is still the integration branch — keep branching from it
  and opening PRs into it; only the *server* went away. CI still builds the
  `:test` image, and the DNS record is kept, so it can be restored cheaply.
  Restore steps are in `..\CLAUDE.md`.
- Connect as **`ssh swimmich`** (unprivileged user `basil`). `ssh ovh` is root
  break-glass — don't use it without asking.
- Images build in GitHub Actions → `ghcr.io/greattoubib/swimmich-server`; the VPS
  only pulls. prod is manual via `~/swimmich/deploy.sh prod`.
- Disk is tight — the box is **shared with junior**. Check `df -h /home/basil`
  before anything that writes.
- Full deploy/CI/Caddy runbook: `..\CLAUDE.md` (the `Swimmich Stack` root).
