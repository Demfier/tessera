import AppKit

/// A brief, click-through overlay showing the number of the Space just switched to.
@MainActor
final class SpaceHUD {
    private static let side: CGFloat = 132
    private static let visibleFor: Duration = .milliseconds(550)

    private lazy var panel: NSPanel = makePanel()
    private let label = NSTextField(labelWithString: "")
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, on screen: NSScreen?) {
        guard let screen else { return }
        label.stringValue = text
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.side / 2, y: frame.midY - Self.side / 2))
        // Through the animator with zero duration, so it supersedes a fade-out still in flight.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.side, height: Self.side),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let background = NSVisualEffectView(frame: panel.contentLayoutRect)
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 22
        background.layer?.masksToBounds = true

        label.font = .systemFont(ofSize: 64, weight: .semibold)
        label.alignment = .center
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        panel.contentView = background
        return panel
    }
}
