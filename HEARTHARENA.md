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
- Sparkle `2.9.2` is pinned through Swift Package Manager and linked only to
  the HSTracker Arena app target.
- The updater uses only
  `https://serge-ml.github.io/HSTracker/appcast.xml` and the fork-owned EdDSA
  public key embedded in `Info.plist`. The official HearthSim feed and public
  key are rejected by CI.
- Automatic checks are off by default. The app menu contains
  `Check for Updates…`, and the Updates preferences pane controls automatic
  checks and downloads using Sparkle's own persisted settings.
- The private Sparkle key is not stored in this repository. Updater logs contain
  state and ordinary errors, never signing material or credentials.
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

The fork updater boundary can be checked independently:

```bash
./scripts/verify_fork_update_identity.sh
```

This fails when the fork feed or public key differs from the release pipeline,
when the official HearthSim updater identity reappears, or when a recognizable
private-key file is tracked.

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

The public update path is separate from the local installer:

1. `HSTracker Arena CI` tests a default-branch commit and uploads the unsigned
   Release ZIP plus SHA-256 as a 14-day artifact.
2. `HSTracker Arena Release` downloads that exact run's artifact by run ID and
   commit SHA; it does not rebuild or execute repository scripts with secrets.
3. The protected `release` job assigns a monotonic build number, verifies the
   bundle, signs all nested code and the app, and optionally notarizes and
   staples it.
4. Pinned official Sparkle tools sign the ZIP and appcast with the fork key.
5. A draft GitHub Release is verified before it becomes public. The release
   asset is checked over HTTPS before `appcast.xml` is atomically pushed to
   `gh-pages`.
6. If publication or feed verification fails, the workflow re-drafts the
   release and rolls back its appcast commit.
7. Existing installations validate the EdDSA signature, replace the app in
   `/Applications`, and relaunch.

The first public release still requires repository settings, the protected
environment, a Sparkle secret, and GitHub Pages. Without a Developer ID
certificate the workflow deliberately produces an ad-hoc-signed test release;
public distribution should use Developer ID and notarization. Until the first
end-to-end release is proven, `hstracker_arena_app.sh install` remains the
development and emergency path.

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

The workflow uses only GitHub's short-lived built-in token. A pull request
created by that token produces a CI run that requires manual approval, so the
sync job also explicitly dispatches `HSTracker Arena CI` for the exact sync
branch SHA. GitHub always creates runs for `workflow_dispatch`; required
`core` and `app` checks still gate auto-merge. No long-lived
`UPSTREAM_SYNC_TOKEN`, GitHub App, or personal access token is required.

The inherited `fastlane/` and `scripts/*release*` files still describe
HearthSim's official release infrastructure. They are intentionally not wired
to any workflow in this fork and must not be used for HSTracker Arena releases.

## Delivery operations

### One-time GitHub setup

Protect the repository default branch and require the `core` and `app` jobs
from `HSTracker Arena CI`. Require a pull request, dismiss stale approvals,
require CODEOWNER review for protected delivery files, block force pushes, and
allow auto-merge. The sync workflow grants its built-in token `Actions`,
`Contents`, `Issues`, and `Pull requests` write access only for the duration of
the job; no persistent sync credential is provisioned.

Create a GitHub Environment named `release`. Initially require owner approval
before deployment. Add:

| Secret | Required | Purpose |
|---|---:|---|
| `SPARKLE_ED_PRIVATE_KEY` | yes | Base64 Ed25519 seed exported by Sparkle `generate_keys` |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | for public releases | Developer ID Application `.p12` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | with certificate | `.p12` password |
| `TEMP_KEYCHAIN_PASSWORD` | with certificate | Ephemeral runner keychain |
| `APPLE_ID` | for notarization | Apple developer account |
| `APPLE_TEAM_ID` | for notarization | Apple team identifier |
| `APPLE_APP_SPECIFIC_PASSWORD` | for notarization | Notary authentication |

Configure GitHub Pages to serve the root of the `gh-pages` branch. That branch
contains only `.nojekyll` and the signed `appcast.xml`; update ZIPs remain
versioned GitHub Release assets.

Never paste secrets into workflow inputs, Issues, PR comments, logs, release
notes, or repository files. Rotate a token immediately if it appears in any of
those locations.

### Running and diagnosing automation

- CI: Actions → `HSTracker Arena CI` → Run workflow.
- Sync: Actions → `HSTracker upstream sync` → Run workflow.
- Release: allow the automatic post-CI run on the default branch, or run
  `HSTracker Arena Release` manually with the successful CI run ID.
- Sync conflicts: inspect the `[automation] Upstream sync conflict` Issue and
  its linked workflow run. Resolve in a new review branch; never force the
  default branch to the upstream SHA.
- Parser failures: inspect the `[automation] HearthArena parser health check
  failed` Issue. A stale valid local snapshot remains usable.
- Release failures: inspect the `sign` job first, then `publish`. Signing
  secrets exist only in `sign`; the public `publish` job receives only verified
  signed artifacts.

A no-change sync exits successfully. A conflict, red required check, changed
protected delivery file, missing secret, bad signature, failed notarization, or
unreachable feed stops automatic delivery.

### Disabling updates and revoking a release

Users can clear `Automatically check for updates` in Preferences → Updates.
To prevent all clients from seeing a newly bad release:

1. re-draft the GitHub Release;
2. revert the corresponding `gh-pages` appcast commit and push the revert;
3. verify the public feed no longer names the revoked asset;
4. publish a fixed build with a strictly higher `CFBundleVersion`.

Do not reuse a tag, ZIP filename, build number, or signature. Keep the previous
Release available for manual recovery. A user can download that earlier ZIP,
quit the app, replace `/Applications/HSTracker Arena.app`, and relaunch. Local
development installations can instead use:

```bash
./scripts/hstracker_arena_app.sh rollback
```

### Rotating credentials

- Sync uses no persistent credential; GitHub creates and expires a scoped token
  for every workflow job.
- Sparkle key: keep the old key long enough to publish a bridge release signed
  by the old key whose app embeds the new public key. Only later sign new
  archives with the new private key. Replacing the feed key without a bridge
  strands installed clients.
- Developer ID: export the renewed Developer ID Application identity as a
  password-protected `.p12`, update all three certificate/keychain secrets, run
  a protected test release, verify notarization, then remove the old export.
- Apple notarization password: update the environment secret and run a manual
  release from a fresh successful CI run.

### Installed-app verification

```bash
app="/Applications/HSTracker Arena.app"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -d -r- --verbose=2 "$app"
spctl --assess --type execute --verbose=2 "$app"
xcrun stapler validate "$app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$app/Contents/Info.plist"
```

`spctl` and stapler validation are expected to succeed only for a Developer
ID-notarized release. The bundle identifier must remain
`io.github.serge-ml.hstrackerarena`.

### N → N+1 acceptance

Before removing manual approval from the `release` environment, prove two real
releases:

1. install N in `/Applications` and confirm it does not offer itself;
2. publish N+1 through PR, required CI, and the release workflow;
3. verify release notes, Sparkle download, signature validation, replacement,
   relaunch, installed build number, tracking, Arena overlay, and a reboot;
4. confirm Accessibility and Input Monitoring permissions remain effective;
5. confirm a corrupted ZIP is rejected, an older build is not installed, an
   unavailable feed does not prevent launch, a failed release leaves the old
   appcast active, and an upstream conflict changes no installed version.

Record the two tags, CI/release run IDs, appcast SHA-256, installed versions,
signature output, and smoke-test results before considering public delivery
complete.

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
