import CoreGraphics
import Testing
@testable import TesseraCore

/// The real setup this was built for: MacBook (menu bar 33pt) with a 1920×1080 display to its right.
/// Coordinates are top-left origin, as the Accessibility API reports them.
private let laptop = Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                             visible: CGRect(x: 0, y: 33, width: 1512, height: 949))
private let external = Display(id: 2, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
                               visible: CGRect(x: 1512, y: 25, width: 1920, height: 1055))
private let displays = [laptop, external]
private let someWindow = CGRect(x: 200, y: 200, width: 800, height: 500)

private func layout(_ command: Command, window: CGRect = someWindow, on current: Int = 0,
                    last: Placement? = nil, behavior: RepeatBehavior = .moveAcrossDisplays,
                    gap: CGFloat = 0) -> LayoutResult? {
    Layout.compute(command, window: window, displays: displays, current: current,
                   last: last, behavior: behavior, gap: gap)
}

/// Simulates pressing a shortcut, then the window settling exactly where it was put.
private func press(_ command: Command, after previous: LayoutResult?, behavior: RepeatBehavior) -> LayoutResult? {
    let last = previous.flatMap { r in r.command.map { Placement(command: $0, variant: r.variant, rect: r.rect) } }
    return layout(command, window: previous?.rect ?? someWindow, on: previous?.display ?? 0,
                  last: last, behavior: behavior)
}

@Suite struct HalvesAndRepeats {
    @Test func leftHalfFillsLeftOfVisibleFrame() {
        let r = layout(.leftHalf)
        #expect(r?.rect == CGRect(x: 0, y: 33, width: 756, height: 949))
        #expect(r?.display == 0)
    }

    @Test func repeatedLeftHalfWalksAcrossDisplays() {
        // Rectangle's "move across displays": left half again → right half of the display to the left
        // (wrapping), and pressing again continues walking left.
        let first = press(.leftHalf, after: nil, behavior: .moveAcrossDisplays)
        let second = press(.leftHalf, after: first, behavior: .moveAcrossDisplays)
        #expect(second?.display == 1)
        #expect(second?.command == .rightHalf)
        #expect(second?.rect == CGRect(x: 1512 + 960, y: 25, width: 960, height: 1055))
        // The window is now "right half" — pressing left is a fresh left half on the same display.
        let third = press(.leftHalf, after: second, behavior: .moveAcrossDisplays)
        #expect(third?.display == 1)
        #expect(third?.rect == CGRect(x: 1512, y: 25, width: 960, height: 1055))
    }

    @Test func movedWindowIsNotARepeat() {
        let first = layout(.leftHalf)!
        let moved = first.rect.offsetBy(dx: 40, dy: 0)
        let r = layout(.leftHalf, window: moved, last: Placement(command: .leftHalf, variant: 0, rect: first.rect))
        #expect(r?.display == 0)
        #expect(r?.rect == first.rect)
    }

    @Test func cycleSizesGoesHalfTwoThirdsThird() {
        var r = press(.leftHalf, after: nil, behavior: .cycleSizes)
        #expect(r?.rect.width == 756)
        r = press(.leftHalf, after: r, behavior: .cycleSizes)
        #expect(r?.rect.width == 1008)
        r = press(.leftHalf, after: r, behavior: .cycleSizes)
        #expect(r?.rect.width == 504)
        r = press(.leftHalf, after: r, behavior: .cycleSizes)
        #expect(r?.rect.width == 756)
    }

    @Test func noneBehaviorRepeatsIdentically() {
        let first = press(.leftHalf, after: nil, behavior: .none)
        let second = press(.leftHalf, after: first, behavior: .none)
        #expect(first == second)
    }

    @Test func thirdsCyclePositionInEveryRepeatMode() {
        for behavior in [RepeatBehavior.moveAcrossDisplays, .cycleSizes] {
            var r = press(.firstThird, after: nil, behavior: behavior)
            #expect(r?.rect.minX == 0)
            r = press(.firstThird, after: r, behavior: behavior)
            #expect(r?.rect.minX == 504)
            r = press(.firstThird, after: r, behavior: behavior)
            #expect(r?.rect.minX == 1008)
            #expect(r?.display == 0)
        }
    }
}

@Suite struct Geometry {
    @Test func gapsSeparateNeighboursByExactlyOneGap() {
        let left = layout(.leftHalf, gap: 10)!.rect
        let right = layout(.rightHalf, gap: 10)!.rect
        #expect(left.minX == 10 && left.minY == 43)
        #expect(right.minX - left.maxX == 10)
        #expect(right.maxX == 1502)
    }

    @Test func portraitDisplaySplitsThirdsIntoRows() {
        let portrait = Display(id: 3, frame: CGRect(x: 0, y: 0, width: 1080, height: 1920),
                               visible: CGRect(x: 0, y: 0, width: 1080, height: 1920))
        let r = Layout.compute(.firstThird, window: someWindow, displays: [portrait], current: 0,
                               last: nil, behavior: .none, gap: 0)
        #expect(r?.rect == CGRect(x: 0, y: 0, width: 1080, height: 640))
    }

    @Test func sixthsTileTheDisplay() {
        let sixths: [Command] = [.topLeftSixth, .topCenterSixth, .topRightSixth,
                                 .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth]
        let rects = sixths.compactMap { layout($0)?.rect }
        let area = rects.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
        #expect(rects.count == 6)
        #expect(area == laptop.visible.width * laptop.visible.height)
    }

    @Test func resizingKeepsTheEdgeFlushWithTheScreen() {
        let snapped = layout(.leftHalf)!.rect
        let shrunk = Layout.resized(snapped, by: -30, in: laptop.visible)
        #expect(shrunk.minX == 0 && shrunk.width == 726)
        let grown = Layout.resized(shrunk, by: 30, in: laptop.visible)
        #expect(grown.minX == 0 && grown.width == 756)
        // A free-floating window grows evenly around its centre.
        let floating = Layout.resized(someWindow, by: 30, in: laptop.visible)
        #expect(floating.midX == someWindow.midX && floating.width == 830)
    }

    @Test func centerKeepsSizeAndClampsOversizedWindows() {
        let huge = CGRect(x: 0, y: 0, width: 3000, height: 3000)
        #expect(layout(.center, window: huge)?.rect == laptop.visible)
        #expect(layout(.center)?.rect.size == someWindow.size)
    }

    @Test func maximizeHeightKeepsHorizontalPosition() {
        let r = layout(.maximizeHeight)!.rect
        #expect(r.minX == someWindow.minX && r.width == someWindow.width)
        #expect(r.minY == 33 && r.height == 949)
    }

    @Test func moveLeftKeepsSize() {
        let r = layout(.moveLeft)!.rect
        #expect(r == CGRect(x: 0, y: someWindow.minY, width: 800, height: 500))
    }
}

@Suite struct Displays {
    @Test func directionalTargetsFollowArrangement() {
        #expect(Layout.targetDisplay(.direction(.right), from: 0, in: displays, cycleWhenNoNeighbour: false) == 1)
        #expect(Layout.targetDisplay(.direction(.left), from: 1, in: displays, cycleWhenNoNeighbour: false) == 0)
        #expect(Layout.targetDisplay(.direction(.left), from: 0, in: displays, cycleWhenNoNeighbour: false) == nil)
        #expect(Layout.targetDisplay(.direction(.up), from: 0, in: displays, cycleWhenNoNeighbour: true) == 1)
    }

    @Test func directNeighbourBeatsDiagonalOne() {
        let center = Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), visible: .zero)
        let diagonal = Display(id: 2, frame: CGRect(x: 1000, y: -1500, width: 1000, height: 1000), visible: .zero)
        let beside = Display(id: 3, frame: CGRect(x: 1200, y: 0, width: 1000, height: 1000), visible: .zero)
        let all = [center, diagonal, beside]
        #expect(Layout.targetDisplay(.direction(.right), from: 0, in: all, cycleWhenNoNeighbour: false) == 2)
    }

    @Test func singleDisplayHasNoTarget() {
        #expect(Layout.targetDisplay(.next, from: 0, in: [laptop], cycleWhenNoNeighbour: true) == nil)
    }

    @Test func windowBelongsToDisplayContainingItsCentre() {
        #expect(Layout.displayIndex(for: CGRect(x: 1400, y: 100, width: 400, height: 300), in: displays) == 1)
        #expect(Layout.displayIndex(for: CGRect(x: -5000, y: 0, width: 10, height: 10), in: displays) == 0)
    }

    @Test func transferredMaximizedWindowFillsDestination() {
        let r = Layout.transfer(window: laptop.visible, last: nil, from: laptop, to: external,
                                destinationIndex: 1, gap: 0)
        #expect(r.rect == external.visible)
        #expect(r.command == .maximize)
    }

    @Test func transferredSnappedWindowKeepsItsLayout() {
        let left = layout(.leftHalf, behavior: .cycleSizes)!
        let twoThirds = Layout.compute(.leftHalf, window: left.rect, displays: displays, current: 0,
                                       last: Placement(command: .leftHalf, variant: 0, rect: left.rect),
                                       behavior: .cycleSizes, gap: 0)!
        let r = Layout.transfer(window: twoThirds.rect,
                                last: Placement(command: .leftHalf, variant: twoThirds.variant, rect: twoThirds.rect),
                                from: laptop, to: external, destinationIndex: 1, gap: 0)
        #expect(r.rect == CGRect(x: 1512, y: 25, width: 1280, height: 1055))
    }

    @Test func transferredFreeWindowKeepsRelativePositionAndShrinksToFit() {
        let r = Layout.transfer(window: someWindow, last: nil, from: laptop, to: external,
                                destinationIndex: 1, gap: 0)
        #expect(r.rect.size == someWindow.size)
        #expect(r.command == nil)
        // 200 / (1512 − 800) of the slack → same fraction on the destination.
        #expect(abs(r.rect.minX - (1512 + (1920 - 800) * 200 / 712)) <= 1)

        let tall = CGRect(x: 0, y: 33, width: 600, height: 2000)
        #expect(Layout.transfer(window: tall, last: nil, from: external, to: laptop,
                                destinationIndex: 0, gap: 0).rect.height == 949)
    }
}

@Suite struct Shortcuts {
    @Test func cocoaFlagsRoundTrip() {
        let rectangleCtrlOpt = Modifiers(cocoaFlags: 786_432)
        #expect(rectangleCtrlOpt == [.control, .option])
        #expect(rectangleCtrlOpt.cocoaFlags == 786_432)
    }

    @Test func descriptionUsesCanonicalOrder() {
        #expect(Shortcut([.command, .shift, .control, .option], KeyCode.leftArrow).description == "⌃⌥⇧⌘←")
    }

    @Test func defaultsHaveNoDuplicates() {
        let shortcuts = Array(Command.defaultBindings.values)
        #expect(Set(shortcuts).count == shortcuts.count)
    }

    @Test func typingCombinationsAreNotGlobalHotkeys() {
        #expect(!Shortcut([], KeyCode.a).isUsableAsGlobalHotkey)
        #expect(!Shortcut(.shift, KeyCode.a).isUsableAsGlobalHotkey)          // capital A
        #expect(!Shortcut([.option, .shift], KeyCode.e).isUsableAsGlobalHotkey) // accents
        #expect(Shortcut([.control, .option], KeyCode.leftArrow).isUsableAsGlobalHotkey)
        #expect(Shortcut([], 0x60).isUsableAsGlobalHotkey) // F5
    }
}

@Suite struct FocusDisplay {
    private let browserOnExternal = OnscreenWindow(id: 10, pid: 100, frame: CGRect(x: 1600, y: 100, width: 1200, height: 800))
    private let editorOnExternal = OnscreenWindow(id: 11, pid: 101, frame: CGRect(x: 1512, y: 25, width: 1920, height: 1055))
    private let terminalOnLaptop = OnscreenWindow(id: 12, pid: 102, frame: CGRect(x: 100, y: 100, width: 700, height: 500))

    @Test func keepsOnlyTheTargetDisplaysWindowsFrontToBack() {
        let frontToBack = [terminalOnLaptop, browserOnExternal, editorOnExternal]
        #expect(Layout.windows(frontToBack, on: 1, in: displays) == [browserOnExternal, editorOnExternal])
        #expect(Layout.windows(frontToBack, on: 0, in: displays) == [terminalOnLaptop])
    }

    @Test func emptyDisplayHasNoWindowToFocus() {
        #expect(Layout.windows([terminalOnLaptop], on: 1, in: displays).isEmpty)
    }

    @Test func windowStraddlingDisplaysBelongsWhereItsCentreIs() {
        let mostlyOnLaptop = OnscreenWindow(id: 13, pid: 103, frame: CGRect(x: 900, y: 100, width: 800, height: 500))
        #expect(Layout.windows([mostlyOnLaptop], on: 1, in: displays).isEmpty)
    }

    @Test func pointerLandsOnTheVisiblePartOfTheWindow() {
        let straddling = CGRect(x: 1300, y: 100, width: 600, height: 400) // 212pt hang onto the laptop
        let point = Layout.pointerTarget(for: straddling, on: external)
        #expect(point == CGPoint(x: 1706, y: 300))
        #expect(external.visible.contains(point))
    }

    @Test func pointerGoesToTheMiddleOfAnEmptyDisplay() {
        #expect(Layout.pointerTarget(for: nil, on: external) == external.visible.center)
    }

    @Test func focusShortcutsAreTheDisplayMovesPlusShift() {
        let pairs: [(Command, Command)] = [(.displayLeft, .focusDisplayLeft), (.displayRight, .focusDisplayRight),
                                           (.displayUp, .focusDisplayUp), (.displayDown, .focusDisplayDown)]
        for (move, focus) in pairs {
            let m = try! #require(move.defaultShortcut), f = try! #require(focus.defaultShortcut)
            #expect(f == Shortcut(m.modifiers.union(.shift), m.keyCode))
            guard case .display(let moveTarget) = move.kind, case .focusDisplay(let focusTarget) = focus.kind else {
                Issue.record("\(focus) should be a focus command"); continue
            }
            #expect(moveTarget == focusTarget)
        }
    }
}
