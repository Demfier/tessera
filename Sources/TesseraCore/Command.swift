import Foundation

public enum Direction: Sendable, Equatable {
    case left, right, up, down
}

/// Every action Tessera can bind to a shortcut. Raw values are persisted — never rename a case.
/// Window-action raw values match Rectangle's action names.
public enum Command: String, CaseIterable, Codable, Sendable {
    // Halves
    case leftHalf, rightHalf, centerHalf, topHalf, bottomHalf
    // Corners
    case topLeft, topRight, bottomLeft, bottomRight
    // Thirds
    case firstThird, centerThird, lastThird, firstTwoThirds, centerTwoThirds, lastTwoThirds
    // Fourths
    case firstFourth, secondFourth, thirdFourth, lastFourth
    case firstThreeFourths, centerThreeFourths, lastThreeFourths
    // Sixths
    case topLeftSixth, topCenterSixth, topRightSixth, bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    // Size
    case maximize, almostMaximize, maximizeHeight, maximizeWidth, center, larger, smaller, restore
    // Move to an edge without resizing
    case moveLeft, moveRight, moveUp, moveDown
    // Displays
    case displayLeft, displayRight, displayUp, displayDown, nextDisplay, previousDisplay
    case toggleFullscreen
    // Keyboard focus (and the pointer) to another display
    case focusDisplayLeft, focusDisplayRight, focusDisplayUp, focusDisplayDown
    case focusNextDisplay, focusPreviousDisplay
    // Spaces
    case spaceLeft, spaceRight
    case space1, space2, space3, space4, space5, space6, space7, space8, space9, space10
    case lastSpace

    public enum Group: String, CaseIterable, Sendable {
        case halves = "Halves"
        case corners = "Corners"
        case thirds = "Thirds"
        case fourths = "Fourths"
        case sixths = "Sixths"
        case size = "Size"
        case move = "Move to Edge"
        case displays = "Displays & Full Screen"
        case focus = "Focus Display"
        case spaces = "Spaces"
    }

    /// What executing a command means, independent of its name.
    public enum Kind: Equatable, Sendable {
        /// Compute a new frame on the window's current display (see `Layout`).
        case layout
        /// Put the window back where it was before Tessera first touched it.
        case restore
        /// Move to another display; full-screen windows are carried over and stay full screen.
        case display(DisplayTarget)
        case toggleFullscreen
        /// Focus the front-most window on another display, without moving anything.
        case focusDisplay(DisplayTarget)
        case spaceStep(Direction)
        /// Zero-based space index on the display under the cursor.
        case spaceIndex(Int)
        case lastSpace
    }

    public var kind: Kind {
        switch self {
        case .restore: .restore
        case .displayLeft: .display(.direction(.left))
        case .displayRight: .display(.direction(.right))
        case .displayUp: .display(.direction(.up))
        case .displayDown: .display(.direction(.down))
        case .nextDisplay: .display(.next)
        case .previousDisplay: .display(.previous)
        case .toggleFullscreen: .toggleFullscreen
        case .focusDisplayLeft: .focusDisplay(.direction(.left))
        case .focusDisplayRight: .focusDisplay(.direction(.right))
        case .focusDisplayUp: .focusDisplay(.direction(.up))
        case .focusDisplayDown: .focusDisplay(.direction(.down))
        case .focusNextDisplay: .focusDisplay(.next)
        case .focusPreviousDisplay: .focusDisplay(.previous)
        case .spaceLeft: .spaceStep(.left)
        case .spaceRight: .spaceStep(.right)
        case .lastSpace: .lastSpace
        default:
            if let index = Self.spaceCommands.firstIndex(of: self) { .spaceIndex(index) } else { .layout }
        }
    }

    public static let spaceCommands: [Command] = [
        .space1, .space2, .space3, .space4, .space5, .space6, .space7, .space8, .space9, .space10,
    ]

    public var group: Group {
        switch self {
        case .leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf: .halves
        case .topLeft, .topRight, .bottomLeft, .bottomRight: .corners
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds: .thirds
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth,
             .firstThreeFourths, .centerThreeFourths, .lastThreeFourths: .fourths
        case .topLeftSixth, .topCenterSixth, .topRightSixth,
             .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth: .sixths
        case .maximize, .almostMaximize, .maximizeHeight, .maximizeWidth,
             .center, .larger, .smaller, .restore: .size
        case .moveLeft, .moveRight, .moveUp, .moveDown: .move
        case .displayLeft, .displayRight, .displayUp, .displayDown,
             .nextDisplay, .previousDisplay, .toggleFullscreen: .displays
        case .focusDisplayLeft, .focusDisplayRight, .focusDisplayUp, .focusDisplayDown,
             .focusNextDisplay, .focusPreviousDisplay: .focus
        case .spaceLeft, .spaceRight, .space1, .space2, .space3, .space4, .space5,
             .space6, .space7, .space8, .space9, .space10, .lastSpace: .spaces
        }
    }

    public var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .centerHalf: "Center Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .firstThird: "First Third"
        case .centerThird: "Center Third"
        case .lastThird: "Last Third"
        case .firstTwoThirds: "First Two Thirds"
        case .centerTwoThirds: "Center Two Thirds"
        case .lastTwoThirds: "Last Two Thirds"
        case .firstFourth: "First Fourth"
        case .secondFourth: "Second Fourth"
        case .thirdFourth: "Third Fourth"
        case .lastFourth: "Last Fourth"
        case .firstThreeFourths: "First Three Fourths"
        case .centerThreeFourths: "Center Three Fourths"
        case .lastThreeFourths: "Last Three Fourths"
        case .topLeftSixth: "Top Left Sixth"
        case .topCenterSixth: "Top Center Sixth"
        case .topRightSixth: "Top Right Sixth"
        case .bottomLeftSixth: "Bottom Left Sixth"
        case .bottomCenterSixth: "Bottom Center Sixth"
        case .bottomRightSixth: "Bottom Right Sixth"
        case .maximize: "Maximize"
        case .almostMaximize: "Almost Maximize"
        case .maximizeHeight: "Maximize Height"
        case .maximizeWidth: "Maximize Width"
        case .center: "Center"
        case .larger: "Make Larger"
        case .smaller: "Make Smaller"
        case .restore: "Restore"
        case .moveLeft: "Move Left"
        case .moveRight: "Move Right"
        case .moveUp: "Move Up"
        case .moveDown: "Move Down"
        case .displayLeft: "Move to Display on Left"
        case .displayRight: "Move to Display on Right"
        case .displayUp: "Move to Display Above"
        case .displayDown: "Move to Display Below"
        case .nextDisplay: "Move to Next Display"
        case .previousDisplay: "Move to Previous Display"
        case .toggleFullscreen: "Toggle Full Screen"
        case .focusDisplayLeft: "Focus Display on Left"
        case .focusDisplayRight: "Focus Display on Right"
        case .focusDisplayUp: "Focus Display Above"
        case .focusDisplayDown: "Focus Display Below"
        case .focusNextDisplay: "Focus Next Display"
        case .focusPreviousDisplay: "Focus Previous Display"
        case .spaceLeft: "Switch to Space on Left"
        case .spaceRight: "Switch to Space on Right"
        case .lastSpace: "Switch to Last Used Space"
        default:
            if case .spaceIndex(let i) = kind { "Switch to Space \(i + 1)" } else { rawValue }
        }
    }

    /// Defaults: Rectangle's recommended (⌃⌥) set, Second Display Pro's ⌃⌥⌘+arrows for displays,
    /// and InstantSpaceSwitcher's ⌃⌥⌘+digit for jumping to a space. Space left/right uses ⌃⌥⇧+arrows
    /// because ISS's own default (⌃⌥⌘+arrows) is taken by the display moves. Focusing a display is
    /// the display move plus ⇧: same arrow, "go there yourself" instead of "send the window".
    public var defaultShortcut: Shortcut? {
        let ctrlOpt: Modifiers = [.control, .option]
        let hyper: Modifiers = [.control, .option, .command]
        let hyperShift: Modifiers = [.control, .option, .shift, .command]
        switch self {
        case .leftHalf: return Shortcut(ctrlOpt, KeyCode.leftArrow)
        case .rightHalf: return Shortcut(ctrlOpt, KeyCode.rightArrow)
        case .topHalf: return Shortcut(ctrlOpt, KeyCode.upArrow)
        case .bottomHalf: return Shortcut(ctrlOpt, KeyCode.downArrow)
        case .topLeft: return Shortcut(ctrlOpt, KeyCode.u)
        case .topRight: return Shortcut(ctrlOpt, KeyCode.i)
        case .bottomLeft: return Shortcut(ctrlOpt, KeyCode.j)
        case .bottomRight: return Shortcut(ctrlOpt, KeyCode.k)
        case .firstThird: return Shortcut(ctrlOpt, KeyCode.d)
        case .centerThird: return Shortcut(ctrlOpt, KeyCode.f)
        case .lastThird: return Shortcut(ctrlOpt, KeyCode.g)
        case .firstTwoThirds: return Shortcut(ctrlOpt, KeyCode.e)
        case .lastTwoThirds: return Shortcut(ctrlOpt, KeyCode.t)
        case .maximize: return Shortcut(ctrlOpt, KeyCode.returnKey)
        case .maximizeHeight: return Shortcut([.control, .option, .shift], KeyCode.upArrow)
        case .center: return Shortcut(ctrlOpt, KeyCode.c)
        case .larger: return Shortcut(ctrlOpt, KeyCode.equal)
        case .smaller: return Shortcut(ctrlOpt, KeyCode.minus)
        case .restore: return Shortcut(ctrlOpt, KeyCode.delete)
        case .displayLeft: return Shortcut(hyper, KeyCode.leftArrow)
        case .displayRight: return Shortcut(hyper, KeyCode.rightArrow)
        case .displayUp: return Shortcut(hyper, KeyCode.upArrow)
        case .displayDown: return Shortcut(hyper, KeyCode.downArrow)
        case .focusDisplayLeft: return Shortcut(hyperShift, KeyCode.leftArrow)
        case .focusDisplayRight: return Shortcut(hyperShift, KeyCode.rightArrow)
        case .focusDisplayUp: return Shortcut(hyperShift, KeyCode.upArrow)
        case .focusDisplayDown: return Shortcut(hyperShift, KeyCode.downArrow)
        case .spaceLeft: return Shortcut([.control, .option, .shift], KeyCode.leftArrow)
        case .spaceRight: return Shortcut([.control, .option, .shift], KeyCode.rightArrow)
        case .lastSpace: return Shortcut(hyper, KeyCode.keypadPlus)
        default:
            if case .spaceIndex(let i) = kind { return Shortcut(hyper, KeyCode.digitRow[i]) }
            return nil
        }
    }

    public static var defaultBindings: [Command: Shortcut] {
        allCases.reduce(into: [:]) { map, command in
            if let shortcut = command.defaultShortcut { map[command] = shortcut }
        }
    }
}

public enum DisplayTarget: Equatable, Sendable {
    /// The display physically on that side, per System Settings › Displays arrangement.
    case direction(Direction)
    /// Displays ordered left-to-right (then top-to-bottom), wrapping around.
    case next, previous
}
