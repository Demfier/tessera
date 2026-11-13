import AppKit
import Combine
import TesseraCore

/// Checks GitHub for new releases on a schedule and installs them.
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AvailableUpdate)
        case installing(AppVersion)
        case checkFailed(String)
        case installFailed(AppVersion, String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    let currentVersion = UpdateInstaller.currentVersion

    private let settings: Settings
    private let defaults: UserDefaults
    private var timer: Timer?
    /// Earliest time for the next automatic check.
    private var nextCheck = Date.distantPast

    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let retryInterval: TimeInterval = 60 * 60
    /// Automatic installs wait for this much keyboard and mouse inactivity, since Tessera restarts.
    private static let idleBeforeInstall: TimeInterval = 120
    private static let lastCheckedKey = "lastUpdateCheck"

    init(settings: Settings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        lastChecked = defaults.object(forKey: Self.lastCheckedKey) as? Date
        if let lastChecked { nextCheck = lastChecked.addingTimeInterval(Self.checkInterval) }
    }

    func start() {
        guard timer == nil else { return }
        // First look shortly after launch (not during it), then once a minute see whether anything is due.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard settings.automaticallyCheckForUpdates else { return }
        switch state {
        case .checking, .installing:
            return
        case .available(let update):
            if settings.automaticallyInstallUpdates, Self.secondsSinceLastInput >= Self.idleBeforeInstall {
                install(update)
            }
        default:
            if Date() >= nextCheck { Task { await check() } }
        }
    }

    @discardableResult
    func check() async -> State {
        if case .checking = state { return state }
        if case .installing = state { return state }
        state = .checking
        do {
            let release = try await UpdateInstaller.fetchLatestRelease()
            let now = Date()
            lastChecked = now
            defaults.set(now, forKey: Self.lastCheckedKey)
            nextCheck = now.addingTimeInterval(Self.checkInterval)
            state = UpdatePolicy.update(from: release, current: currentVersion).map(State.available) ?? .upToDate
        } catch {
            nextCheck = Date().addingTimeInterval(Self.retryInterval)
            state = .checkFailed(error.localizedDescription)
        }
        return state
    }

    func install(_ update: AvailableUpdate) {
        if case .installing = state { return }
        state = .installing(update.version)
        let target = Bundle.main.bundleURL
        Task {
            do {
                try await UpdateInstaller.install(update, over: target)
                UpdateInstaller.relaunch(target)
            } catch {
                nextCheck = Date().addingTimeInterval(Self.checkInterval)
                state = .installFailed(update.version, error.localizedDescription)
            }
        }
    }

    /// "Check for Updates…" from the menu: check now and report the result in an alert.
    func checkAndReport() {
        Task {
            let result = await check()
            NSApp.activate()
            let alert = NSAlert()
            switch result {
            case .available(let update):
                alert.messageText = "Tessera \(update.version) is available"
                alert.informativeText = "You have version \(currentVersion). Tessera restarts after installing, which takes about a second."
                alert.addButton(withTitle: "Install and Restart")
                alert.addButton(withTitle: "Release Notes")
                alert.addButton(withTitle: "Later")
                switch alert.runModal() {
                case .alertFirstButtonReturn: install(update)
                case .alertSecondButtonReturn: NSWorkspace.shared.open(update.releaseNotesURL)
                default: break
                }
            case .checkFailed(let message):
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = message
                alert.runModal()
            case .upToDate:
                alert.messageText = "Tessera is up to date"
                alert.informativeText = "Version \(currentVersion) is the latest release."
                alert.runModal()
            default:
                break // a check or install was already running; its result shows in Settings
            }
        }
    }

    private static var secondsSinceLastInput: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
