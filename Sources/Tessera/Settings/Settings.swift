import Combine
import Foundation
import TesseraCore

/// User preferences, persisted to Tessera's own defaults domain.
@MainActor
final class Settings: ObservableObject {
    private enum Key {
        static let bindings = "shortcuts.v1"
        static let repeatBehavior = "repeatBehavior"
        static let gapSize = "gapSize"
        static let cycleDisplaysWhenNoNeighbour = "cycleDisplaysWhenNoNeighbour"
        static let restoreWindowsOnReconnect = "restoreWindowsOnReconnect"
        static let movePointerWithFocus = "movePointerWithFocus"
        static let instantTrackpadSwipes = "instantTrackpadSwipes"
        static let showSpaceHUD = "showSpaceHUD"
        static let showSpaceNumberInMenuBar = "showSpaceNumberInMenuBar"
        static let automaticallyCheckForUpdates = "automaticallyCheckForUpdates"
        static let automaticallyInstallUpdates = "automaticallyInstallUpdates"
        static let didCompleteFirstLaunch = "didCompleteFirstLaunch"
    }

    private let defaults: UserDefaults

    /// True until the menu-bar app has run its one-time setup. Deliberately not inferred from
    /// "nothing saved yet": a `--perform` run must not count as the app's first launch.
    var isFirstLaunch: Bool { !defaults.bool(forKey: Key.didCompleteFirstLaunch) }

    @Published private(set) var bindings: [Command: Shortcut]

    @Published var repeatBehavior: RepeatBehavior {
        didSet { defaults.set(repeatBehavior.rawValue, forKey: Key.repeatBehavior) }
    }
    /// Space between tiled windows and around the display edge, in points.
    @Published var gapSize: Double {
        didSet { defaults.set(gapSize, forKey: Key.gapSize) }
    }
    /// ⌃⌥⌘+arrow with no display on that side falls back to next/previous instead of beeping.
    @Published var cycleDisplaysWhenNoNeighbour: Bool {
        didSet { defaults.set(cycleDisplaysWhenNoNeighbour, forKey: Key.cycleDisplaysWhenNoNeighbour) }
    }
    @Published var restoreWindowsOnReconnect: Bool {
        didSet { defaults.set(restoreWindowsOnReconnect, forKey: Key.restoreWindowsOnReconnect) }
    }
    /// Focusing another display also moves the pointer there, so Space shortcuts follow.
    @Published var movePointerWithFocus: Bool {
        didSet { defaults.set(movePointerWithFocus, forKey: Key.movePointerWithFocus) }
    }
    /// Replace the animated three-finger swipe between Spaces with an instant switch.
    @Published var instantTrackpadSwipes: Bool {
        didSet { defaults.set(instantTrackpadSwipes, forKey: Key.instantTrackpadSwipes) }
    }
    @Published var showSpaceHUD: Bool {
        didSet { defaults.set(showSpaceHUD, forKey: Key.showSpaceHUD) }
    }
    @Published var showSpaceNumberInMenuBar: Bool {
        didSet { defaults.set(showSpaceNumberInMenuBar, forKey: Key.showSpaceNumberInMenuBar) }
    }
    /// Look for a new GitHub release once a day.
    @Published var automaticallyCheckForUpdates: Bool {
        didSet { defaults.set(automaticallyCheckForUpdates, forKey: Key.automaticallyCheckForUpdates) }
    }
    /// Install a new release without asking, once the keyboard and mouse have been idle for a while.
    @Published var automaticallyInstallUpdates: Bool {
        didSet { defaults.set(automaticallyInstallUpdates, forKey: Key.automaticallyInstallUpdates) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bindings = Self.loadBindings(from: defaults)
        repeatBehavior = defaults.string(forKey: Key.repeatBehavior).flatMap(RepeatBehavior.init) ?? .moveAcrossDisplays
        gapSize = defaults.double(forKey: Key.gapSize)
        cycleDisplaysWhenNoNeighbour = defaults.object(forKey: Key.cycleDisplaysWhenNoNeighbour) as? Bool ?? true
        restoreWindowsOnReconnect = defaults.object(forKey: Key.restoreWindowsOnReconnect) as? Bool ?? true
        movePointerWithFocus = defaults.object(forKey: Key.movePointerWithFocus) as? Bool ?? true
        instantTrackpadSwipes = defaults.bool(forKey: Key.instantTrackpadSwipes)
        showSpaceHUD = defaults.bool(forKey: Key.showSpaceHUD)
        showSpaceNumberInMenuBar = defaults.object(forKey: Key.showSpaceNumberInMenuBar) as? Bool ?? true
        automaticallyCheckForUpdates = defaults.object(forKey: Key.automaticallyCheckForUpdates) as? Bool ?? true
        automaticallyInstallUpdates = defaults.object(forKey: Key.automaticallyInstallUpdates) as? Bool ?? true
    }

    func completeFirstLaunch() {
        saveBindings()
        defaults.set(true, forKey: Key.didCompleteFirstLaunch)
    }

    // MARK: - Shortcuts

    /// Binds `shortcut` to `command` (nil clears it). A shortcut can only do one thing, so any other
    /// command already using it is unbound; that command is returned so the UI can say so.
    @discardableResult
    func setShortcut(_ shortcut: Shortcut?, for command: Command) -> Command? {
        var displaced: Command?
        if let shortcut, let owner = bindings.first(where: { $0.value == shortcut && $0.key != command })?.key {
            bindings[owner] = nil
            displaced = owner
        }
        bindings[command] = shortcut
        saveBindings()
        return displaced
    }

    func resetShortcutsToDefaults() {
        bindings = Command.defaultBindings
        saveBindings()
    }

    /// Stored as `[rawValue: Shortcut?]` covering every command known at save time, so a cleared
    /// shortcut (null) stays cleared while commands added in later versions still get their default.
    private func saveBindings() {
        let stored: [String: Shortcut?] = Dictionary(uniqueKeysWithValues: Command.allCases.map { ($0.rawValue, bindings[$0]) })
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Key.bindings)
        }
    }

    private static func loadBindings(from defaults: UserDefaults) -> [Command: Shortcut] {
        guard let data = defaults.data(forKey: Key.bindings),
              let stored = try? JSONDecoder().decode([String: Shortcut?].self, from: data)
        else { return Command.defaultBindings }

        var bindings: [Command: Shortcut] = [:]
        for (raw, shortcut) in stored {
            if let command = Command(rawValue: raw), let shortcut { bindings[command] = shortcut }
        }
        let taken = Set(bindings.values)
        for command in Command.allCases where !stored.keys.contains(command.rawValue) {
            if let fallback = command.defaultShortcut, !taken.contains(fallback) { bindings[command] = fallback }
        }
        return bindings
    }
}
