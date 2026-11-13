# Tessera

Tessera is a macOS menu-bar app for managing windows with the keyboard. It snaps windows to parts of
the screen, switches Spaces without the slide animation, and moves windows between displays,
including windows in full screen.

It replaces Rectangle, InstantSpaceSwitcher, and the window moving in Second Display Pro.

Website and download: <https://demfier.github.io/tessera/>

Requires macOS 14 or later, on Apple silicon or Intel.

## Features

- Snap the focused window to halves, corners, thirds, fourths, or sixths. Maximize it, center it,
  make it larger or smaller, move it to an edge, or restore the frame it had before Tessera moved it.
- Press a half shortcut a second time to move the window to the same half of the next display. In
  Settings you can make repeated presses cycle through sizes (½, ⅔, ⅓) instead, or do nothing.
- Switch to the Space on the left or right, jump to Space 1–10, or go back to the last Space, without
  the animation. The switch applies to the display under the pointer. Three-finger trackpad swipes
  between Spaces can also skip the animation (off by default).
- Move the focused window to the display on the left, right, above, or below. A window that fills its
  display fills the new one; other windows keep their size and relative position. A full-screen window
  is taken out of full screen, moved, and put back in full screen. This takes about two seconds because
  of macOS's full-screen animation.
- Move keyboard focus to another display. Tessera activates the front window on that display and moves
  the pointer there, so Space shortcuts act on that display next.
- When a display disconnects and comes back, windows that were on it move back.

## Default shortcuts

| Action | Shortcut |
|---|---|
| Left / right / top / bottom half | ⌃⌥ ← → ↑ ↓ |
| Top-left / top-right / bottom-left / bottom-right | ⌃⌥ U I J K |
| First / center / last third | ⌃⌥ D F G |
| First / last two thirds | ⌃⌥ E T |
| Maximize / maximize height | ⌃⌥ ↩ / ⌃⌥⇧ ↑ |
| Center / larger / smaller / restore | ⌃⌥ C = - ⌫ |
| Move window to the display left / right / above / below | ⌃⌥⌘ ← → ↑ ↓ |
| Focus the display left / right / above / below | ⌃⌥⇧⌘ ← → ↑ ↓ |
| Space left / right | ⌃⌥⇧ ← → |
| Space 1–10 | ⌃⌥⌘ 1…0 |
| Last used Space | ⌃⌥⌘ keypad + |

You can change any shortcut in Settings › Shortcuts. Some actions have no default shortcut: fourths,
sixths, almost maximize, maximize width, move to an edge, toggle full screen, and next/previous display.

## Install

With the install script:

```sh
curl -fsSL https://demfier.github.io/tessera/install.sh | bash
```

The script downloads the latest release, checks that it is signed with Tessera's certificate, copies
it to /Applications (or ~/Applications if /Applications isn't writable), and opens it.

To install manually, download `Tessera.zip` from the
[latest release](https://github.com/Demfier/tessera/releases/latest), unzip it, and move Tessera.app
to Applications. Tessera isn't notarized by Apple, because notarization requires a paid Apple
Developer account. As a result, macOS blocks a copy downloaded in a browser the first time you open
it. Click Done, open System Settings › Privacy & Security, and click Open Anyway next to the message
about Tessera. Files downloaded with curl aren't marked as coming from the internet, so the install
script doesn't run into this.

On first launch Tessera asks for Accessibility access, which it needs to move other apps' windows and
to switch Spaces. Turn it on in System Settings › Privacy & Security › Accessibility.

If Rectangle or InstantSpaceSwitcher is running, quit it, since it uses the same shortcuts.

Tessera starts at login. You can turn that off in Settings › General.

## Build from source

Requires Xcode with Swift 6.

```sh
git clone https://github.com/Demfier/tessera.git
cd tessera
scripts/build.sh --install   # build, sign, copy to /Applications, and launch
swift test                   # run the unit tests
```

macOS ties the Accessibility permission to the app's code signature. `build.sh` signs with
"Tessera Self-Signed" if that certificate is in your keychain, otherwise with an Apple Development
certificate, otherwise ad hoc. With an ad-hoc signature you have to grant Accessibility again after
every build.

## Releasing

```sh
scripts/make-signing-identity.sh   # once: create "Tessera Self-Signed" in the login keychain
scripts/build.sh --release         # universal build, signed and zipped to build/Tessera.zip
gh release create v1.1 build/Tessera.zip --title "Tessera 1.1" --notes "..."
```

Before building, update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`. Sign every release with
the same certificate: `docs/install.sh` checks for that certificate's hash, and users keep their
Accessibility permission across updates only if the signature stays the same.

## Command line

`Tessera --perform <command>` runs one action on the focused window and exits. `--list` prints every
command name.

```sh
/Applications/Tessera.app/Contents/MacOS/Tessera --perform leftHalf
/Applications/Tessera.app/Contents/MacOS/Tessera --list
```

## How it works

- Windows are moved with the Accessibility API (`AXPosition`, `AXSize`). Like Rectangle, Tessera sets
  the size, then the position, then the size again, so a window moved to a larger display isn't left
  at the size the old display allowed.
- For full screen, Tessera sets `AXFullScreen` and waits for macOS to report an active-Space change
  before touching the window again. The Accessibility API reports the new state about 150 ms before
  the animation ends, and macOS ignores requests sent in that gap.
- Space switching posts a synthetic Dock swipe gesture with a very high velocity, so the Dock
  completes the switch without animating. It doesn't require turning off SIP. The code in
  `Sources/SpaceSwitchEngine` is copied unmodified from
  [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) (MIT; `UPSTREAM` records
  the commit).
- Focusing a particular window on another display uses private SkyLight functions, as yabai and
  AltTab do. If those functions are missing, Tessera falls back to the Accessibility API.
- Shortcuts are registered with Carbon's `RegisterEventHotKey`, which needs no permission.

## Project layout

```
Sources/TesseraCore/        Commands, shortcuts, and layout math (unit-tested)
Sources/Tessera/            The app: Accessibility, hotkeys, Spaces, displays, settings, menu bar
Sources/SpaceSwitchEngine/  Space-switching engine from InstantSpaceSwitcher (C)
Tests/TesseraCoreTests/     Unit tests (Swift Testing)
scripts/                    build.sh, make-icon.swift, make-signing-identity.sh
docs/                       Website (GitHub Pages) and install.sh
```

## License

MIT; see [LICENSE](LICENSE). `Sources/SpaceSwitchEngine` keeps its own MIT license.
