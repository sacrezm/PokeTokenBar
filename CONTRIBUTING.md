# Contributing to PokéForge

[English](CONTRIBUTING.md) · [한국어](CONTRIBUTING.ko.md) · [日本語](CONTRIBUTING.ja.md)

PokéForge is an independently maintained, non-commercial fan project and a fork of [chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar). The original MIT copyright notice remains in [LICENSE](LICENSE). Contributions are maintained in [sacrezm/pokeforge](https://github.com/sacrezm/pokeforge).

## Before you start

- macOS 14 (Sonoma) or newer
- Swift 6 / Xcode 16 or newer (`swift-tools-version: 6.0`)

The public product name is PokéForge. The Swift package product and app bundle use `PokeForge`, while the target/module and source paths remain `PokeTokenBar` and `Sources/PokeTokenBar` for compatibility. Do not rename those internal paths mechanically; see [the identity notes](docs/reference/pokeforge-identity.md).

For a local checkout, keep the remotes explicit:

```text
origin   https://github.com/sacrezm/pokeforge.git
upstream https://github.com/chattymin/PokeTokenBar.git
```

## Build and test

From the repository root:

```bash
swift build
swift test

# Optional release bundle; build/PokeForge.app, no installation
PTB_INSTALL=0 ./scripts/build-app.sh
```

The bundle script creates `PokeForge.app`; with `PTB_INSTALL=0` it does not install it. Without that variable it replaces `/Applications/PokeForge.app` after stopping the running app. CI runs `swift build`, the test and coverage gate in `scripts/test-gate.sh`, and a secret scan.

## Contribution workflow

1. Create a focused branch from `main`.
2. Make the smallest change that solves the problem and add meaningful tests where behavior changes.
3. Use a Conventional Commit prefix such as `feat:`, `fix:`, `docs:`, `test:`, or `refactor:`.
4. Open a pull request against `main` with an English title and description.
5. Describe before and after for UI changes under `Sources/PokeTokenBar/UI/`; screenshots are optional.

Pull requests and commit messages use English first so the public history stays consistent. Fill out the pull request template and report the macOS version, app version, affected AI tool, and reproduction steps for bugs.

## Code conventions

- **New usage source:** implement `UsageProvider` in `Sources/PokeTokenBar/Core/` and register it in the default provider list in `Sources/PokeTokenBar/Core/UsageStore.swift`.
- **Generic usage behavior:** aggregate across providers. Provider-specific branches are reserved for provider-specific limits or behavior.
- **New tool or version-manager path:** add it to `BinaryLocator.commonToolDirectories()`, the shared discovery and child-process `PATH` source.
- **Append-only SQLite usage:** use `LocalAdditionalUsageReader.scanIncrementalStores` with the format-specific query and parser instead of copying the watermark loop.
- **Roadmap clarity:** keep in-development levels, XP/EV systems, catching/training modes, and trainer battles clearly separate from shipped behavior until they are implemented and verified.

## Legal and privacy boundaries

Do not commit or bundle Pokémon or other third-party copyrighted assets, including sprites, artwork, audio, fonts, or bulk name/data files. Pokémon species data and sprites are fetched at runtime from [PokéAPI](https://pokeapi.co/) and cached locally.

Do not commit secrets, credentials, private tooling references, or features intended for commercial use. Trading is an optional relay-backed feature: Pokémon offers are encrypted on the client, while trainer, friend, and trade metadata is visible to the selected relay. Keep that boundary clear in code and documentation.

By contributing, you confirm that your work is original and may be distributed under this project's [MIT License](LICENSE). That license covers this project's source code only; it grants no rights to third-party Pokémon intellectual property.
