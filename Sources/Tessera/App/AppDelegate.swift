import AppKit
import Combine
import TesseraCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let permissions = Permissions()
    private let hotkeys = HotkeyCenter()
    private let spaces = SpaceController()
    private let restorer = DisplayReconnectRestorer()
    private let launchAtLogin = LaunchAtLogin()
    private lazy var router = CommandRouter(windows: WindowController(settings: settings), spaces: spaces,
                                            focus: DisplayFocusController(settings: settings))
    private lazy var recorder = ShortcutRecorder(settings: settings, hotkeys: hotkeys)
    private lazy var settingsWindow = SettingsWindowController(environment: SettingsEnvironment(
        settings: settings, hotkeys: hotkeys, permissions: permissions, recorder: recorder,
        launchAtLogin: launchAtLogin
    ))
    private var statusMenu: StatusMenuController?
    private var cancellables = Set<AnyCancellable>()

    /// Posted by a second launch (e.g. from Spotlight) asking the running copy to show Settings.
    private static let showSettingsRequest = Notification.Name("me.laurelwood.tessera.showSettings")

    func applicationWillFinishLaunching(_ notification: Notification) {
        handOverIfAlreadyRunning()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DistributedNotificationCenter.default().addObserver(
            forName: Self.showSettingsRequest, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsWindow.show() }
        }

        if settings.isFirstLaunch {
            launchAtLogin.set(true)
            settings.completeFirstLaunch()
        }

        hotkeys.onCommand = { [weak self] in self?.perform($0) }
        bindSettings()

        statusMenu = StatusMenuController(
            settings: settings, spaces: spaces, permissions: permissions,
            actions: .init(perform: { [weak self] in self?.perform($0) },
                           openSettings: { [weak self] in self?.settingsWindow.show() },
                           requestAccessibility: { [weak self] in self?.permissions.requestAccess() })
        )

        restorer.start()
        permissions.whenTrusted { [weak self] in self?.spaces.start() }
        if !permissions.isTrusted {
            settingsWindow.show()
            permissions.requestAccess()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        spaces.stop()
    }

    private func bindSettings() {
        settings.$bindings
            .sink { [hotkeys] in hotkeys.update($0) }
            .store(in: &cancellables)
        settings.$instantTrackpadSwipes
            .sink { [spaces] in spaces.interceptsTrackpadSwipes = $0 }
            .store(in: &cancellables)
        settings.$showSpaceHUD
            .sink { [spaces] in spaces.showsHUD = $0 }
            .store(in: &cancellables)
        settings.$restoreWindowsOnReconnect
            .sink { [restorer] in restorer.isEnabled = $0 }
            .store(in: &cancellables)
    }

    private func perform(_ command: Command) {
        guard permissions.isTrusted else { return permissions.requestAccess() }
        router.perform(command)
    }

    /// A second copy would fight the first over the same hotkeys: ask the running one to show
    /// Settings, then quit. `--perform` runs use the .prohibited policy and don't count.
    private func handOverIfAlreadyRunning() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let alreadyRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0 != .current && $0.activationPolicy != .prohibited }
        guard alreadyRunning else { return }
        DistributedNotificationCenter.default().postNotificationName(
            Self.showSettingsRequest, object: nil, userInfo: nil, deliverImmediately: true)
        exit(0)
    }
}
