# Releasing PokéForge

PokéForge is an independently maintained fork of [PokeTokenBar](https://github.com/chattymin/PokeTokenBar).
Releases belong to **sacrezm/pokeforge**. The original project's Homebrew tap and
website do not distribute PokéForge.

Use the [release workflow](docs/reference/release-workflow.md) for the complete
signing, verification and publication procedure. Run it from a clean, pushed
`main` checkout on the Mac with the existing signing identity:

```bash
CODESIGN_IDENTITY="Your existing signing identity" \
PTB_SPARKLE_KEY_REF="op://AI/PokeTokenBar Sparkle update signing/password" \
./scripts/release.sh <major.minor.patch>
```

Choose a version higher than the current release. The script runs the test gate,
builds a universal app, verifies its signature, and publishes `PokeForge-v<version>.zip`
with a signed `appcast.xml`. It does not install the app on the release machine.

Before publishing:

- Update the README and translations to describe what actually ships. Keep future
  trainer battles and unfinished progression work labelled as planned.
- Review release notes and screenshots for accuracy, including fork attribution.
- Run the isolated updater smoke test when changing updater or packaging behavior.
- Keep the existing signing certificate, Sparkle public key, bundle identifier,
  save format and trainer credentials. Rebranding must not reset a collection.

For the first PokéForge release, include the [manual upgrade instructions](docs/reference/pokeforge-identity.md).
Older PokeTokenBar builds cannot discover the renamed repository because they
validate the old URL exactly. Existing release assets keep their original names;
do not rewrite signed archives or signed feeds from past releases.
