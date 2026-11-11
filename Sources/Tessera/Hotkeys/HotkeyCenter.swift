import Carbon
import Combine
import TesseraCore

/// Registers system-wide hotkeys through Carbon's `RegisterEventHotKey` — the same mechanism
/// Rectangle uses. It needs no permission, and the key press never reaches the frontmost app.
@MainActor
final class HotkeyCenter: ObservableObject {
    /// Commands whose shortcut could not be registered (usually: another app already owns it).
    @Published private(set) var failedCommands: Set<Command> = []

    var onCommand: ((Command) -> Void)?

    private nonisolated static let signature: OSType = 0x5453_5241 // 'TSRA'
    private var bindings: [Command: Shortcut] = [:]
    private var registered: [UInt32: (ref: EventHotKeyRef, command: Command)] = [:]
    private var handlerRef: EventHandlerRef?
    private var isSuspended = false

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotkeyCenter.signature else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon dispatches hotkey events on the main thread's event loop.
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { center.dispatch(hotKeyID.id) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        assert(status == noErr, "InstallEventHandler failed: \(status)")
    }

    func update(_ bindings: [Command: Shortcut]) {
        self.bindings = bindings
        if !isSuspended { registerAll() }
    }

    /// Releases every hotkey so a shortcut recorder can capture combinations that are already bound.
    func suspend() {
        isSuspended = true
        unregisterAll()
    }

    func resume() {
        isSuspended = false
        registerAll()
    }

    private func registerAll() {
        unregisterAll()
        var failed: Set<Command> = []
        // Sorted so hotkey IDs are stable between registrations (useful when debugging).
        for (index, (command, shortcut)) in bindings.sorted(by: { $0.key.rawValue < $1.key.rawValue }).enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.modifiers.rawValue,
                                             EventHotKeyID(signature: Self.signature, id: id),
                                             GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[id] = (ref, command)
            } else {
                failed.insert(command)
            }
        }
        if failed != failedCommands { failedCommands = failed }
    }

    private func unregisterAll() {
        for entry in registered.values { UnregisterEventHotKey(entry.ref) }
        registered.removeAll()
    }

    private func dispatch(_ id: UInt32) {
        guard let command = registered[id]?.command else { return }
        onCommand?(command)
    }
}
