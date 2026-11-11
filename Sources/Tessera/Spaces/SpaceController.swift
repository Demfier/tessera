import AppKit
import Combine
import SpaceSwitchEngine
import TesseraCore

/// Instant Space switching. The vendored engine posts a synthetic trackpad swipe with an enormous
/// velocity, so the Dock commits the switch without playing its slide animation — no SIP changes.
@MainActor
final class SpaceController: ObservableObject {
    struct Status: Equatable {
        /// Zero-based index of the active Space on the menu-bar display.
        let index: Int
        let count: Int
    }

    @Published private(set) var status: Status?

    var showsHUD = false
    var interceptsTrackpadSwipes = false {
        didSet { if isEngineRunning { iss_set_swipe_override(interceptsTrackpadSwipes) } }
    }

    private(set) var isEngineRunning = false
    /// Per display (by UUID): the Space index last seen active, and the one before it. Tracked per
    /// display because Space shortcuts act on the display under the pointer, not the menu-bar one.
    private var currentIndexByDisplay: [String: Int] = [:]
    private var previousIndexByDisplay: [String: Int] = [:]
    private var spaceObserver: NSObjectProtocol?
    private let hud = SpaceHUD()
    private static weak var active: SpaceController?

    /// Requires Accessibility (the engine installs an event tap and posts events).
    func start() {
        guard !isEngineRunning else { return }
        guard iss_init() else {
            // The tap can fail briefly right after permission is granted; retry.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.start() }
            return
        }
        isEngineRunning = true
        Self.active = self
        iss_set_swipe_override(interceptsTrackpadSwipes)
        // Lets the engine ignore trackpad swipes made inside App Exposé, and lets us hide the HUD
        // while Mission Control is open.
        iss_set_overlay_detection_enabled(true)
        iss_set_switch_callback { index in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { SpaceController.active?.engineDidSwitch(to: Int(index)) }
            }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                iss_reset_predictions()
                self?.refreshStatus()
            }
        }
        refreshStatus()
    }

    func stop() {
        guard isEngineRunning else { return }
        iss_destroy()
        isEngineRunning = false
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
    }

    func perform(_ command: Command) {
        guard isEngineRunning else { return NSSound.beep() }
        switch command.kind {
        case .spaceStep(let direction):
            // Returns false at the first/last Space; like the native shortcut, that's a no-op.
            _ = iss_switch(direction == .left ? ISSDirectionLeft : ISSDirectionRight)
        case .spaceIndex(let index):
            // Check bounds ourselves: for an out-of-range index the engine switches to the last
            // Space *and* reports failure.
            guard let info = Self.spaceInfoUnderPointer(), index < Int(info.spaceCount) else { return NSSound.beep() }
            _ = iss_switch_to_index(UInt32(index))
        case .lastSpace:
            guard let info = Self.spaceInfoUnderPointer(),
                  let previous = previousIndexByDisplay[info.displayIdentifier],
                  previous != Int(info.currentIndex), previous < Int(info.spaceCount)
            else { return NSSound.beep() }
            _ = iss_switch_to_index(UInt32(previous))
        default:
            assertionFailure("\(command) is not a Space command")
        }
    }

    private func engineDidSwitch(to index: Int) {
        guard showsHUD, !iss_is_mission_control_active() else { return }
        hud.show(String(index + 1), on: .underMouse)
    }

    private func refreshStatus() {
        var menuBar = ISSSpaceInfo()
        if iss_get_menubar_space_info(&menuBar) {
            record(menuBar)
            status = Status(index: Int(menuBar.currentIndex), count: Int(menuBar.spaceCount))
        } else {
            status = nil
        }
        // Space changes happen on the display under the pointer (our shortcuts) or the focused one
        // (the menu-bar display), so recording both covers every switch.
        if let underPointer = Self.spaceInfoUnderPointer() { record(underPointer) }
    }

    private func record(_ info: ISSSpaceInfo) {
        let display = info.displayIdentifier
        let index = Int(info.currentIndex)
        if let current = currentIndexByDisplay[display], current != index {
            previousIndexByDisplay[display] = current
        }
        currentIndexByDisplay[display] = index
    }

    private static func spaceInfoUnderPointer() -> ISSSpaceInfo? {
        var info = ISSSpaceInfo()
        return iss_get_space_info(&info) ? info : nil
    }
}

private extension ISSSpaceInfo {
    /// `displayID` is a fixed-size C string (`char[128]`) holding the display's UUID.
    var displayIdentifier: String {
        withUnsafeBytes(of: displayID) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
