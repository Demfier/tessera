import AppKit
import TesseraCore

/// Executes window commands against the focused window.
@MainActor
final class WindowController {
    private let settings: Settings

    /// Layout Tessera last applied per window — drives repeat detection and layout replay.
    private var placements: [CGWindowID: Placement] = [:]
    /// The frame Tessera last set per window; if the window no longer has it, the user moved it.
    private var lastSetFrames: [CGWindowID: CGRect] = [:]
    /// Where each window was before Tessera started moving it (for Restore).
    private var restoreFrames: [CGWindowID: CGRect] = [:]

    /// A full-screen hand-off takes a second or two of macOS animation; presses during it are dropped
    /// rather than queued, since they would act on a window that's mid-transition.
    private var transition: Task<Void, Never>?

    var isIdle: Bool { transition == nil }

    init(settings: Settings) {
        self.settings = settings
    }

    func perform(_ command: Command) {
        guard transition == nil else { return }
        guard let window = AXWindow.focused() else {
            NSSound.beep()
            return
        }
        switch command.kind {
        case .layout:
            whenWindowed(window) { self.applyLayout(command, to: window) }
        case .restore:
            whenWindowed(window) { self.restore(window) }
        case .display(let target):
            if window.isFullscreen {
                runTransition { await self.moveFullscreenWindow(window, to: target) }
            } else {
                moveToDisplay(window, target)
            }
        case .toggleFullscreen:
            runTransition {
                if await !window.setFullscreen(!window.isFullscreen) { NSSound.beep() }
            }
        case .focusDisplay, .spaceStep, .spaceIndex, .lastSpace:
            assertionFailure("\(command) is routed elsewhere by CommandRouter")
        }
    }

    // MARK: - Layout

    /// Runs `body` on a normal window; a full-screen window first leaves full screen
    /// (sparing the exit-full-screen → snap → re-enter dance).
    private func whenWindowed(_ window: AXWindow, _ body: @escaping @MainActor () -> Void) {
        guard window.isFullscreen else { return body() }
        runTransition {
            guard await window.setFullscreen(false) else { return NSSound.beep() }
            body()
        }
    }

    private func applyLayout(_ command: Command, to window: AXWindow) {
        let displays = DisplayCatalog.current()
        guard let frame = window.frame, let current = Layout.displayIndex(for: frame, in: displays) else {
            return NSSound.beep()
        }
        let id = window.windowID
        guard let result = Layout.compute(command, window: frame, displays: displays, current: current,
                                          last: id.flatMap { placements[$0] },
                                          behavior: settings.repeatBehavior, gap: settings.gapSize)
        else { return NSSound.beep() }
        place(window, id: id, result: result, from: frame)
    }

    private func moveToDisplay(_ window: AXWindow, _ target: DisplayTarget) {
        let displays = DisplayCatalog.current()
        guard let frame = window.frame,
              let current = Layout.displayIndex(for: frame, in: displays),
              let destination = Layout.targetDisplay(target, from: current, in: displays,
                                                     cycleWhenNoNeighbour: settings.cycleDisplaysWhenNoNeighbour)
        else { return NSSound.beep() }
        let id = window.windowID
        let result = Layout.transfer(window: frame, last: id.flatMap { placements[$0] },
                                     from: displays[current], to: displays[destination],
                                     destinationIndex: destination, gap: settings.gapSize)
        place(window, id: id, result: result, from: frame)
    }

    /// Second Display Pro's trick, automated: leave full screen, hop displays, re-enter full screen.
    private func moveFullscreenWindow(_ window: AXWindow, to target: DisplayTarget) async {
        let before = DisplayCatalog.current()
        guard let fullscreenFrame = window.frame,
              let current = Layout.displayIndex(for: fullscreenFrame, in: before),
              let destination = Layout.targetDisplay(target, from: current, in: before,
                                                     cycleWhenNoNeighbour: settings.cycleDisplaysWhenNoNeighbour)
        else { return NSSound.beep() }
        let destinationID = before[destination].id

        guard await window.setFullscreen(false) else { return NSSound.beep() }

        // Leaving full screen brings the menu bar back, changing visible frames — measure again.
        let displays = DisplayCatalog.current()
        guard let frame = window.frame,
              let destinationIndex = displays.firstIndex(where: { $0.id == destinationID })
        else { return NSSound.beep() }
        let source = Layout.displayIndex(for: frame, in: displays) ?? destinationIndex
        let id = window.windowID
        let result = Layout.transfer(window: frame, last: id.flatMap { placements[$0] },
                                     from: displays[source], to: displays[destinationIndex],
                                     destinationIndex: destinationIndex, gap: settings.gapSize)
        place(window, id: id, result: result, from: frame)

        // Give the window server a beat to re-home the window on the new display, otherwise
        // full screen can open on the old one.
        try? await Task.sleep(for: .milliseconds(150))
        if await !window.setFullscreen(true) { NSSound.beep() }
    }

    private func restore(_ window: AXWindow) {
        guard let id = window.windowID, let original = restoreFrames[id] else { return NSSound.beep() }
        window.setFrame(original)
        restoreFrames[id] = nil
        placements[id] = nil
        lastSetFrames[id] = nil
    }

    // MARK: - Bookkeeping

    private func place(_ window: AXWindow, id: CGWindowID?, result: LayoutResult, from previous: CGRect) {
        guard let id else {
            window.setFrame(result.rect)
            return
        }
        // Remember the pre-Tessera frame, refreshing it whenever the user has moved the window since.
        if restoreFrames[id] == nil || lastSetFrames[id].map({ !$0.isApproximatelyEqual(to: previous, tolerance: 2) }) ?? true {
            restoreFrames[id] = previous
        }
        window.setFrame(result.rect)
        // Read back: apps may round to their own size increments (terminals, editors).
        let actual = window.frame ?? result.rect
        lastSetFrames[id] = actual
        placements[id] = result.command.map { Placement(command: $0, variant: result.variant, rect: actual) }
        pruneIfNeeded()
    }

    /// Forget windows that no longer exist so the history can't grow without bound.
    private func pruneIfNeeded() {
        guard restoreFrames.count > 200 else { return }
        guard let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return }
        let alive = Set(info.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        restoreFrames = restoreFrames.filter { alive.contains($0.key) }
        placements = placements.filter { alive.contains($0.key) }
        lastSetFrames = lastSetFrames.filter { alive.contains($0.key) }
    }

    private func runTransition(_ body: @escaping @MainActor () async -> Void) {
        transition = Task {
            await body()
            transition = nil
        }
    }
}
