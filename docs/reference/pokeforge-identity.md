# PokéForge identity and upgrade notes

PokéForge is an independently maintained fork of
[chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar), maintained at
[sacrezm/pokeforge](https://github.com/sacrezm/pokeforge). The original MIT copyright
notice remains in `LICENSE`. A separate GitHub repository does not erase that
source provenance.

## Public identity

| Surface | Name |
| --- | --- |
| App display name | PokéForge |
| Repository | `sacrezm/pokeforge` |
| App bundle and executable | `PokeForge.app`, `PokeForge` |
| Swift package / executable product | `PokeForge` |
| New release archives | `PokeForge-v<version>.zip` |
| Support | Issues in `sacrezm/pokeforge` |

## Upgrade from PokeTokenBar

The repository rename does not publish a new binary. Existing release ZIPs still
contain `PokeTokenBar.app`; use the release notes to identify the first branded
`PokeForge` archive, or build the current source.

Previously released builds, including 2.6.3, require release metadata to contain
the exact old repository URL. GitHub redirects the old URL, but returns the new
canonical release URL, which those binaries reject. **Install the first PokéForge
release manually once.** New builds check `sacrezm/pokeforge` and use its signed
Sparkle update feed. An old app cannot be patched by changing source code alone.

1. Export a save from the old app if desired. Turn off its **Launch at login** setting.
2. Quit PokeTokenBar normally, so its crash watchdog does not restart it.
3. Move the downloaded `PokeForge.app` to `/Applications` and open it.
4. Verify the collection, trainer profile and preferences, then enable **Launch at login**
   in PokéForge if desired.
5. Remove the old app bundle after verifying the new one. Do not use an app cleaner
   that deletes Application Support, preferences or Keychain records.

Both app names share the same persisted identity. Do not run upstream PokeTokenBar
and PokéForge as separate installations against the same data. The existing
single-instance guard uses the retained bundle identifier.

## Deliberately retained compatibility identifiers

These are not active product branding. Renaming them mechanically would require
a separate, verified data or infrastructure migration:

- `~/Library/Application Support/PokeTokenBar/`: Pokémon, trading sidecars and caches.
- `~/Library/Logs/PokeTokenBar.log` and related crash markers: existing diagnostics.
- `io.github.chattymin.poketokenbar`: bundle/preferences identity; its `.login`
  LaunchAgent label remains stable. New launch entries point at `PokeForge`.
- `com.chattymin.PokeTokenBar.trading.v1` and `PokeTokenBar.trading.*`: Keychain and
  saved trainer state. These must continue to find existing trainer credentials.
- `poketokenbar.save`: exported save format identifier. New export filenames use
  `PokeForge-Save-…`, while existing saves remain readable.
- The existing signing certificate, `PokeTokenBar Local` fallback identity and
  1Password item names: changing a name is not a reason to regenerate signing keys.
- `poketokenbar-trade-server` and its deployed Workers URL: the existing relay
  contains trainer/friendship state. This rebrand does not create or deploy a replacement.
- `Sources/PokeTokenBar`, `Tests/PokeTokenBarTests` and the `PokeTokenBar` Swift
  module: stable internal paths for upstream integration and concurrent gameplay work.
- `PTB_*` developer environment variables and internal protocol/notification keys:
  existing scripts and clients still use them.

Historical upstream references, attribution, test fixtures and already published
signed release assets also retain their original names. Keep `origin` pointed at
PokéForge and `upstream` pointed at the original repository. The active checkout
directory may retain its old name while other tasks are using it.
