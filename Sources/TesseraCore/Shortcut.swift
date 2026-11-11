import Foundation

/// Modifier keys, stored in Carbon's bit layout so they can be handed straight to `RegisterEventHotKey`.
public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let command = Modifiers(rawValue: 1 << 8)  // cmdKey
    public static let shift = Modifiers(rawValue: 1 << 9)    // shiftKey
    public static let option = Modifiers(rawValue: 1 << 11)  // optionKey
    public static let control = Modifiers(rawValue: 1 << 12) // controlKey

    /// Bits of `NSEvent.ModifierFlags` (kept as raw values so this module stays AppKit-free).
    private static let cocoaPairs: [(cocoa: UInt, carbon: Modifiers)] = [
        (1 << 17, .shift), (1 << 18, .control), (1 << 19, .option), (1 << 20, .command),
    ]

    public init(cocoaFlags: UInt) {
        self = Self.cocoaPairs.reduce(into: []) { result, pair in
            if cocoaFlags & pair.cocoa != 0 { result.insert(pair.carbon) }
        }
    }

    public var cocoaFlags: UInt {
        Self.cocoaPairs.reduce(0) { contains($1.carbon) ? $0 | $1.cocoa : $0 }
    }

    /// Symbols in Apple's canonical order: ⌃⌥⇧⌘.
    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// A global keyboard shortcut: a virtual key code (layout-independent) plus modifiers.
public struct Shortcut: Hashable, Codable, Sendable, CustomStringConvertible {
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(_ modifiers: Modifiers, _ keyCode: UInt16) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var description: String { modifiers.symbols + KeyCode.name(for: keyCode) }

    /// A global hotkey swallows its key combination everywhere. ⇧ and ⌥ alone still produce typed
    /// characters (capitals, accents), so require ⌃ or ⌘ — except for function keys, which type nothing.
    public var isUsableAsGlobalHotkey: Bool {
        !modifiers.isDisjoint(with: [.control, .command]) || KeyCode.isFunctionKey(keyCode)
    }
}

/// Virtual key codes (`kVK_*` from Carbon's Events.h) and their display names on an ANSI layout.
public enum KeyCode {
    public static let a: UInt16 = 0x00, s: UInt16 = 0x01, d: UInt16 = 0x02, f: UInt16 = 0x03
    public static let h: UInt16 = 0x04, g: UInt16 = 0x05, z: UInt16 = 0x06, x: UInt16 = 0x07
    public static let c: UInt16 = 0x08, v: UInt16 = 0x09, b: UInt16 = 0x0B, q: UInt16 = 0x0C
    public static let w: UInt16 = 0x0D, e: UInt16 = 0x0E, r: UInt16 = 0x0F, y: UInt16 = 0x10
    public static let t: UInt16 = 0x11, o: UInt16 = 0x1F, u: UInt16 = 0x20, i: UInt16 = 0x22
    public static let p: UInt16 = 0x23, l: UInt16 = 0x25, j: UInt16 = 0x26, k: UInt16 = 0x28
    public static let n: UInt16 = 0x2D, m: UInt16 = 0x2E
    public static let digit1: UInt16 = 0x12, digit2: UInt16 = 0x13, digit3: UInt16 = 0x14
    public static let digit4: UInt16 = 0x15, digit5: UInt16 = 0x17, digit6: UInt16 = 0x16
    public static let digit7: UInt16 = 0x1A, digit8: UInt16 = 0x1C, digit9: UInt16 = 0x19
    public static let digit0: UInt16 = 0x1D
    public static let equal: UInt16 = 0x18, minus: UInt16 = 0x1B
    public static let returnKey: UInt16 = 0x24, tab: UInt16 = 0x30, space: UInt16 = 0x31
    public static let delete: UInt16 = 0x33, escape: UInt16 = 0x35, forwardDelete: UInt16 = 0x75
    public static let keypadPlus: UInt16 = 0x45, keypadEnter: UInt16 = 0x4C
    public static let leftArrow: UInt16 = 0x7B, rightArrow: UInt16 = 0x7C
    public static let downArrow: UInt16 = 0x7D, upArrow: UInt16 = 0x7E

    /// Digit keys 1…9 then 0, in keyboard order.
    public static let digitRow: [UInt16] = [digit1, digit2, digit3, digit4, digit5, digit6, digit7, digit8, digit9, digit0]

    private static let functionKeys: [UInt16: String] = [
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16", 0x40: "F17", 0x4F: "F18",
        0x50: "F19", 0x5A: "F20",
    ]

    private static let names: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y",
        0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O", 0x20: "U",
        0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`",
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x41: "Keypad .", 0x43: "Keypad *", 0x45: "Keypad +", 0x47: "Keypad Clear",
        0x4B: "Keypad /", 0x4C: "Keypad ↩", 0x4E: "Keypad -", 0x51: "Keypad =",
        0x52: "Keypad 0", 0x53: "Keypad 1", 0x54: "Keypad 2", 0x55: "Keypad 3", 0x56: "Keypad 4",
        0x57: "Keypad 5", 0x58: "Keypad 6", 0x59: "Keypad 7", 0x5B: "Keypad 8", 0x5C: "Keypad 9",
    ]

    public static func name(for keyCode: UInt16) -> String {
        functionKeys[keyCode] ?? names[keyCode] ?? "Key \(keyCode)"
    }

    public static func isFunctionKey(_ keyCode: UInt16) -> Bool { functionKeys[keyCode] != nil }

    /// The `NSMenuItem.keyEquivalent` string for a key, so menus can display the bound shortcut.
    /// Returns nil for keys a menu can't render (the shortcut still works; it just isn't shown).
    public static func menuKeyEquivalent(for keyCode: UInt16) -> String? {
        let special: [UInt16: Unicode.Scalar] = [
            leftArrow: "\u{F702}", rightArrow: "\u{F703}", upArrow: "\u{F700}", downArrow: "\u{F701}",
            returnKey: "\r", delete: "\u{08}", forwardDelete: "\u{F728}", tab: "\t", escape: "\u{1B}",
            space: " ",
        ]
        if let scalar = special[keyCode] { return String(Character(scalar)) }
        let fKeyBase: UInt32 = 0xF704 // NSF1FunctionKey
        if let name = functionKeys[keyCode], let n = UInt32(name.dropFirst()),
           let scalar = Unicode.Scalar(fKeyBase + n - 1) {
            return String(Character(scalar))
        }
        guard let name = names[keyCode], name.count == 1 else { return nil }
        return name.lowercased()
    }
}
