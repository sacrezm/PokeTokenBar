#!/usr/bin/env bash
# Publish this trading fork from a clean, pushed main checkout on the signing Mac.
# CODESIGN_IDENTITY="Your existing signing identity" ./scripts/release.sh 2.6.0
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="sacrezm/PokeTokenBar"
VERSION="${1:?Usage: release.sh <major.minor.patch>}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version"; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { echo "Run on main"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit and push your changes first"; exit 1; }
case "$(git remote get-url origin)" in
  "https://github.com/$REPO.git"|"git@github.com:$REPO.git") ;;
  *) echo "origin must be $REPO; refusing to publish elsewhere"; exit 1 ;;
esac
REMOTE_HEAD=$(git ls-remote origin refs/heads/main | cut -f1)
[[ "$(git rev-parse HEAD)" == "$REMOTE_HEAD" ]] || { echo "Sync main with origin first"; exit 1; }
PREVIOUS=$(sed -nE 's/^VERSION="\$\{PTB_VERSION:-([0-9.]+)\}"/\1/p' scripts/build-app.sh)
[[ "$PREVIOUS" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Cannot read current version"; exit 1; }
[[ -z "$(git ls-remote origin "refs/tags/v$VERSION")" ]] || { echo "Tag already exists; choose a new version"; exit 1; }
# Numeric comparison, not lexical (2.5.10 is newer than 2.5.9).
awk -v a="$VERSION" -v b="$PREVIOUS" 'BEGIN {
  split(a,x,"."); split(b,y,".");
  for(i=1;i<=3;i++) { if(x[i]+0>y[i]+0) exit 0; if(x[i]+0<y[i]+0) exit 1 }
  exit 1
}' || { echo "Version must be newer than $PREVIOUS"; exit 1; }
: "${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to the same identity used for previous fork builds}"
security find-identity -v -p codesigning | grep -F "\"$CODESIGN_IDENTITY\"" >/dev/null \
  || { echo "Signing identity unavailable; no ad-hoc releases"; exit 1; }
gh repo view "$REPO" --json visibility --jq .visibility | grep -qx PUBLIC \
  || { echo "Public releases are required for unauthenticated update checks"; exit 1; }
if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release already exists; choose a new version"; exit 1
fi

echo "Testing and building v$VERSION. No app installation or save changes."
./scripts/test-gate.sh
# Only the version default is changed; a failed build leaves it uncommitted for inspection.
perl -pi -e "s/PTB_VERSION:-[0-9.]+/PTB_VERSION:-$VERSION/" scripts/build-app.sh
PTB_INSTALL=0 PTB_UNIVERSAL=1 PTB_REQUIRE_STABLE_SIGN=1 PTB_VERSION="$VERSION" ./scripts/build-app.sh
APP="build/PokeTokenBar.app"
BUILT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
[[ "$BUILT" == "$VERSION" ]] || { echo "Built version mismatch"; exit 1; }
codesign --verify --strict "$APP"
lipo "$APP/Contents/MacOS/PokeTokenBar" -verify_arch arm64 x86_64
ZIP="build/PokeTokenBar-v$VERSION.zip"
[[ ! -e "$ZIP" ]] || { echo "$ZIP already exists; inspect it before retrying"; exit 1; }
ditto -c -k --keepParent "$APP" "$ZIP"

git add scripts/build-app.sh
git commit -m "release: trading fork v$VERSION"
git push origin main
# A draft prevents update alerts before the binary upload completes.
gh release create "v$VERSION" "$ZIP" --repo "$REPO" --target "$(git rev-parse HEAD)" \
  --draft --title "PokeTokenBar Trading v$VERSION" --generate-notes
gh release edit "v$VERSION" --repo "$REPO" --draft=false --latest
echo "Published https://github.com/$REPO/releases/tag/v$VERSION"
