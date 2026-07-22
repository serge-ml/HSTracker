# Repository instructions

## Local verification

- Do not run local full-application builds, including `xcodebuild build`,
  `xcodebuild archive`, or repository scripts that build/package the macOS app,
  unless the user explicitly requests a local build.
- Do not use a local full-app build as a routine pre-commit check. Full Debug
  and Release builds are verified by GitHub Actions.
- Prefer lightweight, targeted tests, smoke checks, linting, and static
  validation that do not build the complete application.

## Local development fast path

- Use the shortest verification layer that covers the change:
  1. Run focused SwiftPM tests with `swift test --filter ...` for isolated core
     logic when a suitable test target exists.
  2. Run the existing focused Swift smoke scripts for HearthArena parser,
     layout, adapter, mapping, or related isolated code when applicable.
  3. Run static validation such as `plutil`, `xmllint`, or `bash -n` for project
     metadata, XIB, plist, and shell-script-only changes.
  4. Build and launch the real app only when behavior cannot be established by
     the preceding layers and the user explicitly requests a local build.
- When a real local app test is explicitly requested, prefer a persistent,
  incremental Debug development build over the Release delivery path:
  - reuse stable DerivedData and Swift package checkout directories;
  - compile only the active architecture;
  - do not clean caches as a routine step;
  - do not resolve packages again unless `Package.resolved` or package state
    changed;
  - keep the app bundle identifier, required entitlements, signing, stable
    `/Applications/HSTracker Arena.app` path, atomic replacement, and rollback
    behavior needed for Accessibility and HearthMirror testing;
  - relaunch the installed app after a successful incremental update.
- Reserve a local Release build for release-specific behavior, final packaging
  checks, or an explicit user request. Do not use Release for each edit/test
  iteration.
- Do not add a separate development host app, recorded-log replay harness, or
  CI-artifact installation path solely to speed ordinary local development
  unless the user explicitly asks for one.

## Build performance hygiene

- Treat external resources and dependencies as bootstrap/versioned inputs.
  Network downloads must not run during every ordinary incremental build.
- Xcode Run Script phases must declare accurate input and output paths (or a
  version-keyed stamp/file list) so dependency analysis can skip unchanged
  work. Do not set `alwaysOutOfDate` unless the phase genuinely must run for
  every build.
- Avoid repeatedly copying or re-signing unchanged large Mono, card-data,
  HearthMirror, HearthDb, or BobsBuddy resources during the compile-only part
  of the development loop. Perform installation/signing work only when a real
  app run is requested.
- When changing build performance, measure a warm incremental build before and
  after with Xcode's timing summary (for example,
  `-showBuildTimingSummary`). Do not run that measurement without the local
  build authorization required above.
