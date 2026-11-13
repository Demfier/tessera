import AppKit
import TesseraCore

/// `Tessera --perform <command>` runs one action and exits, for scripts and launchers. `--update`
/// installs the latest release. Unknown arguments fall through so normal launches (which may carry
/// system flags) work.
@MainActor
enum CommandLineInterface {
    static func runIfRequested(_ arguments: [String]) {
        switch arguments.first {
        case "--help":
            print(usage)
            exit(0)
        case "--list":
            for command in Command.allCases {
                let shortcut = command.defaultShortcut.map { "  (default \($0))" } ?? ""
                print("\(command.rawValue.padding(toLength: 22, withPad: " ", startingAt: 0))\(command.title)\(shortcut)")
            }
            exit(0)
        case "--perform":
            guard arguments.count == 2, let command = Command(rawValue: arguments[1]) else {
                FileHandle.standardError.write(Data("\(usage)\n".utf8))
                exit(64) // EX_USAGE
            }
            // Needs Space history, which only the running menu-bar app has.
            guard command != .lastSpace else {
                FileHandle.standardError.write(Data("lastSpace is only available from the running app.\n".utf8))
                exit(64)
            }
            perform(command)
        case "--update":
            update()
        default:
            return
        }
    }

    private static let usage = """
        Usage: Tessera [--perform <command> | --list | --update | --help]
          --perform <command>  Run one action on the focused window (or switch Spaces) and exit.
          --list               List every command name.
          --update             Install the latest release over this copy of Tessera, restarting
                               it if it's running.
        """

    private static func update() -> Never {
        Task {
            let current = UpdateInstaller.currentVersion
            do {
                let release = try await UpdateInstaller.fetchLatestRelease()
                guard let update = UpdatePolicy.update(from: release, current: current) else {
                    say("Tessera \(current) is up to date.")
                    exit(0)
                }
                let target = Bundle.main.bundleURL
                say("Installing Tessera \(update.version) over \(current)…")
                try await UpdateInstaller.install(update, over: target)
                try await restartCopies(of: target)
                say("Installed Tessera \(update.version).")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Update failed: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        dispatchMain()
    }

    /// Unbuffered, so it can't come out after an error written to stderr.
    private static func say(_ line: String) {
        FileHandle.standardOutput.write(Data("\(line)\n".utf8))
    }

    /// Quits any running menu-bar copy started from `app` and opens the new version in its place.
    private static func restartCopies(of app: URL) async throws {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != .current && $0.bundleURL?.standardizedFileURL == app.standardizedFileURL }
        guard !running.isEmpty else { return }
        for copy in running { copy.terminate() }
        let deadline = Date().addingTimeInterval(5)
        while running.contains(where: { kill($0.processIdentifier, 0) == 0 }), Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        for copy in running where kill(copy.processIdentifier, 0) == 0 { copy.forceTerminate() }
        try await Task.sleep(for: .milliseconds(300))
        NSWorkspace.shared.open(app)
    }

    private static func perform(_ command: Command) -> Never {
        guard AXIsProcessTrusted() else {
            FileHandle.standardError.write(Data("Tessera needs Accessibility access for the calling process.\n".utf8))
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        let settings = Settings()
        let windows = WindowController(settings: settings)
        let spaces = SpaceController()
        if command.group == .spaces { spaces.start() }
        CommandRouter(windows: windows, spaces: spaces, focus: DisplayFocusController(settings: settings))
            .perform(command)

        // Full-screen hand-offs are asynchronous; keep the run loop alive until they finish.
        let started = Date()
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                let elapsed = Date().timeIntervalSince(started)
                if (windows.isIdle && elapsed > 0.3) || elapsed > 15 {
                    spaces.stop()
                    exit(0)
                }
            }
        }
        app.run()
        exit(0)
    }
}
