import AppKit

MainActor.assumeIsolated {
    CommandLineInterface.runIfRequested(Array(CommandLine.arguments.dropFirst()))

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Info.plist sets LSUIElement; this covers running the bare binary during development.
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
