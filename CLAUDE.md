# CLAUDE.md — Swimmich Mobile

Project instructions for Claude. Read `SWIMMICH.md` for the narrative project/
release recap. This file is the operational "house rules."

## What this is
- A personal **fork of [Immich](https://github.com/immich-app/immich)** (self-hosted photo manager), tracking tag **v3.2.4** (from v3.0.3 on 2026-10-01; v2.7.5 → v3.0.3 on 2026-07-27).
- Swimmich adds a Tinder-style **photo triage / "sort deck"** to the mobile app (`mobile/`).
- Solo developer. Goal loop: branch → build to phone → ready-to-merge PR.

## Locations (paths contain spaces — always quote them)
- **Repo root:** `C:\Users\basil\dev\Swimmich Stack\Swimmich app`
- **Flutter app:** `mobile/`
- **Flutter SDK:** `C:\Users\basil\dev\dev-tools\flutter` (call `…\flutter\bin\flutter.bat`)
  - A shallow checkout of tag **3.47.1**, the exact version `mobile/pubspec.yaml`
    pins since the v3.2.4 upgrade (`flutter --version` reports channel `[user-branch]`).
    Do not run `flutter upgrade`. It is the only Flutter SDK on the PC (the 3.44.1 one
    was removed on 2026-10-02). When upstream bumps the pin, move it with
    `git -C C:\Users\basil\dev\dev-tools\flutter fetch --depth 1 origin tag <version> --no-tags`,
    then `git -C … checkout <version>` and `flutter --version` (downloads the engine).
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
- Since v3.2.4 upstream commits **no generated mobile code**: the OpenAPI Dart client
  (`mobile/generated/openapi`), `router.gr.dart`, `*.g.dart`, `*.drift.dart`, the
  translation keys and the pigeon files are all gitignored. After a checkout, regenerate:
  1. Dart client (needs Java + Node, so run it in Docker; `git archive` avoids CRLF
     breaking the generator's patch files). From the repo root:
     `git -c core.autocrlf=false archive -o $env:TEMP\oa.tar HEAD open-api`, then
     `docker run --rm -v "$env:TEMP\oa.tar:/oa.tar:ro" -v "${PWD}\mobile:/out" node:24.15.0 bash -c "tar -xf /oa.tar -C / && apt-get update -qq && apt-get install -y -qq openjdk-17-jre-headless >/dev/null && npm i -g @openapitools/openapi-generator-cli@2.40.1 >/dev/null && cd /open-api && bash ./bin/generate-dart-sdk.sh && rm -rf /out/generated && cp -r /mobile/generated /out/"`
  2. In `mobile\`: `flutter pub get`, then `dart run pigeon --input <file>` for each
     `pigeon\*.dart` (also writes the Kotlin/Swift halves the Android build needs),
     `dart run easy_localization:generate -S ..\i18n`,
     `dart run bin\generate_keys.dart`, `dart run drift_dev make-migrations`,
     `dart run build_runner build` (same chain as upstream's `mobile/mise.toml` `codegen`).
- If `build_runner` output is stale, delete `mobile\.dart_tool\build` and re-run.
- Run `dart analyze --fatal-infos` before committing (upstream's level; v3.2 enforces
  braces on one-line `if` bodies and `unawaited(...)` for fire-and-forget futures).

## Generated-files rule (CRITICAL)
- Only `git add` **deliberate source edits**. Never stage generated files
  (`*.g.dart`, `*.g.kt`, `*.g.swift`, `*.drift.dart`, `router.gr.dart`, `mobile/generated/`).
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
- v3.2 deprecated the flat search fields (`albumIds`, `page`, ...) in favour of a
  `filter` tree; the two shapes cannot be mixed. The sort deck still sends flat
  `MetadataSearchDto`s, and the fork's `sortStatus` filter exists **only** in the flat
  shape. Port both to `filter` before upstream drops the flat fields (v4).
- Server search results select an explicit column list (`columns.searchAsset` in
  `server/src/database.ts`); a new asset column the API returns must be added there.
- Generated OpenAPI enums are Dart enums with a private value: use `toJson()`, not `.value`.
- **DB migrations:** never renumber a fork migration once it has run on prod (Kysely
  then refuses to boot: "previously executed migration ... is missing"). On every
  upstream bump, check that no *new* upstream migration sorts below an applied fork
  migration. Number a new fork migration just above the newest upstream one and list
  it in `server/src/schema/migrations/ORDER` (checked by `sql-tools migrations verify-order`).

## Servers
- Local dev: Docker Desktop, then `cd ~/immich-app && docker compose up -d`.
- **Prod runs on the Contabo VPS since 2026-10-01** (`ssh contabo`, stack in `/opt/immich`):
  | Env  | Branch     | URL                                 | Port (127.0.0.1) |
  |------|------------|-------------------------------------|------------------|
  | prod | `swimmich` | https://swimmich.azestysolution.com | 2283             |
- Runbook: `deploy/contabo/README.md`. Deploy (only with Basil's OK) =
  `ssh contabo /opt/immich/src/deploy/contabo/deploy.sh` once CI has built `:prod`; it
  takes a pre-deploy `pg_dumpall` first. Nightly restic backups run at 03:00.
- A temporary test stack (prod DB copy + the `:test` image on 127.0.0.1:2284) can be
  brought up next to prod: `deploy/contabo/test-stack/README.md`.
- `swimmich-test` is still the integration branch — keep branching from it and opening
  PRs into it. CI builds `:test` on every push to it.
- Images build in GitHub Actions → `ghcr.io/greattoubib/swimmich-server`; the VPS
  only pulls.
- The old OVH VPS (141.94.77.202) is Junior's shared host: its Swimmich stack is
  stopped with the data kept. Do not touch it.
