import AppKit
import Combine
import TesseraCore

/// The menu-bar item: shows the current Space number and lists every action with its shortcut.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    struct Actions {
        let perform: (Command) -> Void
        let openSettings: () -> Void
        let requestAccessibility: () -> Void
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings: Settings
    private let spaces: SpaceController
    private let permissions: Permissions
    private let actions: Actions
    private var cancellables = Set<AnyCancellable>()

    /// Groups shown inline at the top level; the rest get a submenu each.
    private static let inlineGroups: [Command.Group] = [.halves, .displays]

    init(settings: Settings, spaces: SpaceController, permissions: Permissions, actions: Actions) {
        self.settings = settings
        self.spaces = spaces
        self.permissions = permissions
        self.actions = actions
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false // items are enabled explicitly from the permission state
        statusItem.menu = menu
        statusItem.button?.toolTip = "Tessera"

        Publishers.CombineLatest3(spaces.$status, settings.$showSpaceNumberInMenuBar, permissions.$isTrusted)
            .receive(on: RunLoop.main)
            .sink { [weak self] status, showNumber, trusted in
                self?.updateIcon(spaceNumber: showNumber ? status.map { $0.index + 1 } : nil, warning: !trusted)
            }
            .store(in: &cancellables)
    }

    // MARK: Icon

    private func updateIcon(spaceNumber: Int?, warning: Bool) {
        statusItem.button?.image = Self.icon(spaceNumber: spaceNumber, warning: warning)
    }

    /// A template image: a 2×2 tile glyph, or the Space number in a rounded square.
    private static func icon(spaceNumber: Int?, warning: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            let box = NSRect(x: 0.75, y: 0.75, width: size.width - 1.5, height: size.height - 1.5)
            let path = NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5)
            path.lineWidth = 1.5
            NSColor.black.setStroke()
            NSColor.black.setFill()
            if let spaceNumber {
                path.stroke()
                let text = NSAttributedString(string: "\(spaceNumber)", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: spaceNumber > 9 ? 9 : 11, weight: .bold),
                    .foregroundColor: NSColor.black,
                ])
                let textSize = text.size()
                text.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
            } else {
                // Four tiles, echoing the app's name.
                let gap: CGFloat = 1.5
                let w = (box.width - gap) / 2, h = (box.height - gap) / 2
                for (col, row) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                    let tile = NSRect(x: box.minX + CGFloat(col) * (w + gap), y: box.minY + CGFloat(row) * (h + gap),
                                      width: w, height: h)
                    NSBezierPath(roundedRect: tile, xRadius: 1.5, yRadius: 1.5).fill()
                }
            }
            if warning {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: size.width - 6, y: size.height - 6, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = spaceNumber.map { "Tessera, Space \($0)" } ?? "Tessera"
        return image
    }

    // MARK: Menu

    /// Rebuilt on every open so shortcuts, Space list and permission state are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !permissions.isTrusted {
            menu.addItem(item("Grant Accessibility Access…", action: #selector(requestAccessibility)))
            let note = NSMenuItem(title: "Tessera can't move windows or switch Spaces until then.", action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
            menu.addItem(.separator())
        }

        for group in Self.inlineGroups {
            for command in Command.allCases where command.group == group { menu.addItem(commandItem(command)) }
            if group == .halves {
                for command in [Command.maximize, .center, .restore] { menu.addItem(commandItem(command)) }
            }
            menu.addItem(.separator())
        }

        for group in Command.Group.allCases where !Self.inlineGroups.contains(group) && group != .spaces {
            let submenu = NSMenu()
            for command in Command.allCases where command.group == group { submenu.addItem(commandItem(command)) }
            let parent = NSMenuItem(title: group.rawValue, action: nil, keyEquivalent: "")
            parent.submenu = submenu
            menu.addItem(parent)
        }
        menu.addItem(spacesItem())
        menu.addItem(.separator())

        let settingsItem = item("Settings…", action: #selector(openSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        let quit = NSMenuItem(title: "Quit Tessera", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func spacesItem() -> NSMenuItem {
        let submenu = NSMenu()
        for command in [Command.spaceLeft, .spaceRight, .lastSpace] { submenu.addItem(commandItem(command)) }
        submenu.addItem(.separator())
        let count = min(spaces.status?.count ?? Command.spaceCommands.count, Command.spaceCommands.count)
        for command in Command.spaceCommands.prefix(count) {
            let item = commandItem(command)
            if case .spaceIndex(let index) = command.kind, index == spaces.status?.index { item.state = .on }
            submenu.addItem(item)
        }
        let parent = NSMenuItem(title: Command.Group.spaces.rawValue, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func commandItem(_ command: Command) -> NSMenuItem {
        let item = item(command.title, action: #selector(performCommand(_:)))
        item.representedObject = command.rawValue
        // Shown for reference only — the status menu never handles key equivalents itself.
        if let shortcut = settings.bindings[command], let key = KeyCode.menuKeyEquivalent(for: shortcut.keyCode) {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: shortcut.modifiers.cocoaFlags)
        }
        item.isEnabled = permissions.isTrusted
        return item
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let command = Command(rawValue: raw) else { return }
        actions.perform(command)
    }

    @objc private func openSettings() { actions.openSettings() }
    @objc private func requestAccessibility() { actions.requestAccessibility() }
}
