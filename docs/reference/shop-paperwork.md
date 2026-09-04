# Psyduck’s Paperwork

An optional shop comedy component, requested and implemented on 2026-09-04.

## Six-juror tribunal

Six independent Luna/max jurors proposed and challenged concepts before implementation:

| Juror | Role | Main contribution |
|---|---|---|
| Arendt | Absurdist comedian | Escalating interaction instead of a static pun; proposed an emergency button. |
| Boole | Deadpan writer | Psyduck’s unnecessary forms and meaningless stamped receipts. |
| Parfit | Pokémon-character specialist | Psyduck as a confused clerk; compared Magikarp and Slowpoke. |
| Socrates | Minimalist UX critic | Collapsed, opt-in row; no modal or automatic performance. |
| Bernoulli | Hostile comedy critic | Bureaucratic absurdity; reject token guilt, fake rewards and pun spam. |
| Mill | Implementation/safety reviewer | A standalone view-local value model with no gameplay dependencies. |

The root selected **Psyduck’s Paperwork**, combining the bureaucratic premise,
finite escalation and quiet presentation. This was a synthesis, not a unanimous
vote for one original pitch. Bernoulli and Mill reviewed the implementation;
their copy/accessibility feedback was incorporated.

## Interaction

- One 44pt collapsed row below the shop wallet: **Free nonsense. No game effects.**
- Click to reveal Psyduck and a fictional form.
- **Request review → Escalate → Stamp it anyway** produces an absurd certificate.
- **File another form** advances to the next of three stories:
  Ball Exists, Less Paperwork, and Missing Supervisor.
- Collapsing retains the current form while that shop view exists. A new view
  instance starts fresh; nothing is saved.

Examples:

> The second opinion is square. We have suspended geometry.

> Certified round. This certificate is rectangular. Please do not alert the committee.

> The chair has requested a standing desk. Psyduck has escalated the furniture.

## Boundaries

`ShopPaperwork` has no store, wallet, gameplay RNG, timer, network or persistence
dependency. `ShopPaperworkView` accepts no gameplay state and calls no store actions.
The portrait uses the existing static sprite loader/cache; no LLM calls, typewriter
effect, sound, confetti, purchase trigger or balance-dependent joke is involved.

No price, hatch odds, inventory, XP, EV, ownership or save-format changes are part
of this feature. The preceding economy audit remains a separate, unimplemented
set of findings. The initial authored comedy and accessibility copy is English;
translations are not claimed for this slice.

## Verification

- Six new tests cover the story transitions, deterministic wraparound, unique beats,
  10,000 repeated actions, the compact closed row and every form/stage at both
  332pt production width and 388pt preview content width.
- Full suite: 1,002 tests, 10 existing skips, zero failures.
- Model region coverage: 100%. Both expanded/closed and certificate branches are
  exercised by native layout tests; button callbacks are also checked in the app.
- Native click-through verified the full first story, certificate, next form,
  collapse/reopen and unchanged 30.1M displayed wallet. The isolated gameplay save’s
  SHA-256 was identical before and after the comedy interactions.
- Installed app/save untouched; preview uses its existing isolated sandbox.
