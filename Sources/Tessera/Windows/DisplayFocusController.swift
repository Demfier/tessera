import AppKit
import TesseraCore

/// Moves keyboard focus to another display: brings forward the front-most window there and,
/// optionally, takes the pointer along (Space shortcuts act on the display under the pointer,
/// so this keeps them pointed at the display you just went to).
@MainActor
final class DisplayFocusController {
    private let settings: Settings

    /// Ignore slivers and helper windows some apps keep at the normal window level.
    private static let minimumWindowSide: CGFloat = 40

    init(settings: Settings) {
        self.settings = settings
    }

    func focus(_ target: DisplayTarget) {
        let displays = DisplayCatalog.current()
        guard let current = currentDisplay(in: displays),
              let destination = Layout.targetDisplay(target, from: current, in: displays,
                                                     cycleWhenNoNeighbour: settings.cycleDisplaysWhenNoNeighbour)
        else { return NSSound.beep() }

        let window = Self.frontmostWindow(on: destination, in: displays)
        if let window { WindowActivation.focus(window.id, pid: window.pid, element: window.element) }

        var movedPointer = false
        if settings.movePointerWithFocus, let pointer = Self.pointerLocation,
           Layout.displayIndex(for: CGRect(origin: pointer, size: .zero), in: displays) != destination {
            CGWarpMouseCursorPosition(Layout.pointerTarget(for: window?.frame, on: displays[destination]))
            // Warping briefly freezes the pointer unless it's re-associated with the mouse.
            CGAssociateMouseAndMouseCursorPosition(1)
            movedPointer = true
        }
        // An empty display with the pointer left behind: nothing happened, so say so.
        if window == nil && !movedPointer { NSSound.beep() }
    }

    /// The display holding the focused window; with nothing focused, the one under the pointer.
    private func currentDisplay(in displays: [Display]) -> Int? {
        if let frame = AXWindow.focused()?.frame { return Layout.displayIndex(for: frame, in: displays) }
        guard let pointer = Self.pointerLocation else { return nil }
        return Layout.displayIndex(for: CGRect(origin: pointer, size: .zero), in: displays)
    }

    /// The front-most real window on `display`. The window server also lists helper windows at the
    /// normal level — e.g. the hidden title-bar strip along the top of a full-screen app — so prefer
    /// the first one its app actually reports as a window; if none do, take the front-most anyway.
    private static func frontmostWindow(on display: Int, in displays: [Display])
        -> (id: CGWindowID, pid: pid_t, frame: CGRect, element: AXWindow?)? {
        let candidates = Layout.windows(onscreenWindows(), on: display, in: displays)
        var appWindows: [pid_t: [AXWindow]] = [:]
        for candidate in candidates {
            let windows = appWindows[candidate.pid] ?? AXWindow.windows(of: candidate.pid)
            appWindows[candidate.pid] = windows
            if let element = windows.first(where: { $0.windowID == candidate.id }) {
                return (candidate.id, candidate.pid, element.frame ?? candidate.frame, element)
            }
        }
        return candidates.first.map { ($0.id, $0.pid, $0.frame, nil) }
    }

    /// Global top-left-origin coordinates, like everything else in Tessera.
    private static var pointerLocation: CGPoint? { CGEvent(source: nil)?.location }

    /// Ordinary app windows on the visible Space of every display, front to back.
    private static func onscreenWindows() -> [OnscreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width >= minimumWindowSide, frame.height >= minimumWindowSide
            else { return nil }
            return OnscreenWindow(id: id, pid: pid, frame: frame)
        }
    }
}
