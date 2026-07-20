# HSTracker Arena

This personal fork of
[HearthSim/HSTracker](https://github.com/HearthSim/HSTracker) adds public
HearthArena base tier-list scores to ordinary Arena draft offers. It does not
reproduce HearthArena's private dynamic synergy advice and is not affiliated
with HearthArena, HearthSim, or Blizzard.

See [HEARTHARENA.md](HEARTHARENA.md) for the architecture, build commands,
backup procedure, tests, and manual Arena smoke-test matrix. Current
requirement-by-requirement evidence and remaining gates are tracked in
[HEARTHARENA-AUDIT.md](HEARTHARENA-AUDIT.md).

## Installation
- Requirements:
  - macOS 10.14 or higher
  - Full Xcode for local development builds
  - For Windows support please look at [**Hearthstone Deck Tracker**](https://github.com/HearthSim/Hearthstone-Deck-Tracker/)
- No proven HSTracker Arena binary release is published yet. Until the first
  signed N → N+1 update test is complete, build this repository with the
  commands in [HEARTHARENA.md](HEARTHARENA.md).
- Do not use the official HSTracker download link when you expect the
  HearthArena overlay; the official application does not contain this fork's
  feature.
- Move `HSTracker Arena.app` to your `Applications` directory.
- Launch HSTracker Arena before Hearthstone.
- Create a new deck from the Deck Manager or import it from a deckstring. HSTracker will also auto-detect the deck you play with.

## Updates and automation

The app contains pinned Sparkle 2.9.2 and checks only the fork-owned signed
feed at `https://serge-ml.github.io/HSTracker/appcast.xml`. Automatic checks are
off by default; use `Check for Updates…` or Preferences → Updates.

Pull requests and default-branch pushes run full core tests plus unsigned Debug
and Release builds. A successful default-branch CI artifact can then enter the
protected release workflow for signing, optional notarization, GitHub Release
publication, and atomic appcast publication. Upstream HSTracker changes arrive
through review PRs and cannot bypass required checks.

Repository setup, secret scopes, manual workflow controls, rollback, key
rotation, signature checks, and the required two-version acceptance test are
documented in [HEARTHARENA.md](HEARTHARENA.md#delivery-operations).


## Community & Troubleshooting
- Join the Community Discord: [![Join HearthSim Community Discord](https://discordapp.com/api/guilds/265636998700728321/widget.png)](https://discord.gg/hearthsim)
- [Follow HSTracker on Twitter](https://twitter.com/hstracker_mac)
- HSReplay.net integration: Please email <support@hsdecktracker.net> for support.


## Contributing
- Please read the [contributing guidelines](https://github.com/HearthSim/HSTracker/blob/master/CONTRIBUTING.md).
- Developer Discord: [![Join HearthSim #hstracker](https://img.shields.io/badge/discord-join%20chat-blue.svg)](https://discord.gg/hearthsim-devs)
- HSTracker is a [HearthSim](https://hearthsim.info) project.


## Features
### Deck Tracker
![Deck Tracker](https://github.com/HearthSim/HSTracker/blob/master/hstracker.jpg)

### Deck Manager
![Deck Manager](https://github.com/HearthSim/HSTracker/blob/master/manager.jpg)


### HSReplay.net Integration
HSTracker uploads your games to [HSReplay.net](https://hsreplay.net).


## License
HSTracker is released under the [MIT license](LICENSE).

All Hearthstone assets are copyright © Blizzard Entertainment.
