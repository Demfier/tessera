import AppKit
import ApplicationServices

/// Private but long-stable (used by Rectangle, AltTab, yabai…): maps an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// A top-level window of some app, driven through the Accessibility API.
/// Frames are in global top-left-origin coordinates.
/// `@unchecked Sendable`: AXUIElement is an immutable CF reference whose API is safe from any thread.
struct AXWindow: @unchecked Sendable {
    let element: AXUIElement
    let pid: pid_t

    private static let fullScreenAttribute = "AXFullScreen"
    private static let fullScreenButtonAttribute = "AXFullScreenButton"
    private static let enhancedUIAttribute = "AXEnhancedUserInterface"
    /// AX calls block on the target app; never let a hung app freeze Tessera for long.
    private static let messagingTimeout: Float = 1

    /// The focused window of the frontmost app.
    static func focused() -> AXWindow? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var app = systemWide.element(kAXFocusedApplicationAttribute)
        if app == nil, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            app = AXUIElementCreateApplication(pid)
        }
        guard let app else { return nil }
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let window = app.element(kAXFocusedWindowAttribute) ?? app.element(kAXMainWindowAttribute)
        else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return AXWindow(element: window, pid: pid)
    }

    /// The app's windows on the current Space (AX does not expose windows on other Spaces).
    static func windows(of pid: pid_t) -> [AXWindow] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let list = app.value(kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return list.map { AXWindow(element: $0, pid: pid) }
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    var frame: CGRect? {
        guard let position: CGPoint = element.axValue(kAXPositionAttribute, type: .cgPoint),
              let size: CGSize = element.axValue(kAXSizeAttribute, type: .cgSize)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    var isFullscreen: Bool { element.bool(Self.fullScreenAttribute) ?? false }
    var isMinimized: Bool { element.bool(kAXMinimizedAttribute) ?? false }

    func setFrame(_ rect: CGRect) {
        // With "enhanced user interface" on (VoiceOver, some Electron/Chromium apps), apps animate
        // AX-driven moves and drop the second half of a size+position change. Disable it meanwhile.
        let app = AXUIElementCreateApplication(pid)
        let enhanced = app.bool(Self.enhancedUIAttribute) == true
        if enhanced { app.set(Self.enhancedUIAttribute, kCFBooleanFalse) }
        defer { if enhanced { app.set(Self.enhancedUIAttribute, kCFBooleanTrue) } }

        // Size → position → size: the first resize may be clamped by the old display's bounds when
        // moving to a bigger display, and the final resize fixes that once the window has arrived.
        element.setAXValue(kAXSizeAttribute, rect.size, type: .cgSize)
        element.setAXValue(kAXPositionAttribute, rect.origin, type: .cgPoint)
        element.setAXValue(kAXSizeAttribute, rect.size, type: .cgSize)
    }

    /// Asks the app to enter or leave native full screen. Returns false if the app refused outright;
    /// the transition itself is asynchronous (see `setFullscreen(_:)`).
    /// `allowButton` permits the green-button fallback — a toggle, so never use it to retry.
    private func requestFullscreen(_ on: Bool, allowButton: Bool) -> Bool {
        if element.set(Self.fullScreenAttribute, on ? kCFBooleanTrue : kCFBooleanFalse) == .success {
            return true
        }
        // Fallback for apps that don't expose a settable AXFullScreen: press the green button.
        guard allowButton, let button = element.element(Self.fullScreenButtonAttribute) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// Enters or leaves full screen and waits for macOS to finish the transition.
    ///
    /// AX alone can't tell when the transition is over: it reports the new state ~150 ms before the
    /// Space animation ends, and requests made during that window are silently dropped. The reliable
    /// signal is the active-Space change macOS posts when the animation completes.
    @MainActor
    func setFullscreen(_ on: Bool) async -> Bool {
        if isFullscreen == on { return true }
        let spaceChange = SpaceChangeSignal()
        guard requestFullscreen(on, allowButton: true) else { return false }

        let clock = ContinuousClock()
        let start = clock.now
        var retried = false
        while clock.now - start < .seconds(4) {
            try? await Task.sleep(for: .milliseconds(40))
            if spaceChange.fired, isFullscreen == on {
                // The window server is still settling the window into its new Space.
                try? await Task.sleep(for: .milliseconds(120))
                return true
            }
            // Apps occasionally drop a request that lands right after another transition; ask once more.
            if !retried, !spaceChange.fired, isFullscreen != on, clock.now - start > .milliseconds(1500) {
                retried = true
                _ = requestFullscreen(on, allowButton: false)
            }
        }
        return isFullscreen == on
    }
}

/// Records whether the active Space changed since it was created.
@MainActor
private final class SpaceChangeSignal {
    private(set) var fired = false
    /// Only written in `init`; removing an observer is thread-safe, so the (nonisolated) deinit may
    /// use it. Not an `isolated deinit`: that needs a Swift runtime newer than macOS 14 ships.
    nonisolated(unsafe) private var token: NSObjectProtocol?

    init() {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fired = true }
        }
    }

    deinit {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
}

// MARK: - AXUIElement conveniences

extension AXUIElement {
    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success ? value : nil
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement) // type ID checked above
    }

    func bool(_ attribute: String) -> Bool? {
        value(attribute) as? Bool
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(self, attribute as CFString, value)
    }

    /// Reads a geometry attribute (`CGPoint`/`CGSize`) boxed in an `AXValue`.
    func axValue<T: BitwiseCopyable>(_ attribute: String, type: AXValueType) -> T? {
        guard let raw = value(attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        return AXValueGetValue(raw as! AXValue, type, pointer) ? pointer.pointee : nil
    }

    func setAXValue<T: BitwiseCopyable>(_ attribute: String, _ value: T, type: AXValueType) {
        let boxed = withUnsafePointer(to: value) { AXValueCreate(type, $0) }
        guard let boxed else { return }
        set(attribute, boxed)
    }
}
