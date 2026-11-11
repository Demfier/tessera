# Tessera

One menu-bar app that replaces three. **Website and download: <https://demfier.github.io/tessera/>**

| Replaces | What Tessera does |
|---|---|
| **Rectangle** | Snap the focused window to halves, corners, thirds, fourths, sixths; maximize, center, grow/shrink, restore, move to an edge. Pressing a shortcut again moves the window across displays (or cycles sizes; your choice). |
| **InstantSpaceSwitcher** | Switch Spaces with no slide animation, so the pointer is usable immediately. Optionally makes three-finger trackpad swipes instant too. |
| **Second Display Pro** (window moving) | ⌃⌥⌘+arrow sends the window to the display on that side. **Full-screen apps move too**: Tessera exits full screen, moves the window, and re-enters full screen on the other display. Windows go back to a display when it reconnects. |

## Default shortcuts

| Action | Shortcut |
|---|---|
| Left / Right / Top / Bottom half | ⌃⌥ ← → ↑ ↓ |
| Top-left / Top-right / Bottom-left / Bottom-right | ⌃⌥ U I J K |
| First / Center / Last third | ⌃⌥ D F G |
| First / Last two thirds | ⌃⌥ E T |
| Maximize / Maximize height | ⌃⌥ ↩ / ⌃⌥⇧ ↑ |
| Center / Larger / Smaller / Restore | ⌃⌥ C = - ⌫ |
| Move to display left / right / above / below (full screen included) | ⌃⌥⌘ ← → ↑ ↓ |
| Focus the display left / right / above / below | ⌃⌥⇧⌘ ← → ↑ ↓ |
| Switch to Space left / right | ⌃⌥⇧ ← → |
| Switch to Space 1–10 | ⌃⌥⌘ 1…0 |
| Switch to last used Space | ⌃⌥⌘ Keypad + |

Everything is rebindable in **Settings › Shortcuts**, and more actions (fourths, sixths, almost
maximize, toggle full screen, next/previous display, …) are available unbound.

Snapping a full-screen window (e.g. ⌃⌥←) takes it out of full screen and snaps it in one go.

Focusing a display brings forward the front-most window on it and moves the pointer there, so Space
shortcuts then act on that display (Settings › General can leave the pointer where it is). An empty
display gets the pointer only.

## Install

```sh
curl -fsSL https://demfier.github.io/tessera/install.sh | bash
```

Or download `Tessera.zip` from the [latest release](https://github.com/Demfier/tessera/releases/latest)
and drag Tessera into Applications. Tessera isn't notarized by Apple (that needs a paid developer
account), so a browser download is blocked on first open: click **Done**, then **Open Anyway** in
System Settings › Privacy & Security. The install script avoids this, and only installs an app signed
with Tessera's own certificate.

Then grant **Accessibility** in System Settings › Privacy & Security. Both window moves and Space
switching need it. Quit Rectangle and InstantSpaceSwitcher if you have them, or their hotkeys will
collide. Requires macOS 14 or later, on Apple silicon or Intel.

## Build

Requires Xcode (Swift 6).

```sh
scripts/build.sh --install   # builds, signs, copies to /Applications and launches
swift test                   # layout/geometry unit tests
```

The Accessibility permission is tied to the app's signature. `build.sh` signs with a stable identity
when it finds one ("Tessera Self-Signed", then an Apple Development certificate), so the permission
survives rebuilds; ad-hoc signing would need a re-grant after every build.

### Publishing a release (maintainers)

```sh
scripts/make-signing-identity.sh   # once: creates "Tessera Self-Signed" in your login keychain
scripts/build.sh --release         # universal build, signed, zipped to build/Tessera.zip
gh release create v1.0 build/Tessera.zip --title "Tessera 1.0" --notes "…"
```

Every release must be signed with the same certificate: `docs/install.sh` pins its hash, and users'
Accessibility permission carries across updates only while the signature stays the same. Bump
`CFBundleShortVersionString` in `Resources/Info.plist` first.

## Command line

```sh
/Applications/Tessera.app/Contents/MacOS/Tessera --perform leftHalf
/Applications/Tessera.app/Contents/MacOS/Tessera --list
```

## How it works

- **Window moves**: the Accessibility API (`AXPosition`/`AXSize`), with Rectangle's
  size → position → size sequence so moves across displays of different sizes land correctly.
- **Full-screen hand-off**: sets `AXFullScreen`, then waits for macOS's active-Space change before
  touching the window again. AX reports the new state about 150 ms before the transition actually
  finishes, and requests made in that gap are silently dropped.
- **Instant Spaces**: posts a synthetic Dock swipe gesture with a huge velocity, so the Dock
  commits the switch without animating. No SIP changes. The engine in `Sources/SpaceSwitchEngine` is
  vendored unmodified from [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher)
  (MIT; see `UPSTREAM` for the commit).
- **Hotkeys**: Carbon `RegisterEventHotKey`, which needs no permission.

## Layout

```
Sources/TesseraCore/        Pure model + geometry (commands, shortcuts, layout math): unit-tested
Sources/Tessera/            The app: AX, hotkeys, Spaces, displays, settings, menu bar
Sources/SpaceSwitchEngine/  Vendored instant-Space-switch engine (C)
Tests/TesseraCoreTests/     Swift Testing suite
scripts/                    build.sh, make-icon.swift, make-signing-identity.sh
docs/                       The website (GitHub Pages) and install.sh
```

## License

MIT; see [LICENSE](LICENSE). The vendored engine in `Sources/SpaceSwitchEngine` keeps its own MIT license.
