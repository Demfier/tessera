#!/bin/bash
# Builds Tessera.app. Usage: scripts/build.sh [--install] [--debug] [--release]
#   --install  copy to /Applications, replacing and relaunching any running copy
#   --debug    debug build (default: optimised)
#   --release  universal (Apple silicon + Intel) build, zipped to build/Tessera.zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
INSTALL=false
RELEASE=false
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --debug) CONFIG=debug ;;
        --release) RELEASE=true ;;
        *) echo "Unknown option: $arg" >&2; exit 64 ;;
    esac
done
if $RELEASE && [[ "$CONFIG" == debug ]]; then
    echo "--release and --debug don't mix" >&2
    exit 64
fi

ARCHS=()
$RELEASE && ARCHS=(--arch arm64 --arch x86_64)
APP=build/Tessera.app
swift build -c "$CONFIG" "${ARCHS[@]+"${ARCHS[@]}"}"
BIN="$(swift build -c "$CONFIG" "${ARCHS[@]+"${ARCHS[@]}"}" --show-bin-path)/Tessera"

[[ -f Resources/AppIcon.icns ]] || swift scripts/make-icon.swift Resources/AppIcon.icns

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tessera"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Accessibility permission is tied to the code signature, so sign with one stable identity:
#   1. $TESSERA_SIGN_IDENTITY, if set
#   2. "Tessera Self-Signed" (scripts/make-signing-identity.sh) — what published releases use
#   3. an Apple Development / Developer ID certificate
#   4. ad-hoc, which changes every build and forces an Accessibility re-grant each time
SELF_SIGNED="Tessera Self-Signed"
IDENTITY="${TESSERA_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]] && security find-certificate -c "$SELF_SIGNED" >/dev/null 2>&1; then
    IDENTITY="$SELF_SIGNED"
fi
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }')"
fi
if [[ -n "$IDENTITY" ]]; then
    codesign --force --options runtime --sign "$IDENTITY" "$APP"
elif $RELEASE; then
    echo "error: releases need a stable signature; run scripts/make-signing-identity.sh first" >&2
    exit 1
else
    echo "warning: no signing identity found; signing ad-hoc (re-grant Accessibility after each rebuild)" >&2
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"

if $RELEASE; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
    # A fixed name, so .../releases/latest/download/Tessera.zip always points at the newest release.
    ZIP="build/Tessera.zip"
    rm -f "$ZIP"
    # ditto keeps the bundle's signature and metadata intact; plain `zip` can break it.
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Packaged $ZIP: version $VERSION ($(lipo -archs "$APP/Contents/MacOS/Tessera"))"
    shasum -a 256 "$ZIP"
fi

if $INSTALL; then
    pkill -x Tessera 2>/dev/null && sleep 0.5 || true
    rm -rf /Applications/Tessera.app
    cp -R "$APP" /Applications/Tessera.app
    open /Applications/Tessera.app
    echo "Installed and launched /Applications/Tessera.app"
fi
