import CoreGraphics
import GameCore

/// Uniform full-arena fit (ADR-0004, §6.1): one scale from
/// `min(w/arenaW, h/arenaH)`, centered, edge-to-edge, never stretched.
/// Pure math so device-aspect fixtures can assert the whole arena stays
/// visible on every supported surface.
public struct ArenaLayout: Equatable, Sendable {
    public let cellPoints: CGFloat
    public let origin: CGPoint
    public let arena: ArenaSpecification

    public init(surface: CGSize, arena: ArenaSpecification) {
        self.arena = arena
        cellPoints = min(surface.width / CGFloat(arena.cellsWide),
                         surface.height / CGFloat(arena.cellsHigh))
        let width = CGFloat(arena.cellsWide) * cellPoints
        let height = CGFloat(arena.cellsHigh) * cellPoints
        origin = CGPoint(x: (surface.width - width) / 2, y: (surface.height - height) / 2)
    }

    public var pointsPerSubunit: CGFloat { cellPoints / CGFloat(SpatialUnits.subunitsPerCell) }

    public var arenaRect: CGRect {
        CGRect(x: origin.x, y: origin.y,
               width: CGFloat(arena.cellsWide) * cellPoints,
               height: CGFloat(arena.cellsHigh) * cellPoints)
    }

    /// World subunits (Y-down) → scene points (Y-up): the single conversion
    /// owned by the presentation adapter (§6.1).
    public func scenePoint(_ p: Vec2i) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(p.x) * pointsPerSubunit,
                y: origin.y + (CGFloat(arena.heightSubunits) - CGFloat(p.y)) * pointsPerSubunit)
    }

    /// A world-rect (top-left + size in subunits) mapped into scene space.
    public func sceneRect(topLeft: Vec2i, widthSubunits: Int, heightSubunits: Int) -> CGRect {
        let bottomLeft = scenePoint(Vec2i(x: topLeft.x, y: topLeft.y + heightSubunits))
        return CGRect(x: bottomLeft.x, y: bottomLeft.y,
                      width: CGFloat(widthSubunits) * pointsPerSubunit,
                      height: CGFloat(heightSubunits) * pointsPerSubunit)
    }
}
