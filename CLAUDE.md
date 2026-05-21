# CLAUDE.md — Swimmich Mobile

Project instructions for Claude. Read `SWIMMICH.md` for the narrative project/
release recap. This file is the operational "house rules."

## What this is
- A personal **fork of [Immich](https://github.com/immich-app/immich)** (self-hosted photo manager), pinned to tag **v2.7.5**.
- Swimmich adds a Tinder-style **photo triage / "sort deck"** to the mobile app (`mobile/`).
- Solo developer. Goal loop: branch → build to phone → ready-to-merge PR.

## Locations (paths contain spaces — always quote them)
- **Repo root:** `C:\Users\basil\dev\Swimmich Stack\Swimmich Mobile`
- **Flutter app:** `mobile/`
- **Flutter SDK:** `C:\Users\basil\dev\dev tools\flutter` (call `…\flutter\bin\flutter.bat`)

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
- `androidx.glance` is pinned to `1.1.1` in `mobile/android/app/build.gradle`
  (the `1.+` dynamic version pulled an alpha needing compileSdk 37).
- Immich metadata search **ANDs** `albumIds` (intersection, not OR) — to load a
  union across albums, query each album separately and merge/dedupe.

## Servers
- Local dev: Docker Desktop, then `cd ~/immich-app && docker compose up -d`.
- Production: OVH VPS via `ssh ovh` (141.94.77.202) — Swimmich not yet deployed there.
