#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Never installs over /Applications or uses the production app identity/save.
# Each build gets a fresh bundle; preview progress lives in its own Application Support folder.
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build
PTB_BIN_DIR=$(swift build --show-bin-path)
PTB_BIN_NAME=PokeForge
mkdir -p build
PTB_PREVIEW_DIR=$(mktemp -d "$PWD/build/gameplay-preview-XXXXXX")
PTB_PREVIEW_APP="$PTB_PREVIEW_DIR/PokeForge Gameplay Preview.app"
mkdir -p "$PTB_PREVIEW_APP/Contents/MacOS" "$PTB_PREVIEW_APP/Contents/Resources" "$PTB_PREVIEW_APP/Contents/Frameworks"
cp "$PTB_BIN_DIR/$PTB_BIN_NAME" "$PTB_PREVIEW_APP/Contents/MacOS/$PTB_BIN_NAME"
cp scripts/gameplay-preview/Info.plist "$PTB_PREVIEW_APP/Contents/Info.plist"
cp assets/AppIcon.icns "$PTB_PREVIEW_APP/Contents/Resources/AppIcon.icns"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$PTB_PREVIEW_APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$PTB_PREVIEW_APP"
codesign --verify --deep --strict "$PTB_PREVIEW_APP"
echo "Preview: $PTB_PREVIEW_APP"
if [[ "${PTB_PREVIEW_OPEN:-1}" == "1" ]]; then
    open "$PTB_PREVIEW_APP"
fi
