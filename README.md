<div align="center">

<img src="assets/icon.png" width="112" alt="PokéForge icon">

# PokéForge

**Turn AI coding into Pokémon progress.**

Track the tokens your coding tools already use, raise a companion in your macOS menu bar, and grow a collection while you work.

[Releases](https://github.com/sacrezm/pokeforge/releases) · [Source](https://github.com/sacrezm/pokeforge) · [Contributing](CONTRIBUTING.md)

[English](README.md) · [한국어](README.ko.md) · [日本語](README.ja.md)

</div>

> **Fork provenance:** PokéForge is an independently maintained fork of [chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar). The original project's MIT copyright notice remains in [LICENSE](LICENSE), and this fork is maintained at [sacrezm/pokeforge](https://github.com/sacrezm/pokeforge).

## Your work, your team

**Code → hatch → raise → collect or trade → start again.**

PokéForge turns the AI tokens you already use into progress for your Pokémon. Keep a favorite beside you while you work, grow your collection, and trade with friends.

## What ships today

- **Usage tracking.** Read local usage records from Claude Code, Codex, Gemini CLI, Antigravity, OpenCode, Hermes Agent, Cursor, Grok CLI, Copilot CLI, Kiro CLI, Pi Agent, and omp. See today, week, and month totals, reported cost where available, and supported official limit windows.
- **Hatching and evolution.** Coding usage incubates an egg, grows a companion through its real evolution line, and graduates completed Pokémon into your collection. Hatches can have rarity, nature, and shiny status.
- **Shop.** Turn used tokens into Rare Candy, Mints, a Shiny Charm, or a fresh egg with optional Uncommon or Rare guarantees.
- **Collection.** Browse currently owned Pokémon, a species-level Pokédex, and the individual catch log. An optional floating pet and menu-bar representative keep a favorite visible while you work.
- **Trading.** Create a trainer, add a friend by code, and exchange one graduated Pokémon through a shared relay. Both players confirm; Original Trainer identity is retained, and supported trade evolutions apply when a Pokémon is received. Eggs and the active companion cannot be traded.

## What this fork changes

PokeTokenBar provides the original menu-bar companion, usage tracking, hatching, evolution, shop, and Pokédex. PokéForge builds on that foundation with:

| Addition | What it brings |
| --- | --- |
| Friends and remote trading | Friend codes, mutually confirmed trades, Original Trainer records, and supported trade evolutions. |
| Owned collection | Individual Pokémon ownership, received Pokémon, and detail pages alongside the historical Pokédex and catch log. |
| Hatch preferences | Choose which of Gen 1–5 can appear in future hatches. |
| Independent distribution | PokéForge releases, signed in-app updates, and support in this repository. |

The original author and contributors retain credit for the foundation. Fork-specific issues and contributions belong here.

## Where we’re going

**In development:** Pokémon levels, XP, EV training, dedicated catching and training modes, and a faster collection loop with more ball choices.

**Later:** Pokémon battles against other trainers, giving the team you have raised a new purpose.

These features are not available in the current release. Trading works today; battles are a future milestone.

## Screenshots

A look at the companion, shop, and Pokédex. Screenshots are from before the PokéForge rebrand, so some labels still use the original name.

<p align="center">
  <img src="assets/screenshot-home.gif" width="360" alt="Pre-rebrand home view with companion and usage totals">
</p>

<p align="center">
  <img src="assets/screenshot-shop.png" width="250" alt="Pre-rebrand Shop view with token-funded items and eggs">
  <img src="assets/screenshot-collection-pokedex.png" width="250" alt="Pre-rebrand Pokédex view">
</p>

## Install

Download app archives from the [PokéForge releases](https://github.com/sacrezm/pokeforge/releases). Use the built app ZIP, not GitHub's automatically generated source archive. Unzip it and move the app inside to `/Applications`.

This rename does not publish a new binary. The latest existing download remains `PokeTokenBar-v2.6.3.zip` and contains `PokeTokenBar.app`. The first branded release will be `PokeForge-vX.Y.Z.zip`, containing `PokeForge.app`.

Releases use a stable self-signed certificate and are not Apple-notarized. If macOS blocks the first launch, use its **Privacy & Security → Open Anyway** flow for the app you downloaded from this repository.

### Moving from PokeTokenBar

Existing PokeTokenBar builds, including v2.6.3, cannot discover updates after the repository rename. **Install the first PokéForge release manually once.** Subsequent updates use PokéForge’s signed in-app update flow.

1. In the old PokeTokenBar app, turn off **Launch at login**.
2. Quit PokeTokenBar normally so its crash watchdog does not restart it.
3. Download the first `PokeForge-vX.Y.Z.zip`, move `PokeForge.app` to `/Applications`, and open it.
4. Verify your collection, trainer profile, and preferences, then enable **Launch at login** in PokéForge if you want it.
5. Remove the old app bundle after verification. Do not use an app cleaner that deletes Application Support, preferences, or Keychain records.

Do not run the old PokeTokenBar app and PokéForge as separate installations against the same data. See [the identity and upgrade notes](docs/reference/pokeforge-identity.md) for the complete compatibility boundary.

## Build from source

For macOS 14 or newer with Swift 6 and Xcode 16 or newer:

```bash
git clone https://github.com/sacrezm/pokeforge.git
cd pokeforge
swift build
swift test

# Release bundle in build/PokeForge.app; do not install it
PTB_INSTALL=0 ./scripts/build-app.sh

# Release bundle, then stop the running app and install it in /Applications
./scripts/build-app.sh
```

`scripts/build-app.sh` assembles and verifies the signed app bundle. By default it replaces `/Applications/PokeForge.app`; `PTB_INSTALL=0` builds without installing. Quit the old PokeTokenBar app first, following the migration steps above. Developer builds may fall back to ad-hoc signing; published releases require the existing stable signing identity.

### Your existing collection

PokéForge keeps the existing save locations, trainer credentials, and preferences. Some internal identifiers and historical releases retain the PokeTokenBar name for compatibility. The [identity notes](docs/reference/pokeforge-identity.md) explain these choices for contributors.

## Privacy and trading

Usage aggregation reads your AI tools' local logs or databases. The app does not send usage logs, prompts, or project paths to the trading relay. Some provider integrations make network requests for official limits or account usage, and the app contacts GitHub for release checks and downloads.

Optional Claude session-key mode stores the supplied credential in a local file with owner-only permissions, rather than Keychain. This is separate from trading credentials.

Pokémon species, evolution data, and sprites are fetched at runtime and cached locally; Pokémon assets are not bundled in the app or release archives.

Trading is opt-in and relay-based. The relay receives the trainer profile, friend code, public key, and friendship/trade metadata. Pokémon offers are encrypted on this Mac before transmission, but relay-visible metadata can still be stored by the relay. Trading private keys and bearer credentials stay in macOS Keychain. Use only a relay you trust.

## License and disclaimer

The original project source and this fork are released under the [MIT License](LICENSE); the original `chattymin` copyright notice is retained. MIT covers this project's source code and grants no rights to Pokémon trademarks, artwork, sprites, or data.

PokéForge is an unofficial, non-commercial fan project. It is not affiliated with, endorsed by, or sponsored by Nintendo, Game Freak, Creatures Inc., or The Pokémon Company. Pokémon data and sprites are fetched at runtime from [PokéAPI](https://pokeapi.co/) and remain the property of their respective owners.

See [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request.
