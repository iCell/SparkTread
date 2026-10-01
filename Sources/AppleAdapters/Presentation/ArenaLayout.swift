import CoreGraphics
import GameCore

/// Uniform full-arena fit (GAME_RULES §15.1, owner 2026-09-16): one scale
/// from `min(surfaceW/56, surfaceH/27)` over the FULL screen, centered,
/// never stretched. The gutter left over on the non-constraining axis is
/// dressed as white steel by the scene; system cutouts (notch, Dynamic
/// Island) may overlap that decorative bezel, while touch controls and the
/// HUD keep their own safe-area padding. Pure math so device-aspect
/// fixtures can assert the fit.
public struct ArenaLayout: Equatable, Sendable {
    public let cellPoints: CGFloat
    public let origin: CGPoint
    public let arena: ArenaSpecification

    public init(surface: CGSize, arena: ArenaSpecification) {
        self.arena = arena
        let width = max(1, surface.width), height = max(1, surface.height)
        cellPoints = min(width / CGFloat(arena.cellsWide),
                         height / CGFloat(arena.cellsHigh))
        origin = CGPoint(x: (width - CGFloat(arena.cellsWide) * cellPoints) / 2,
                         y: (height - CGFloat(arena.cellsHigh) * cellPoints) / 2)
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
