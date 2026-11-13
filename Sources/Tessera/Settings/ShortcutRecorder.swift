import AppKit
import Combine
import TesseraCore

/// Captures the next key combination typed in the Settings window and binds it to a command.
/// Global hotkeys are suspended meanwhile, otherwise pressing an already-bound combination would
/// trigger its action instead of being recorded.
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var recording: Command?
    /// Modifiers currently held, for live feedback while recording.
    @Published private(set) var heldModifiers: Modifiers = []
    /// Feedback from the last recording, e.g. that a shortcut was taken over from another command.
    @Published var message: String?

    private let settings: Settings
    private let hotkeys: HotkeyCenter
    private var monitor: Any?

    init(settings: Settings, hotkeys: HotkeyCenter) {
        self.settings = settings
        self.hotkeys = hotkeys
    }

    func toggle(_ command: Command) {
        if recording == command { stop() } else { start(command) }
    }

    func start(_ command: Command) {
        stop()
        recording = command
        message = nil
        hotkeys.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording != nil else { return }
        recording = nil
        heldModifiers = []
        hotkeys.resume()
    }

    /// Returns true when the event was consumed by the recorder.
    private func handle(_ event: NSEvent) -> Bool {
        guard let command = recording else { return false }
        let modifiers = Modifiers(cocoaFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
            .intersection([.control, .option, .shift, .command])
        if event.type == .flagsChanged {
            heldModifiers = modifiers
            return true
        }

        switch (event.keyCode, modifiers.isEmpty) {
        case (KeyCode.escape, true):
            stop()
        case (KeyCode.delete, true), (KeyCode.forwardDelete, true):
            settings.setShortcut(nil, for: command)
            stop()
        default:
            let shortcut = Shortcut(modifiers, event.keyCode)
            guard shortcut.isUsableAsGlobalHotkey else {
                message = "Include ⌃ or ⌘. A shortcut with only ⇧ or ⌥ would block normal typing."
                NSSound.beep()
                return true
            }
            if let displaced = settings.setShortcut(shortcut, for: command) {
                message = "\(shortcut) was taken from “\(displaced.title)”, which is now unassigned."
            }
            stop()
        }
        return true
    }
}
