# Repository instructions

## Local verification

- Do not run clean builds, archives, Release builds, or repository delivery
  scripts that build/package the macOS app unless the user explicitly requests
  that level of verification.
- A user report about behavior in the running app, or a request to fix visible
  UI/runtime behavior, implicitly authorizes the persistent incremental Debug
  build/install/relaunch fast path below. Do not require a separate request to
  "build the app," and do not stop after isolated tests when the user needs the
  installed app to exercise the fix. A request limited to review, explanation,
  or diagnosis does not authorize an app build.
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
  4. For a running-app bug fix or visible UI/runtime change, run the applicable
     checks above and then update the installed app with the incremental Debug
     fast path so the user can immediately verify the result. For non-runtime
     work, build the app only when the preceding layers cannot establish the
     behavior or the user requests it.
- For the incremental Debug development path:
  - reuse stable DerivedData and Swift package checkout directories;
    the default locations are `build/local/DerivedData` and
    `build/local/SourcePackages`;
  - use the `HSTracker` scheme, Debug configuration, macOS destination,
    `ONLY_ACTIVE_ARCH=YES`, `CODE_SIGNING_ALLOWED=NO`, and
    `-disableAutomaticPackageResolution`;
  - compile only the active architecture;
  - do not clean caches as a routine step;
  - do not resolve packages again unless `Package.resolved` or package state
    changed;
  - the current `scripts/hstracker_arena_app.sh install` path builds Release,
    so do not use it for an ordinary incremental Debug iteration;
  - copy the completed Debug app to a staging bundle, sign it with the required
    entitlements and stable designated requirement, and verify the signature
    and bundle identifier before installation;
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
  of the development loop. Perform installation/signing work only when the
  running-app fast path is authorized above or the user otherwise requests a
  real app run.
- When changing build performance, measure a warm incremental build before and
  after with Xcode's timing summary (for example,
  `-showBuildTimingSummary`). Do not run that measurement without the local
  build authorization required above.
