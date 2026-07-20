# HSTracker Arena

This fork adds public HearthArena base tier-list scores to the normal three-card
Hearthstone Arena draft. It does not reproduce HearthArena's private dynamic
synergy or archetype advice.

## Current implementation

- `ArenaWatcher` publishes neutral events for a new offer, a picked card, and a
  closed draft.
- `ArenaChoiceAdapter` is the only boundary that knows both HearthMirror types
  and the HearthArena domain model.
- The parser reads the public English tier list and extracts the Hearthstone
  card ID from `data-card-image`. Exact card-ID lookup is preferred; normalized
  English names are a strict fallback.
- A validated snapshot is written atomically to:

  ```text
  ~/Library/Application Support/HSTracker/heartharena/tierlist-v1.json
  ```

- A snapshot is considered stale after 24 hours. Network or parser failures keep
  the previous valid snapshot. Automatic attempts are also persisted and
  limited to one per 24 hours; the manual refresh button intentionally bypasses
  that limit.
- The overlay is a transparent, non-activating, click-through `NSPanel` aligned
  with the existing `SizeHelper.hearthstoneWindow` frame.
- During the Underground Arena deck-edit step after a five-card redraft, the
  overlay shows a full rating badge on each of the five cards currently
  outside the deck. It retains the original 35-card pool and follows each
  deck swap as a multiset difference, including duplicate cards. Ratings are
  intentionally not drawn beside the deck list because Hearthstone does not
  expose row coordinates or its internal scroll position.
- Settings and data diagnostics are available in the HearthArena preferences
  pane.

Package offers use a separate compact list for each of the three choices. It
shows only the individual card scores and explicitly says that no package rank
is calculated; no average or other misleading aggregate is displayed.

## App identity and updates

- Product name: `HSTracker Arena`
- Bundle ID: `io.github.serge-ml.hstrackerarena`
- Primary URL scheme: `hstracker-arena`
- Legacy `hstracker` is also registered solely for the existing HSReplay OAuth
  client callback. Do not run the official app and the fork together while
  signing in to HSReplay.
- Fork revision: `ha.1` on top of upstream `3.6.1`
- The official HearthSim Sparkle feed, public keys, menu controller, and linked
  Sparkle product are removed. Reintroduce Sparkle only with the fork's own
  signed appcast.
- HearthSim's Sentry DSN and Mixpanel project token are not used. Retained
  upstream Mixpanel calls use an opted-out local-only instance, and Sentry is
  not started until the fork has its own endpoint.

The first launch can import an allowlist of ordinary settings from
`net.hearthsim.hstracker`. HSReplay tokens are deliberately not copied, and old
preferences are never deleted.

## Build prerequisites

A full Xcode installation is required. Apple Command Line Tools alone cannot
build or test this `.xcodeproj`.

After installing Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -resolvePackageDependencies -project HSTracker.xcodeproj

swift test

xcodebuild build \
  -project HSTracker.xcodeproj \
  -scheme HSTracker \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -project HSTracker.xcodeproj \
  -scheme HSTracker \
  -configuration Release \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

The SwiftPM suite contains the HearthArena unit tests and compiles the same
Domain, Data and Diagnostics files used by the app. The inherited
`HSTrackerTests` Xcode target is not a dependable repository-wide gate in this
checkout because it omits hundreds of application source files. CI therefore
runs `swift test`, then builds the complete unsigned app in both
configurations. Build-time downloads use the macOS-provided `curl`; `wget` is
not required.

## Local delivery to Applications

The normal local update path builds a Release app in the persistent ignored
`build/local/` directory, signs and verifies a staging copy, atomically replaces
the installed app, retains one previous installation for rollback, and launches
the result:

```bash
./scripts/hstracker_arena_app.sh install
```

The installed path is always:

```text
/Applications/HSTracker Arena.app
```

No build or install artifact is placed in `/tmp`. Swift package checkouts,
DerivedData, the signed staging artifact, and the rollback copy all remain
under `build/local/`, so subsequent builds are incremental. Every successful
update replaces the single rollback copy with the installation that was
running immediately before it.

Useful commands:

```bash
./scripts/hstracker_arena_app.sh build
./scripts/hstracker_arena_app.sh install --no-build
./scripts/hstracker_arena_app.sh status
./scripts/hstracker_arena_app.sh launch
./scripts/hstracker_arena_app.sh rollback
```

`install --no-build` is useful for reinstalling the already verified staging
artifact. `rollback` swaps the current and previous installations, so it can
also be run again to return to the newer build.

If a valid Apple code-signing identity is available in Keychain, the script
uses it automatically. Otherwise it creates a valid local ad-hoc signature
with a stable designated requirement for
`io.github.serge-ml.hstrackerarena`. This is suitable for one-machine
development and keeps the app at a stable path for Accessibility permission.
The final app signature preserves HSTracker's debugger, JIT and library-loading
entitlements and enables hardened runtime; without those entitlements
HearthMirror cannot obtain the task port needed to read Hearthstone state.
Public distribution still requires a Developer ID signature and notarization.

For Accessibility, add `/Applications/HSTracker Arena.app` in System Settings →
Privacy & Security → Accessibility. Do not add an Xcode DerivedData copy; its
path and signing identity are development implementation details.

The intended public update path is separate from the local installer:

1. A version tag triggers a reproducible Release build in CI.
2. CI signs the app with the fork's Developer ID identity, enables the hardened
   runtime, notarizes it with Apple, and staples the notarization ticket.
3. CI publishes the verified ZIP and checksum as a versioned GitHub release.
4. The release job updates a fork-owned, signed Sparkle appcast.
5. Existing installations download the ZIP through Sparkle, validate its
   signature, replace the app in `/Applications`, and relaunch.

The repository does not enable that channel yet: Developer ID credentials,
notarization credentials, fork-owned Sparkle keys, and a first versioned
release are required. Until then, `hstracker_arena_app.sh install` is the
canonical update path and exercises the same build → verify → replace →
relaunch lifecycle locally.

After the branch is pushed, the manual `HSTracker Arena personal build`
workflow can produce an unsigned ZIP plus SHA-256 checksum as a 14-day Actions
artifact. It does not create a release. macOS may require the usual local
Gatekeeper override for an unsigned personal build.

The pure Swift core can be checked without Xcode:

```bash
swiftc \
  HSTracker/HearthArenaOverlay/Domain/*.swift \
  HSTracker/HearthArenaOverlay/Data/*.swift \
  HSTracker/HearthArenaOverlay/Diagnostics/*.swift \
  scripts/heartharena_core_smoke.swift \
  -o /tmp/heartharena-core-smoke

/tmp/heartharena-core-smoke \
  HSTrackerTests/HearthArenaOverlay/Fixtures/heartharena-tierlist-sample.html

swiftc \
  HSTracker/HearthArenaOverlay/UI/ArenaOverlayLayout.swift \
  scripts/heartharena_layout_smoke.swift \
  -o /tmp/heartharena-layout-smoke

/tmp/heartharena-layout-smoke
```

The scheduled parser-health job also compares exact HearthArena card IDs with
the current full English HearthstoneJSON `cards.json` database used by
HSTracker and fails below 99.5% coverage.

## First-run safety

Close Hearthstone and the official HSTracker before testing the fork. Back up
existing data first:

```bash
mkdir -p "$HOME/Documents/HSTracker-backup"
cp -a \
  "$HOME/Library/Application Support/HSTracker" \
  "$HOME/Documents/HSTracker-backup/"
defaults export net.hearthsim.hstracker \
  "$HOME/Documents/HSTracker-backup/net.hearthsim.hstracker.plist"
```

The preferences export can contain HSReplay credentials. Do not commit or share
the backup.

## Upstream synchronization

The official repository is configured as a fetch-only `upstream` remote:

```bash
git fetch upstream
git switch -c sync/hstracker-<version>
git merge upstream/master
```

Resolve conflicts only in the sync branch, then build, run tests, and smoke-test
both normal tracking and an Arena draft before merging.

The daily `HSTracker upstream sync` workflow fast-forwards the clean
`upstream-sync` audit branch and opens a unique review PR when official
`master` advances. Safe PRs receive `upstream-sync` and `automerge` labels and
are configured for auto-merge after required CI passes. Changes to workflows,
project identity, entitlements, or scripts pause auto-merge for explicit
CODEOWNER review. A merge conflict fails safely and creates or updates an Issue
containing the upstream SHA, fork base SHA, conflicting files, and workflow
run.

The workflow requires a repository-only fine-grained token in the
`UPSTREAM_SYNC_TOKEN` Actions secret with `Contents: write` and
`Pull requests: write`. Prefer a dedicated GitHub App or bot account so the
owner can review protected changes authored by the sync identity. The built-in
workflow token handles labels and conflict Issues and never pushes the sync
branch, so PAT-authored pushes still trigger pull-request CI.

The inherited `fastlane/` and `scripts/*release*` files still describe
HearthSim's official release infrastructure. They are intentionally not wired
to any workflow in this fork and must not be used for HSTracker Arena releases.

## Manual Arena smoke test

1. Launch the fork and confirm the HearthArena data status is Fresh or Stale.
2. Open a normal Arena draft and select a hero.
3. Confirm three ratings appear for each card offer within one second.
4. Confirm the highest score has rank 1 and unknown cards show `—`.
5. If a package offer appears, confirm each package lists only its individual
   card scores and has no package rank or average.
6. In an Underground Arena redraft, draft five new cards and enter the
   `Discard 5 cards from your deck` screen.
7. Confirm all five cards outside the deck have full score badges. Swap one
   card at a time and confirm the changed physical slot updates within one
   second.
8. Swap a duplicate card and confirm all five physical discard slots still
   receive the correct badge.
9. Confirm clicks pass through the overlay.
10. Pick a card and verify the old badges disappear before the next offer.
11. Move or resize Hearthstone and check overlay alignment.
12. Check windowed, fullscreen, Russian and English clients.
13. Disable the network and confirm the last valid snapshot still works.
14. Leave Arena and confirm the overlay closes.

## Data and attribution

Ratings come from the public
[HearthArena tier list](https://www.heartharena.com/tierlist). This repository
does not currently bundle or redistribute a full rating snapshot; offline mode
therefore works after the first successful refresh. Confirm redistribution
permission before adding a bundled last-known-good dataset or distributing
pre-populated releases.

HSTracker Arena is not affiliated with HearthArena, HearthSim, Blizzard, or
their respective owners.
