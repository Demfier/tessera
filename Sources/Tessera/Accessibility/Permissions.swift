import AppKit
import ApplicationServices
import Combine

/// Tracks the Accessibility permission every feature depends on (moving windows, posting the
/// synthetic swipe gestures that switch Spaces). macOS gives no change notification, so poll.
@MainActor
final class Permissions: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    private var pollTimer: Timer?
    private var onGranted: [() -> Void] = []

    /// Runs `body` now if trusted, otherwise as soon as the permission is granted.
    func whenTrusted(_ body: @escaping () -> Void) {
        if isTrusted { body(); return }
        onGranted.append(body)
        startPolling()
    }

    /// Shows the system prompt that deep-links to System Settings › Privacy › Accessibility.
    func requestAccess() {
        // The literal value of kAXTrustedCheckOptionPrompt, which Swift 6 flags as mutable global state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        update(trusted: AXIsProcessTrustedWithOptions(options))
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(trusted: AXIsProcessTrusted()) }
        }
    }

    /// The single place trust is recorded, so pending callbacks run no matter which path
    /// (poll, prompt, or a shortcut press) notices the grant first.
    private func update(trusted: Bool) {
        if isTrusted != trusted { isTrusted = trusted }
        guard trusted else { return startPolling() }
        pollTimer?.invalidate()
        pollTimer = nil
        let callbacks = onGranted
        onGranted.removeAll()
        callbacks.forEach { $0() }
    }
}
