# Trading fork releases

This fork uses GitHub Releases in **sacrezm/PokeTokenBar**. No upstream tap,
Pages deployment, update server, or CI signing secrets are needed.

## Publish

Commit and push the intended changes to this fork's `main`, then run on the
Mac that holds the existing signing identity:

```bash
CODESIGN_IDENTITY="Your existing signing identity" ./scripts/release.sh 2.6.0
```

Replace the identity placeholder with the existing fork signing identity and the
example version with a higher major.minor.patch. Other release machines must
securely have the **same certificate and private key**, not create a replacement
with the same name. Never put private keys or certificates containing private keys in Git.

The command checks the clean checkout and exact origin, runs the full test gate,
bumps the bundled version, builds a universal Apple Silicon + Intel app, verifies
its stable signature, and packages a ZIP. It then commits/pushes only the version
bump, creates a draft release with the ZIP, and publishes it as Latest. It does
not install the build or interrupt the running app. A build/test failure does
not publish. A failure after creating the draft leaves it unpublished: inspect
the existing draft and attached ZIP before publishing or retrying.

There is no new Apple Developer enrollment/notarization setup here: releases
remain self-signed like the current fork. Downloaded apps may require explicit
approval in macOS Privacy & Security. Stable signing is not Apple notarization.

## User flow

The installed app checks the fork's latest stable release at launch and on
popover opening, throttled to 30 minutes. Its existing banner opens the release.
Users quit, replace the app in Applications, and reopen. Saves and trainer
credentials are not part of the app ZIP and are not replaced. Settings offers a
manual check, including skipped versions, and distinguishes failed checks from
"up to date".

Old builds that still point at upstream need one manual installation of the new
fork-channel build. Do not use upstream Homebrew upgrade; it removes trading.

## Verify a published release

- Confirm the release is public, not a draft/prerelease, with the built app ZIP.
- Check its version matches the app's CFBundleShortVersionString.
- On an older fork-channel build, use Settings → Updates → Check now.
- Follow Download and confirm it opens this fork, not upstream.
- Quit and replace the app; check the version and retained collection on restart.

GitHub documentation: [Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
and [latest-release API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release).
