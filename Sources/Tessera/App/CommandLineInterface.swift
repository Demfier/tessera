import AppKit
import TesseraCore

/// `Tessera --perform <command>` runs one action and exits — handy for scripts, launchers and
/// testing. Unknown arguments fall through so normal launches (which may carry system flags) work.
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
        default:
            return
        }
    }

    private static let usage = """
        Usage: Tessera [--perform <command> | --list | --help]
          --perform <command>  Run one action on the focused window (or switch Spaces) and exit.
          --list               List every command name.
        """

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
