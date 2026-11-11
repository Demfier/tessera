import AppKit

/// When a display sleeps or disconnects for more than a few seconds, macOS herds its windows onto
/// the remaining display and doesn't reliably send them back. This remembers which windows lived on
/// each display and returns them when that display reappears (Second Display Pro's "put windows back").
@MainActor
final class DisplayReconnectRestorer {
    var isEnabled = true

    private struct WindowRecord: Sendable {
        let windowID: CGWindowID
        let pid: pid_t
        /// Frame relative to the display's top-left corner.
        let offset: CGRect
    }

    private struct Snapshot: Sendable {
        let uuid: String
        let records: [WindowRecord]
    }

    /// Brief blips (cable wiggle, mode switch) don't make macOS move windows, so ignore them.
    private static let minimumAbsence: TimeInterval = 3
    /// macOS keeps rearranging windows for a moment after a display returns; let it finish first.
    private static let settleDelay: Duration = .seconds(2)
    private static let refreshInterval: TimeInterval = 5

    private static weak var active: DisplayReconnectRestorer?

    private var latest: [CGDirectDisplayID: Snapshot] = [:]
    private var departed: [String: (records: [WindowRecord], at: Date)] = [:]
    private var refreshTimer: Timer?

    func start() {
        guard Self.active == nil else { return }
        Self.active = self
        latest = Self.captureSnapshots()
        // Periodic snapshots are the fallback; the reconfiguration callback below captures one more
        // right before displays change, while windows are still where the user left them.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.merge(Self.captureSnapshots()) }
        }
        CGDisplayRegisterReconfigurationCallback({ displayID, flags, _ in
            // Window lists are safe to read off the main thread, and this must happen synchronously.
            let snapshot = flags.contains(.beginConfigurationFlag) ? DisplayReconnectRestorer.captureSnapshots() : nil
            let rawFlags = flags.rawValue
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    DisplayReconnectRestorer.active?.handle(displayID: displayID,
                                                           flags: CGDisplayChangeSummaryFlags(rawValue: rawFlags),
                                                           snapshot: snapshot)
                }
            }
        }, nil)
    }

    private func handle(displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags,
                        snapshot: [CGDirectDisplayID: Snapshot]?) {
        if let snapshot {
            merge(snapshot)
            return
        }
        // Some monitors report sleep/wake as disabled/enabled rather than removed/added.
        if !flags.isDisjoint(with: [.removeFlag, .disabledFlag]), let gone = latest[displayID] {
            departed[gone.uuid] = (gone.records, Date())
            latest[displayID] = nil
        }
        if !flags.isDisjoint(with: [.addFlag, .enabledFlag]), let uuid = Self.uuid(of: displayID),
           let gone = departed.removeValue(forKey: uuid),
           Date().timeIntervalSince(gone.at) >= Self.minimumAbsence, isEnabled {
            Task {
                try? await Task.sleep(for: Self.settleDelay)
                self.restore(gone.records, toDisplayWithUUID: uuid)
                self.merge(Self.captureSnapshots())
            }
        }
    }

    /// Merge rather than replace: a refresh that lands just after a display vanished must not wipe
    /// its last snapshot before the removal callback claims it. Only removal deletes an entry.
    private func merge(_ snapshot: [CGDirectDisplayID: Snapshot]) {
        latest.merge(snapshot) { _, new in new }
    }

    private func restore(_ records: [WindowRecord], toDisplayWithUUID uuid: String) {
        guard isEnabled, AXIsProcessTrusted(),
              let displayID = Self.activeDisplays().first(where: { Self.uuid(of: $0) == uuid })
        else { return }
        let bounds = CGDisplayBounds(displayID)
        for (pid, windowRecords) in Dictionary(grouping: records, by: \.pid) {
            let windows = AXWindow.windows(of: pid)
            for record in windowRecords {
                guard let window = windows.first(where: { $0.windowID == record.windowID }),
                      !window.isFullscreen, !window.isMinimized,
                      let frame = window.frame,
                      !bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) // already back
                else { continue }
                let size = CGSize(width: min(record.offset.width, bounds.width),
                                  height: min(record.offset.height, bounds.height))
                let origin = CGPoint(x: min(bounds.minX + record.offset.minX, bounds.maxX - size.width),
                                     y: min(bounds.minY + record.offset.minY, bounds.maxY - size.height))
                window.setFrame(CGRect(origin: origin, size: size))
            }
        }
    }

    // MARK: - Snapshots (thread-safe: Quartz only, no AppKit or AX)

    private nonisolated static func captureSnapshots() -> [CGDirectDisplayID: Snapshot] {
        let displays = activeDisplays().map { ($0, CGDisplayBounds($0)) }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPID = getpid()

        var records: [CGDirectDisplayID: [WindowRecord]] = [:]
        for window in info {
            guard window[kCGWindowLayer as String] as? Int == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let windowID = window[kCGWindowNumber as String] as? CGWindowID,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict),
                  let (displayID, bounds) = displays.first(where: { $0.1.contains(CGPoint(x: rect.midX, y: rect.midY)) })
            else { continue }
            let offset = rect.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            records[displayID, default: []].append(WindowRecord(windowID: windowID, pid: pid, offset: offset))
        }
        return displays.reduce(into: [:]) { result, display in
            guard let uuid = uuid(of: display.0) else { return }
            result[display.0] = Snapshot(uuid: uuid, records: records[display.0] ?? [])
        }
    }

    private nonisolated static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// Display IDs can be reassigned on reconnect; the UUID is what identifies the physical display.
    private nonisolated static func uuid(of displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
