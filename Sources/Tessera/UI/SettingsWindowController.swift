import AppKit
import SwiftUI

/// Hosts `SettingsView` in a regular window. Tessera is a menu-bar (accessory) app, so it has to
/// activate itself explicitly for the window to come forward and receive key presses.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let environment: SettingsEnvironment
    private var window: NSWindow?

    init(environment: SettingsEnvironment) {
        self.environment = environment
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(environment: environment)))
        window.title = "Tessera Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        environment.recorder.stop()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Never leave global hotkeys suspended because a recording was abandoned.
        environment.recorder.stop()
    }
}
