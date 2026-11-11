#!/bin/bash
# Installs (or updates) Tessera from the latest GitHub release.
#
#   curl -fsSL https://demfier.github.io/tessera/install.sh | bash
#
# Files fetched with curl aren't marked "downloaded from the internet", so macOS doesn't stop
# Tessera on first launch the way it does for a browser download of an un-notarized app. To make
# up for skipping that check, this script refuses any app not signed with Tessera's own certificate.
set -euo pipefail

URL="https://github.com/Demfier/tessera/releases/latest/download/Tessera.zip"
# Hash of the "Tessera Self-Signed" certificate every release is signed with.
REQUIREMENT='identifier "me.laurelwood.tessera" and certificate leaf = H"d18ed2de4b7711966df5de47841af96ca0880552"'

fail() { echo "Tessera: $*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || fail "this installs a macOS app."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 14 )) || fail "needs macOS 14 or later (this Mac has $(sw_vers -productVersion))."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Downloading Tessera…"
curl -fL --progress-bar "$URL" -o "$work/Tessera.zip"
ditto -x -k "$work/Tessera.zip" "$work"
app="$work/Tessera.app"
[[ -d "$app" ]] || fail "the download didn't contain Tessera.app."
codesign --verify --strict -R="$REQUIREMENT" "$app" 2>/dev/null \
    || fail "the download isn't signed by Tessera's certificate; not installing it."

# /Applications is writable for admin accounts; otherwise install just for this user.
dest="/Applications"
[[ -w "$dest" ]] || { dest="$HOME/Applications"; mkdir -p "$dest"; }

if pgrep -x Tessera >/dev/null; then
    echo "Quitting the running copy…"
    pkill -x Tessera || true
    sleep 1
fi
rm -rf "$dest/Tessera.app"
ditto "$app" "$dest/Tessera.app"
xattr -dr com.apple.quarantine "$dest/Tessera.app" 2>/dev/null || true

echo "Installed $dest/Tessera.app. Opening it…"
open "$dest/Tessera.app"
echo "If this is your first install, turn Tessera on in System Settings › Privacy & Security › Accessibility."
