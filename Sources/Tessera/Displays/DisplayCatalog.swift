import AppKit
import TesseraCore

/// Bridges AppKit's screens (bottom-left origin) to the top-left-origin geometry used by
/// `TesseraCore` and the Accessibility API.
@MainActor
enum DisplayCatalog {
    /// Connected displays, ordered for next/previous (left-to-right, then top-to-bottom).
    static func current() -> [Display] {
        let screens = NSScreen.screens
        // The primary screen (index 0, origin at 0,0) anchors the global coordinate space.
        guard let primaryHeight = screens.first?.frame.maxY else { return [] }
        return Layout.sorted(screens.map { screen in
            Display(id: screen.displayID ?? 0,
                    frame: flip(screen.frame, primaryHeight: primaryHeight),
                    visible: flip(screen.visibleFrame, primaryHeight: primaryHeight))
        })
    }

    private static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The screen under the mouse pointer — the one a space switch or HUD applies to.
    static var underMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }
}
