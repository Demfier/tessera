import TesseraCore

/// Sends each command to the controller that carries it out. The switch is exhaustive on purpose:
/// a new kind of command can't be added without deciding who runs it.
@MainActor
struct CommandRouter {
    let windows: WindowController
    let spaces: SpaceController
    let focus: DisplayFocusController

    func perform(_ command: Command) {
        switch command.kind {
        case .layout, .restore, .display, .toggleFullscreen:
            windows.perform(command)
        case .focusDisplay(let target):
            focus.focus(target)
        case .spaceStep, .spaceIndex, .lastSpace:
            spaces.perform(command)
        }
    }
}
