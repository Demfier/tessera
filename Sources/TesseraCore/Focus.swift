import CoreGraphics

/// A visible top-level window as the window server lists it (front-to-back order).
public struct OnscreenWindow: Equatable, Sendable {
    public let id: CGWindowID
    public let pid: Int32
    public let frame: CGRect

    public init(id: CGWindowID, pid: Int32, frame: CGRect) {
        self.id = id
        self.pid = pid
        self.frame = frame
    }
}

extension Layout {
    /// The windows that belong to `display`, keeping the window server's front-to-back order.
    public static func windows(_ windows: [OnscreenWindow], on display: Int,
                               in displays: [Display]) -> [OnscreenWindow] {
        windows.filter { displayIndex(for: $0.frame, in: displays) == display }
    }

    /// Where the pointer goes when focus moves to `display`: the middle of the part of `window` that's
    /// on that display (so it lands on the window, never off-screen), else the display's middle.
    public static func pointerTarget(for window: CGRect?, on display: Display) -> CGPoint {
        if let window {
            let visible = window.intersection(display.visible)
            if !visible.isNull, visible.width > 0, visible.height > 0 { return visible.center }
        }
        return display.visible.center
    }
}
