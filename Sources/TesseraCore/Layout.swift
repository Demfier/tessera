import CoreGraphics

// All geometry in this file uses global "top-left origin" coordinates (y grows downward) — the space
// the Accessibility API and Quartz window lists use. The app layer converts from AppKit's bottom-left space.

/// A connected display.
public struct Display: Equatable, Sendable {
    public var id: UInt32
    /// Full bounds of the display.
    public var frame: CGRect
    /// Bounds minus the menu bar and Dock.
    public var visible: CGRect

    public init(id: UInt32, frame: CGRect, visible: CGRect) {
        self.id = id
        self.frame = frame
        self.visible = visible
    }
}

/// What pressing the same layout shortcut again does (Rectangle's "subsequent execution" setting).
public enum RepeatBehavior: String, CaseIterable, Codable, Sendable {
    /// Left/Right Half again sends the window to the neighbouring display; thirds etc. cycle position.
    case moveAcrossDisplays
    /// Halves and corners cycle ½ → ⅔ → ⅓; thirds etc. cycle position.
    case cycleSizes
    /// Repeating does nothing new.
    case none

    public var title: String {
        switch self {
        case .moveAcrossDisplays: "Move to the next display"
        case .cycleSizes: "Cycle sizes (½ → ⅔ → ⅓)"
        case .none: "Do nothing"
        }
    }
}

/// What Tessera last did to a window. Used to detect repeated presses, and to replay a snapped
/// layout when the window is sent to another display.
public struct Placement: Equatable, Sendable {
    public var command: Command
    public var variant: Int
    /// The frame the window actually ended up with (apps may round to their own size increments).
    public var rect: CGRect

    public init(command: Command, variant: Int, rect: CGRect) {
        self.command = command
        self.variant = variant
        self.rect = rect
    }

    /// True while the window still sits exactly where Tessera put it.
    public func stillApplies(to window: CGRect) -> Bool {
        rect.isApproximatelyEqual(to: window, tolerance: Layout.matchTolerance)
    }
}

public struct LayoutResult: Equatable, Sendable {
    public var rect: CGRect
    /// Index into the display array the caller passed in.
    public var display: Int
    /// The layout the window now occupies, if it is one that can be repeated or replayed.
    public var command: Command?
    public var variant: Int
}

public enum Layout {
    static let matchTolerance: CGFloat = 2
    /// Halves and corners cycle through these widths (or heights) when `RepeatBehavior.cycleSizes` is on.
    static let sizeCycle: [CGFloat] = [1.0 / 2.0, 2.0 / 3.0, 1.0 / 3.0]
    static let resizeStep: CGFloat = 30
    static let almostMaximizeRatio: CGFloat = 0.9

    // MARK: - Layout commands

    /// The frame for a `.layout` command applied to `window` on `displays[current]`.
    /// `displays` must be ordered with `sorted(_:)` so "previous/next display" is left-to-right.
    public static func compute(
        _ command: Command,
        window: CGRect,
        displays: [Display],
        current: Int,
        last: Placement?,
        behavior: RepeatBehavior,
        gap: CGFloat
    ) -> LayoutResult? {
        guard command.kind == .layout, displays.indices.contains(current) else { return nil }
        let repeated = last.map { $0.command == command && $0.stillApplies(to: window) } ?? false
        let lastVariant = repeated ? last?.variant : nil

        // Left/Right Half pressed again walks the window across displays (Rectangle's "across monitor").
        if repeated, behavior == .moveAcrossDisplays, displays.count > 1,
           command == .leftHalf || command == .rightHalf {
            let step = command == .leftHalf ? -1 : 1
            let target = (current + step + displays.count) % displays.count
            let opposite: Command = command == .leftHalf ? .rightHalf : .leftHalf
            let rect = tiledRect(opposite, variant: 0, in: displays[target].visible, gap: gap)!
            return LayoutResult(rect: rect, display: target, command: opposite, variant: 0)
        }

        let visible = displays[current].visible
        if command.isTiling {
            let variant = nextVariant(for: command, after: lastVariant, behavior: behavior)
            guard let rect = tiledRect(command, variant: variant, in: visible, gap: gap) else { return nil }
            return LayoutResult(rect: rect, display: current, command: command, variant: variant)
        }
        guard let rect = freeformRect(command, window: window, in: visible, gap: gap) else { return nil }
        return LayoutResult(rect: rect, display: current, command: command, variant: 0)
    }

    static func nextVariant(for command: Command, after lastVariant: Int?, behavior: RepeatBehavior) -> Int {
        guard let lastVariant else { return 0 }
        let count: Int
        switch behavior {
        case .none:
            return 0
        case .cycleSizes:
            count = command.cyclesSizes ? sizeCycle.count : positionSequence(for: command, landscape: true).count
        case .moveAcrossDisplays:
            // Halves/corners don't resize in this mode; thirds/fourths/sixths still cycle (as Rectangle).
            count = command.cyclesSizes ? 1 : positionSequence(for: command, landscape: true).count
        }
        return count > 0 ? (lastVariant + 1) % count : 0
    }

    /// The frame of a tiling command (a fixed fraction of the display), with gaps applied.
    static func tiledRect(_ command: Command, variant: Int, in visible: CGRect, gap: CGFloat) -> CGRect? {
        let landscape = visible.width >= visible.height
        let slot: Slot
        if command.cyclesSizes {
            let f = sizeCycle[variant % sizeCycle.count]
            switch command {
            case .leftHalf: slot = Slot(x: 0, f, y: 0, 1)
            case .rightHalf: slot = Slot(x: 1 - f, 1, y: 0, 1)
            case .topHalf: slot = Slot(x: 0, 1, y: 0, f)
            case .bottomHalf: slot = Slot(x: 0, 1, y: 1 - f, 1)
            case .topLeft: slot = Slot(x: 0, f, y: 0, 0.5)
            case .topRight: slot = Slot(x: 1 - f, 1, y: 0, 0.5)
            case .bottomLeft: slot = Slot(x: 0, f, y: 0.5, 1)
            case .bottomRight: slot = Slot(x: 1 - f, 1, y: 0.5, 1)
            default: return nil
            }
        } else if command == .maximize {
            slot = Slot(x: 0, 1, y: 0, 1)
        } else {
            let sequence = positionSequence(for: command, landscape: landscape)
            guard !sequence.isEmpty else { return nil }
            slot = sequence[variant % sequence.count]
        }
        return applyGaps(slot.rect(in: visible), in: visible, gap: gap)
    }

    /// Fixed-position commands, and the positions repeated presses cycle through (first = unrepeated).
    static func positionSequence(for command: Command, landscape: Bool) -> [Slot] {
        // Thirds and fourths split along the long axis: columns on landscape, rows on portrait displays.
        func strip(_ start: CGFloat, _ end: CGFloat) -> Slot {
            landscape ? Slot(x: start, end, y: 0, 1) : Slot(x: 0, 1, y: start, end)
        }
        let third = (0..<3).map { strip(CGFloat($0) / 3, CGFloat($0 + 1) / 3) }
        let fourth = (0..<4).map { strip(CGFloat($0) / 4, CGFloat($0 + 1) / 4) }
        // Sixths in reading order: 3×2 on landscape, 2×3 on portrait.
        let (cols, rows) = landscape ? (3, 2) : (2, 3)
        let sixth = (0..<6).map { i in
            let c = CGFloat(i % cols), r = CGFloat(i / cols)
            return Slot(x: c / CGFloat(cols), (c + 1) / CGFloat(cols), y: r / CGFloat(rows), (r + 1) / CGFloat(rows))
        }
        func cycle(_ slots: [Slot], from start: Int) -> [Slot] {
            (0..<slots.count).map { slots[(start + $0) % slots.count] }
        }

        switch command {
        case .centerHalf: return [Slot(x: 0.25, 0.75, y: 0, 1)]
        case .firstThird: return [third[0], third[1], third[2]]
        case .centerThird: return [third[1]]
        case .lastThird: return [third[2], third[1], third[0]]
        case .firstTwoThirds: return [strip(0, 2.0 / 3), strip(1.0 / 3, 1)]
        case .centerTwoThirds: return [strip(1.0 / 6, 5.0 / 6)]
        case .lastTwoThirds: return [strip(1.0 / 3, 1), strip(0, 2.0 / 3)]
        case .firstFourth: return fourth
        case .secondFourth: return [fourth[1]]
        case .thirdFourth: return [fourth[2]]
        case .lastFourth: return fourth.reversed()
        case .firstThreeFourths: return [strip(0, 0.75), strip(0.25, 1)]
        case .centerThreeFourths: return [strip(0.125, 0.875)]
        case .lastThreeFourths: return [strip(0.25, 1), strip(0, 0.75)]
        case .topLeftSixth: return cycle(sixth, from: 0)
        case .topCenterSixth: return cycle(sixth, from: 1)
        case .topRightSixth: return cycle(sixth, from: 2)
        case .bottomLeftSixth: return cycle(sixth, from: 3)
        case .bottomCenterSixth: return cycle(sixth, from: 4)
        case .bottomRightSixth: return cycle(sixth, from: 5)
        default: return []
        }
    }

    /// Commands whose result depends on the window's current frame rather than a fixed fraction.
    static func freeformRect(_ command: Command, window: CGRect, in v: CGRect, gap: CGFloat) -> CGRect? {
        let fitted = CGSize(width: min(window.width, v.width), height: min(window.height, v.height))
        switch command {
        case .almostMaximize:
            let size = CGSize(width: v.width * almostMaximizeRatio, height: v.height * almostMaximizeRatio)
            return centered(size, in: v)
        case .maximizeHeight:
            let x = clamp(window.minX, v.minX, v.maxX - fitted.width)
            let r = CGRect(x: x, y: v.minY, width: fitted.width, height: v.height)
            return applyGaps(r, in: v, gap: gap, horizontal: false)
        case .maximizeWidth:
            let y = clamp(window.minY, v.minY, v.maxY - fitted.height)
            let r = CGRect(x: v.minX, y: y, width: v.width, height: fitted.height)
            return applyGaps(r, in: v, gap: gap, vertical: false)
        case .center:
            return centered(fitted, in: v)
        case .larger, .smaller:
            return resized(window, by: command == .larger ? resizeStep : -resizeStep, in: v)
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            var origin = CGPoint(x: clamp(window.minX, v.minX, v.maxX - fitted.width),
                                 y: clamp(window.minY, v.minY, v.maxY - fitted.height))
            switch command {
            case .moveLeft: origin.x = v.minX + gap
            case .moveRight: origin.x = v.maxX - fitted.width - gap
            case .moveUp: origin.y = v.minY + gap
            default: origin.y = v.maxY - fitted.height - gap
            }
            return CGRect(origin: origin, size: fitted).pixelAligned
        default:
            return nil
        }
    }

    /// Grow or shrink by `delta` per dimension. Edges flush with the screen stay put, so a window
    /// snapped to the left grows rightward rather than off-screen.
    static func resized(_ w: CGRect, by delta: CGFloat, in v: CGRect) -> CGRect {
        let tol = matchTolerance
        let minWidth = min(w.width, v.width / 4), minHeight = min(w.height, v.height / 4)
        let newWidth = clamp(w.width + delta, minWidth, v.width)
        let newHeight = clamp(w.height + delta, minHeight, v.height)

        func axis(_ lo: CGFloat, _ hi: CGFloat, _ vLo: CGFloat, _ vHi: CGFloat, _ old: CGFloat, _ new: CGFloat) -> CGFloat {
            let pinnedLo = abs(lo - vLo) <= tol, pinnedHi = abs(hi - vHi) <= tol
            let origin: CGFloat = switch (pinnedLo, pinnedHi) {
            case (true, false): lo
            case (false, true): hi - new
            default: lo - (new - old) / 2
            }
            return clamp(origin, vLo, vHi - new)
        }
        let x = axis(w.minX, w.maxX, v.minX, v.maxX, w.width, newWidth)
        let y = axis(w.minY, w.maxY, v.minY, v.maxY, w.height, newHeight)
        return CGRect(x: x, y: y, width: newWidth, height: newHeight).pixelAligned
    }

    /// Edges on the display boundary get a full gap; edges shared with a neighbouring tile get half,
    /// so two adjacent tiles end up exactly `gap` apart.
    static func applyGaps(_ r: CGRect, in v: CGRect, gap: CGFloat, horizontal: Bool = true, vertical: Bool = true) -> CGRect {
        guard gap > 0 else { return r }
        func inset(_ edge: CGFloat, _ boundary: CGFloat) -> CGFloat { abs(edge - boundary) < 1 ? gap : gap / 2 }
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        if horizontal { minX += inset(r.minX, v.minX); maxX -= inset(r.maxX, v.maxX) }
        if vertical { minY += inset(r.minY, v.minY); maxY -= inset(r.maxY, v.maxY) }
        // Round each edge (not origin + size) so adjacent tiles keep sharing an exact boundary.
        minX.round(); maxX.round(); minY.round(); maxY.round()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Moving between displays

    /// Where a window lands when sent from `source` to `destination` (Second Display Pro semantics):
    /// a snapped window keeps its layout, a window filling its display fills the new one, anything
    /// else keeps its size (shrunk to fit) and its relative position.
    public static func transfer(
        window w: CGRect, last: Placement?, from source: Display, to destination: Display,
        destinationIndex: Int, gap: CGFloat
    ) -> LayoutResult {
        let dst = destination.visible
        if let last, last.stillApplies(to: w), last.command.isTiling,
           let rect = tiledRect(last.command, variant: last.variant, in: dst, gap: gap) {
            return LayoutResult(rect: rect, display: destinationIndex, command: last.command, variant: last.variant)
        }
        let fillTolerance = gap + matchTolerance
        if w.covers(source.visible, tolerance: fillTolerance) || w.covers(source.frame, tolerance: fillTolerance) {
            let rect = tiledRect(.maximize, variant: 0, in: dst, gap: gap)!
            return LayoutResult(rect: rect, display: destinationIndex, command: .maximize, variant: 0)
        }

        let src = source.visible
        let size = CGSize(width: min(w.width, dst.width), height: min(w.height, dst.height))
        func relative(_ pos: CGFloat, _ lo: CGFloat, _ slack: CGFloat) -> CGFloat {
            slack > 0 ? clamp((pos - lo) / slack, 0, 1) : 0.5
        }
        let fx = relative(w.minX, src.minX, src.width - w.width)
        let fy = relative(w.minY, src.minY, src.height - w.height)
        let origin = CGPoint(x: dst.minX + (dst.width - size.width) * fx,
                             y: dst.minY + (dst.height - size.height) * fy)
        return LayoutResult(rect: CGRect(origin: origin, size: size).pixelAligned,
                            display: destinationIndex, command: nil, variant: 0)
    }

    /// Display order for next/previous: left-to-right, then top-to-bottom.
    public static func sorted(_ displays: [Display]) -> [Display] {
        displays.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    /// The display a window is on: the one containing its centre, else the one it overlaps most,
    /// else the nearest.
    public static func displayIndex(for window: CGRect, in displays: [Display]) -> Int? {
        let center = CGPoint(x: window.midX, y: window.midY)
        if let i = displays.firstIndex(where: { $0.frame.contains(center) }) { return i }
        let overlaps = displays.enumerated().map { ($0.offset, $0.element.frame.intersection(window).area) }
        if let best = overlaps.max(by: { $0.1 < $1.1 }), best.1 > 0 { return best.0 }
        return displays.enumerated().min {
            $0.element.frame.center.distance(to: center) < $1.element.frame.center.distance(to: center)
        }?.offset
    }

    /// Resolves a display target. `cycleWhenNoNeighbour` makes →/↓ fall back to the next display and
    /// ←/↑ to the previous one when nothing sits physically in that direction.
    public static func targetDisplay(
        _ target: DisplayTarget, from current: Int, in displays: [Display], cycleWhenNoNeighbour: Bool
    ) -> Int? {
        let n = displays.count
        guard n > 1, displays.indices.contains(current) else { return nil }
        let next = (current + 1) % n, previous = (current - 1 + n) % n
        switch target {
        case .next: return next
        case .previous: return previous
        case .direction(let direction):
            if let neighbour = neighbour(of: current, toward: direction, in: displays) { return neighbour }
            guard cycleWhenNoNeighbour else { return nil }
            return direction == .right || direction == .down ? next : previous
        }
    }

    /// The display physically adjacent in `direction`: prefer ones that overlap along the other
    /// axis (i.e. directly beside, not diagonal), then the closest.
    static func neighbour(of current: Int, toward direction: Direction, in displays: [Display]) -> Int? {
        let cur = displays[current].frame
        let epsilon: CGFloat = 1
        struct Candidate { let index: Int; let diagonal: Bool; let distance: CGFloat; let offset: CGFloat }
        let candidates: [Candidate] = displays.enumerated().compactMap { index, display in
            guard index != current else { return nil }
            let f = display.frame
            let distance: CGFloat
            let overlap: CGFloat
            let offset: CGFloat
            switch direction {
            case .left:
                guard f.maxX <= cur.minX + epsilon else { return nil }
                distance = cur.minX - f.maxX
            case .right:
                guard f.minX >= cur.maxX - epsilon else { return nil }
                distance = f.minX - cur.maxX
            case .up:
                guard f.maxY <= cur.minY + epsilon else { return nil }
                distance = cur.minY - f.maxY
            case .down:
                guard f.minY >= cur.maxY - epsilon else { return nil }
                distance = f.minY - cur.maxY
            }
            if direction == .left || direction == .right {
                overlap = min(f.maxY, cur.maxY) - max(f.minY, cur.minY)
                offset = abs(f.midY - cur.midY)
            } else {
                overlap = min(f.maxX, cur.maxX) - max(f.minX, cur.minX)
                offset = abs(f.midX - cur.midX)
            }
            return Candidate(index: index, diagonal: overlap <= 0, distance: distance, offset: offset)
        }
        return candidates.min {
            ($0.diagonal ? 1 : 0, $0.distance, $0.offset) < ($1.diagonal ? 1 : 0, $1.distance, $1.offset)
        }?.index
    }

    static func centered(_ size: CGSize, in v: CGRect) -> CGRect {
        CGRect(x: v.midX - size.width / 2, y: v.midY - size.height / 2, width: size.width, height: size.height).pixelAligned
    }

    static func clamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        max(lo, min(value, max(lo, hi)))
    }
}

/// A rectangle expressed as fractions of a display's visible frame (y = 0 is the top).
struct Slot: Equatable {
    var x0, x1, y0, y1: CGFloat

    init(x x0: CGFloat, _ x1: CGFloat, y y0: CGFloat, _ y1: CGFloat) {
        self.x0 = x0; self.x1 = x1; self.y0 = y0; self.y1 = y1
    }

    /// Each edge is rounded independently so neighbouring tiles share an exact boundary.
    func rect(in v: CGRect) -> CGRect {
        let minX = (v.minX + v.width * x0).rounded(), maxX = (v.minX + v.width * x1).rounded()
        let minY = (v.minY + v.height * y0).rounded(), maxY = (v.minY + v.height * y1).rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension Command {
    /// Commands that occupy a fixed fraction of the display; these can be replayed on another display.
    public var isTiling: Bool {
        cyclesSizes || self == .maximize || !Layout.positionSequence(for: self, landscape: true).isEmpty
    }

    /// Halves and corners: repeated presses cycle their size rather than their position.
    var cyclesSizes: Bool {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf, .topLeft, .topRight, .bottomLeft, .bottomRight: true
        default: false
        }
    }
}

extension CGRect {
    public func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    /// True when this rect reaches every edge of `other` (within `tolerance`).
    func covers(_ other: CGRect, tolerance: CGFloat) -> Bool {
        minX <= other.minX + tolerance && maxX >= other.maxX - tolerance
            && minY <= other.minY + tolerance && maxY >= other.maxY - tolerance
    }

    var area: CGFloat { isNull ? 0 : width * height }

    /// Whole-point origin and size. Unlike `integral`, never grows the rect by a point when the
    /// origin is fractional — a window must keep exactly the size it asked for.
    var pixelAligned: CGRect {
        CGRect(x: minX.rounded(), y: minY.rounded(), width: width.rounded(), height: height.rounded())
    }
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}
