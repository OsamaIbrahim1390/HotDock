#!/bin/bash
#
# HotDock build script.
#
#   ./make.sh build      compile and assemble build/HotDock.app
#   ./make.sh run         build, then (re)launch it
#   ./make.sh stop        quit a running instance
#   ./make.sh clean       remove build products
#   ./make.sh install     copy build/HotDock.app to /Applications
#   ./make.sh identity    show which code-signing identity would be used
#   ./make.sh dmg         build a release .app and package it as dist/HotDock-<version>.dmg
#
# Set HOTDOCK_CONFIG=release for an optimised build.
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="HotDock"
CONFIG="${HOTDOCK_CONFIG:-debug}"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

# A stable signing identity keeps macOS privacy permissions (Accessibility, Apple Events,
# Screen Recording) attached to the app across rebuilds. Ad-hoc signatures change every
# build, so macOS treats each build as a different app and re-asks.
find_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1
}

cmd_identity() {
    local id; id="$(find_identity || true)"
    if [ -n "$id" ]; then
        echo "Signing identity: $id"
    else
        echo "No 'Apple Development' identity found; builds will be ad-hoc signed."
        echo "To fix: Xcode > Settings > Accounts > + > Apple ID (free account is enough)."
    fi
}

cmd_build() {
    echo "==> swift build ($CONFIG)"
    swift build --configuration "$CONFIG"
    local bin; bin="$(swift build --configuration "$CONFIG" --show-bin-path)"

    echo "==> assembling $APP"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$bin/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
    cp Resources/Info.plist "$APP/Contents/Info.plist"
    printf 'APPL????' > "$APP/Contents/PkgInfo"
    # Copy any bundled resources SPM produced (none yet, but keeps the script honest).
    for b in "$bin"/*.bundle; do
        [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/" || true
    done

    local id; id="$(find_identity || true)"
    if [ -n "$id" ]; then
        echo "==> codesign with: $id"
        codesign --force --sign "$id" --timestamp=none --options runtime "$APP"
    else
        echo "==> codesign ad-hoc (no Apple Development identity found)"
        echo "    macOS may re-ask for permissions after each rebuild. See './make.sh identity'."
        codesign --force --sign - "$APP"
    fi
    codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'
    echo "==> built $APP"
}

cmd_stop() {
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        echo "==> quitting running $APP_NAME"
        osascript -e "tell application id \"com.hotdock.HotDock\" to quit" 2>/dev/null || pkill -x "$APP_NAME" || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
            sleep 0.2
        done
        pkill -x "$APP_NAME" 2>/dev/null || true
    fi
}

cmd_run() {
    cmd_build
    cmd_stop
    echo "==> launching"
    open "$APP"
    sleep 1
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        echo "==> running (pid $(pgrep -x "$APP_NAME" | head -1))"
    else
        echo "!! did not stay running. Recent log lines:"
        log show --last 1m --predicate 'process == "HotDock"' --style compact 2>/dev/null | tail -30
        exit 1
    fi
}

cmd_clean() { rm -rf "$BUILD_DIR" .build; echo "==> cleaned"; }

cmd_install() {
    cmd_build
    cmd_stop
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/"
    echo "==> installed to /Applications/$APP_NAME.app"
}

# Packages the app as a disk image for people to download.
#
# Honest note about what this does and does not get you: the result is signed with whatever
# identity this Mac has, and it is NOT notarized — notarization needs a paid Apple Developer
# account. macOS will therefore refuse to open it on first launch with "Apple could not verify
# ... is free of malware". The README explains the right-click > Open workaround that users
# have to do once. There is no way around that without the paid account.
cmd_dmg() {
    HOTDOCK_CONFIG=release
    CONFIG=release
    cmd_build

    local version staging dmg
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
    dmg="$BUILD_DIR/../dist/$APP_NAME-$version.dmg"
    mkdir -p "$(dirname "$dmg")"
    rm -f "$dmg"

    staging="$(mktemp -d)"
    cp -R "$APP" "$staging/"
    # The familiar drag-to-install layout.
    ln -s /Applications "$staging/Applications"

    echo "==> building $dmg"
    hdiutil create -volname "$APP_NAME $version" \
        -srcfolder "$staging" -ov -format UDZO -quiet "$dmg"
    rm -rf "$staging"

    echo "==> $dmg ($(du -h "$dmg" | cut -f1))"
    shasum -a 256 "$dmg"
    if [ -z "$(find_identity || true)" ]; then
        echo
        echo "NOTE: ad-hoc signed and not notarized. Anyone downloading this will need to"
        echo "      right-click the app and choose Open the first time. See the README."
    fi
}

case "${1:-build}" in
    build)    cmd_build ;;
    run)      cmd_run ;;
    stop)     cmd_stop ;;
    clean)    cmd_clean ;;
    install)  cmd_install ;;
    identity) cmd_identity ;;
    dmg)      cmd_dmg ;;
    *) echo "usage: ./make.sh [build|run|stop|clean|install|identity|dmg]"; exit 2 ;;
esac
