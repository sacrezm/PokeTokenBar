#!/bin/bash
# Real signed download -> replacement -> relaunch, without loading any user data.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${PTB_SPARKLE_KEY_REF:?Use the existing 1Password signing reference}"
: "${CODESIGN_IDENTITY:?Use the existing signing identity}"
[[ "$PTB_SPARKLE_KEY_REF" == op://* ]]
PORT=18763
if lsof -iTCP:$PORT -sTCP:LISTEN -t >/dev/null; then
    echo "Test port $PORT is busy; no process was stopped" >&2; exit 1
fi
RUN_DIR="$(mktemp -d "$PWD/Scratch/updater-smoke-XXXXXXXX")"
echo "Updater smoke artifacts: $RUN_DIR"
FRAMEWORK_ROOT="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin"
APP="$RUN_DIR/Installed/UpdaterSmoke.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$RUN_DIR/feed"
ditto "$FRAMEWORK_ROOT/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
ditto scripts/updater-smoke/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set SUPublicEDKey $(tr -d '\r\n' < scripts/sparkle-public-key.txt)" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set PTBSmokeResultPath $RUN_DIR/relaunched.txt" "$APP/Contents/Info.plist"
INSTALLER="${PTB_SMOKE_INSTALLER:-Sources/PokeTokenBar/Core/SparkleInstaller.swift}"
swiftc -F "$FRAMEWORK_ROOT" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "$INSTALLER" scripts/updater-smoke/main.swift -o "$APP/Contents/MacOS/UpdaterSmoke"
codesign --force -s "$CODESIGN_IDENTITY" "$APP"
ditto "$APP" "$RUN_DIR/feed/UpdaterSmoke.app"
/usr/libexec/PlistBuddy -c 'Set CFBundleVersion 2.0.0' "$RUN_DIR/feed/UpdaterSmoke.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set CFBundleShortVersionString 2.0.0' "$RUN_DIR/feed/UpdaterSmoke.app/Contents/Info.plist"
codesign --force -s "$CODESIGN_IDENTITY" "$RUN_DIR/feed/UpdaterSmoke.app"
ditto -c -k --keepParent "$RUN_DIR/feed/UpdaterSmoke.app" "$RUN_DIR/feed/UpdaterSmoke-2.0.0.zip"
op read "$PTB_SPARKLE_KEY_REF" | "$TOOLS/generate_appcast" --ed-key-file - \
    --maximum-deltas 0 --download-url-prefix "http://127.0.0.1:$PORT/" "$RUN_DIR/feed"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$RUN_DIR/feed" >"$RUN_DIR/http.log" 2>&1 &
SERVER_PID=$!
APP_PID=''
trap 'kill "$SERVER_PID" 2>/dev/null || true; if [[ -n "$APP_PID" ]]; then kill "$APP_PID" 2>/dev/null || true; fi' EXIT
for attempt in {1..40}; do
    if curl -fsS "http://127.0.0.1:$PORT/appcast.xml" >/dev/null 2>&1; then break; fi
    sleep 0.1
done
"$APP/Contents/MacOS/UpdaterSmoke" >"$RUN_DIR/app.log" 2>&1 &
APP_PID=$!
for ((attempt=0; attempt<${PTB_SMOKE_TIMEOUT:-90}; attempt++)); do
    if [[ -f "$RUN_DIR/relaunched.txt" ]]; then
        [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")" == 2.0.0 ]]
        codesign --verify --deep --strict "$APP"
        echo 'PASS: one click downloaded, verified, installed and relaunched version 2.0.0'
        exit 0
    fi
    sleep 1
done
echo 'FAIL: no completed installation/relaunch; inspect app.log and http.log in the printed directory' >&2
exit 1
