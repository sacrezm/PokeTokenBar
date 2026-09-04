# Pokémon progression — local playtest

This is a custom, token-driven fan-game loop, not a simulation of the main-series
capture or evolution formulas. Trainer battles and exploration are not implemented.

## Daily loop

1. **Catch**: your normal AI usage incubates an egg, raises its Pokémon through the
   existing evolution line, then keeps the completed individual and starts a new egg.
2. **Train**: select an owned Pokémon and an EV focus. New usage gives that individual
   experience and EVs; the catching/evolution meter pauses.
3. **Balanced**: half of new tokens catch and half train. Odd-token remainders persist,
   so frequent refreshes do not create or lose progress. If there is no eligible
   trainee, all tokens go to catching.

The wallet still earns actual observed usage once. Switching modes does not replay
past usage, and spending tokens never rewinds experience or collection progress.
No artificial AI calls or paid-token consumption are necessary to playtest.

## Levels and EVs

- Pokémon start at level 5. Existing saves keep their Pokémon, identities, nature,
  shininess and collection history; no historical EV investment is invented.
- Experience uses a shared Medium-Fast-style cubic curve: total XP = level³,
  capped at level 100. One thousand allocated tokens yield one XP, with carry.
- Catching also gives XP to the individual being raised, but no EVs. Training gives
  the chosen individual XP and one focused EV per 100,000 training tokens.
- Six EV stats: HP, Attack, Defense, Special Attack, Special Defense and Speed.
  Each stat caps at 252; the total caps at 510. EVs are saved investment for future
  battles, not invented combat stats. No IVs, moves, battle engine or multiplayer
  battle balance are included in this slice.
- Rare Candy adds exactly one level to the selected trainee, without EVs or
  catching progress. It cannot be spent at level 100.
- Evolution still follows the app's catching meter. Raising a level while training
  does not trigger a main-series level evolution in this version.

## Faster collecting

| Cost | Before | This playtest |
| --- | ---: | ---: |
| Egg incubation | 5M | 1M |
| Common completion | 750M | 75M |
| Uncommon completion | 1.875B | 187.5M |
| Rare completion | 3B | 300M |
| Legendary completion | 6B | 600M |

Completion cost excludes incubation. Balanced mode requires twice the actual usage
for the same catching progress. Overflow continues into the next egg; fetching a
species may wait for the next refresh when offline or while another hatch is loading.
Existing accumulated catching progress is retained against the reduced thresholds.

Rare Candy costs 5M, Mint 2M, and replacement eggs 10M / 25M / 40M. Replacement eggs
still **release the active Pokémon**, as in the original app; use the free completion
cycle to keep it instead. The shiny charm remains a long-term, permanent purchase.
Catch-up is bounded to four hatches per update; larger banks retain their remaining
tokens and continue on later refreshes.

## Optional balls

Basic hatching is free. Buy balls in Shop and equip one for the next egg. An untouched
egg can equip immediately; an egg that already has progress/equipment waits until
the next cycle. Equipping the next egg consumes one ball; it persists across restarts
and network failures. Changing a queued choice does not spend a ball.

Ball prices and exact effects are defined in `Core/CatchingBall.swift` and displayed
in the shop. Rarity bonuses are relative selection weights, not guaranteed species
or absolute catch percentages. No Master Ball or unsupported type-lure claims.
If the primary species index is unavailable, the existing REST fallback samples
base species differently. Ball rarity multipliers still apply, but absolute odds
and collection bias differ; unsuccessful sampling waits for a retry without
consuming another ball. A selected species is retained through line-fetch failures.

| Ball | Price | One-egg effect |
| --- | ---: | --- |
| Poké Ball | 1M | 20% fewer incubation tokens (800K) |
| Quick Ball | 2M | 60% fewer incubation tokens (400K) |
| Great Ball | 3M | 2× rare-or-better selection weight |
| Luxury Ball | 4M | Hatches at level 10, no EVs |
| Ultra Ball | 6M | 4× rare-or-better selection weight |

## Future battle seam

`PokemonProgression` is the pure, Codable progression module. The individual ID and
progression travel with the owned/trading data. Future battles can consume the
saved XP/EV values without implementing a battle engine in the collecting loop.
Received Pokémon train too; the trading ledger gates current ownership. A selected
individual that becomes unavailable does not silently redirect EVs to another.
Frozen/pending trade offers lock training, and new offers use the latest progression.
An older app build cannot be expected to preserve fields it does not understand;
use matching progression-capable builds for trades.

## Manual playtest

- Open Train, choose a Pokémon, change mode and EV focus, then check its XP/EVs
  after normal usage refreshes. Confirm the catching meter pauses in Train.
- Use one Rare Candy and check +1 level, no EV change, and one fewer candy.
- Choose Balanced and confirm both progress paths move.
- Buy a ball, equip it, restart, then check that the effect remains attached to
  the intended egg and consumes only one item.
- Open Collection → Owned → individual details to inspect level, XP and EVs.
- Finish a catching cycle and confirm the individual remains selectable for
  training while a fresh egg begins.

Run `./scripts/preview-gameplay.sh`. Preview progress persists in
`~/Library/Application Support/PokeTokenBar Gameplay Preview/companion-state.json`.
It uses a separate app identity and never starts usage scanning, trading, Keychain,
login-item migration or updater checks. The installed stable app/save is untouched.

## Verification (2026-09-04)

- Five workers contributed progression design, ball economy/critique, trading
  integration, native UI, and regression-test updates; the root integrated/reviewed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --enable-code-coverage`:
  995 tests, 10 existing environment/opt-in skips, zero failures.
- Debug sandbox and production (`swift build -c release`) builds both succeeded.
- Native sandbox click-through: Train XP/EVs, candy +1 level/no EV change, frozen
  catching meter in Train, Quick Ball purchase/equipment/400K threshold, Balanced
  allocation, hatch overflow, owned-individual details and save persistence.
- Disabled the new post-prefetch hatch continuation: the suspended-index test failed
  on hatch, overflow and ball consumption. Restored it; the full suite passed again.
- Offline paid-egg retry and failed-save rollback have dedicated integration tests.
- Default trainee is visibly selected and pinned when Train/Balanced is chosen;
  the empty picker label is a disabled placeholder, not a "train nobody" action.
- The existing REST fallback's different absolute odds are retained and disclosed
  above. No live relay mutation, release, push or installed-app replacement was done.
