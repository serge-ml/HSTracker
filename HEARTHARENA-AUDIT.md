# HSTracker Arena implementation audit

Audit date: 2026-07-20

This document records implementation evidence for HSTracker Arena. It
deliberately distinguishes source completion from runtime proof.

## Evidence levels

- **Proven locally** — exercised by an executable check with Xcode 26.6 and
  Swift 6.3.3 on Apple silicon.
- **Build-proven** — compiled as part of both unsigned Debug and Release app
  targets, but still requires a live Hearthstone session for behavioral proof.
- **Manual Hearthstone pending** — only a live client can prove the behavior.
- **Deferred intentionally** — outside the personal MVP or requires a legal or
  release decision.

## Stage audit

### Stage 0 — base fork and reproducible build

| Requirement | State | Evidence |
|---|---|---|
| GitHub fork/origin | Proven locally | `origin` is `serge-ml/HSTracker` |
| Fetch-only official upstream | Proven locally | `upstream` fetch URL is HearthSim; push URL is `DISABLED` |
| Clean upstream-sync branch | Proven locally | local `upstream-sync` tracks `upstream/master` |
| Full app build | Proven locally | unsigned Debug and Release configurations build successfully |
| Installed Release launch | Proven locally | signed universal app launched from `/Applications` and completed Mono, BobsBuddy and HearthArena initialization |
| CI build | Implemented, execution pending | `.github/workflows/heartharena-ci.yml` |
| HearthArena XCTest suite | Proven locally | SwiftPM compiles the production core; 16/16 tests pass |
| Name and Bundle ID | Proven in built app | `HSTracker Arena`, `io.github.serge-ml.hstrackerarena` |
| Official updater isolation | Proven in source and built app | no feed, keys, controller, bridging import, or bundled Sparkle product |
| Backup procedure | Proven structurally | `HEARTHARENA.md` |

The stage Definition of Done is not yet proven because the complete app has
not launched against a normal match.

### Stage 1 — Arena choices spike

| Requirement | State | Evidence |
|---|---|---|
| ChoicesChangedEventArgs and callback | Proven structurally/typechecked | `ArenaWatcher.swift` |
| Adapter boundary | Proven structurally/typechecked | `ArenaChoiceAdapter.swift` |
| Class, slot, version and IDs in logs | Proven structurally | `HearthArenaFeatureBootstrap.swift` |
| Hide on slot advance/pick | Proven structurally/typechecked | watcher callback plus state-machine tests |
| Three sequential live offers | Manual Hearthstone pending | live Arena required |
| Normal and Underground Arena | Manual Hearthstone pending | live Arena required |

### Stage 2 — data provider

| Requirement | State | Evidence |
|---|---|---|
| HTML fixture and parser | Proven locally | core smoke test |
| HTTP client failure handling | Proven locally | invalid URL, HTTP 503, empty and successful response checks |
| Entities, badge removal and normalization | Proven locally | fixture and normalization checks |
| Exact class-aware lookup | Proven locally | card-ID/name/neutral/unknown checks |
| Snapshot schema and content hash | Proven locally | cache round-trip |
| Validation | Proven locally | missing class, range, duplicate and coverage-drop checks |
| Atomic cache and stale policy | Proven locally | cache and refresh-throttle checks |
| Failed replacement keeps valid data | Proven locally | store smoke test |
| Mapping coverage ≥99.5% | Proven against current public data | 1,148/1,148 exact IDs, 100.000% |
| Bundled first-launch fallback | Deferred intentionally | redistribution permission has not been confirmed |

Offline operation is proven after one successful snapshot. First launch
without network remains unavailable until a redistributable snapshot is
approved.

### Stage 3 — overlay

| Requirement | State | Evidence |
|---|---|---|
| Rated view model and rank | Proven locally | resolver tests |
| Click-through, non-activating NSPanel | Build-proven | `ArenaOverlayWindow.swift` and controller |
| Three card badges | Proven geometrically | layout smoke across three sizes and scales |
| Package individual-score lists | Proven geometrically/typechecked | no aggregate or package rank |
| State-machine synchronization | Proven locally | duplicate/stale/pick/close checks |
| Unknown card renders as dash | Proven structurally | rated model and views |
| Windowed/fullscreen/click behavior | Manual Hearthstone pending | live app required |

### Stage 4 — settings, migration and reliability

| Requirement | State | Evidence |
|---|---|---|
| Overlay settings and reset | Build-proven | HearthArena preferences pane |
| Data status, age and manual refresh | Build-proven | preferences pane |
| Allowlisted UserDefaults migration | Build-proven | tokens excluded, legacy data never deleted |
| Diagnostics and safe logs | Proven locally/typechecked | state, mode, coverage, errors, unknown cards; rerenders do not double-count |
| Package handling | Implemented, typechecked | individual scores only |
| Manual matrix | Manual Hearthstone pending | checklist in `HEARTHARENA.md` |
| Main tracker regression check | Manual Hearthstone pending | normal match required |

### Stage 5 — updates and releases

| Requirement | State | Evidence |
|---|---|---|
| Scheduled upstream check and sync PR | Implemented, execution pending | `upstream-sync.yml` |
| Nightly parser/mapping health | Implemented, live parser proven locally | `parser-health.yml` opens/updates an issue on failure |
| Fork version | Proven structurally | upstream 3.6.1 plus `ha.1` |
| ZIP and SHA-256 | Implemented, execution pending | manual unsigned personal-build workflow |
| Persistent local build and `/Applications` delivery | Proven locally | Release build, entitlement-preserving signing, resource/signature verification, atomic install and relaunch completed |
| Local update and rollback | Proven locally | installed artifact was replaced with rollback copy retained; rollback swap and relaunch completed |
| Smoke test and rollback documentation | Proven structurally | `HEARTHARENA.md` and `scripts/hstracker_arena_app.sh` |
| Developer ID/notarization | Deferred intentionally | not needed for the first personal prototype |
| Own Sparkle feed | Deferred intentionally | requires signed fork releases and fork-owned keys |
| Version-to-version public update | Not achieved | no fork release or fork-owned update feed exists yet |

## Current executable evidence

```text
heartharena_core_smoke=passed
heartharena_layout_smoke=passed
heartharena_adapter_smoke=passed
ratings=4140
classes=12
card_ids=4140
unique_tier_cards=1148
database_matches=1148
card_id_coverage=100.000%
canonical_name_matches=1148
arena_watcher_typecheck=passed
adapter_integration_lifecycle_typecheck=passed
overlay_ui_typecheck=passed
preferences_and_migration_typecheck=passed
configuration_validation=passed
swift_test=16 passed, 0 failed
xcode_debug_build=passed
xcode_release_build=passed
debug_app_launch_smoke=passed
local_release_signing=passed
local_release_entitlements=passed
local_app_install=passed
local_app_update=passed
local_app_rollback=passed
installed_release_launch=passed
installed_heartharena_ratings=4140
debug_bundle=HSTracker Arena, arm64, build DEV
release_bundle=HSTracker Arena, x86_64+arm64, build 3562
```

Both app artifacts were inspected with `plutil`, `file`, `codesign`, and
binary-string checks. They have the fork bundle ID, fork URL scheme and
HearthArena bootstrap code. Xcode produces an unsigned Release bundle; the
local delivery script signs a staging copy, verifies its embedded resources and
deep signature, installs it as `/Applications/HSTracker Arena.app`, and keeps
one signed rollback copy. With no Apple identity in Keychain, the tested local
installation uses an ad-hoc signature with the stable designated requirement
`identifier "io.github.serge-ml.hstrackerarena"`.

The inherited `HSTrackerTests` Xcode target is not used as the feature gate. In
this checkout it omits hundreds of application source files and fails to
compile independently of HearthArena. Clear upstream leftovers found while
checking it (the removed `Wrap` dependency and obsolete Mono include paths)
were corrected. HearthArena's isolated SwiftPM test target compiles the actual
Domain, Data and Diagnostics production sources instead, while Debug and
Release app builds prove their Xcode integration.

## Remaining completion gates

1. Execute the new CI workflow on GitHub after the branch is pushed.
2. Launch the fork and verify a normal constructed match has no regression.
3. Complete the live Arena matrix, including three sequential offers,
   Underground, packages, windowed/fullscreen, backgrounding and click-through.
4. Verify migration on a backup of the actual existing profile.
5. Produce two distinct versioned release artifacts and exercise the eventual
   public update channel between them. Local install and rollback mechanics are
   already proven.
6. Confirm redistribution permission before adding a bundled ratings snapshot.

Until those gates have evidence, the overall development-plan Definition of
Done is not claimed.
