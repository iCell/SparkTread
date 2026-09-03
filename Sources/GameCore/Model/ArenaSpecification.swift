/// The universal fixed-size arena (D-003, ADR-0004, ADR-0009).
///
/// All shipping stages use one universal fixed arena, pinned at 56×27 cells
/// by ADR-0009 (the one-shot M1 dimension tuning D-003 allowed). Arena
/// logic never changes with device, safe area, window size, or display scale.
public struct ArenaSpecification: Codable, Equatable, Sendable {
    /// Terrain cells along X; valid cell coordinates are `0..<cellsWide`.
    public let cellsWide: Int
    /// Terrain cells along Y; valid cell coordinates are `0..<cellsHigh`.
    public let cellsHigh: Int

    public init(cellsWide: Int, cellsHigh: Int) {
        self.cellsWide = cellsWide
        self.cellsHigh = cellsHigh
    }

    /// The universal arena: 56×27 base terrain cells (ADR-0009).
    public static let universal = ArenaSpecification(cellsWide: 56, cellsHigh: 27)

    /// Arena width in authoritative subunits.
    public var widthSubunits: Int { cellsWide * SpatialUnits.subunitsPerCell }

    /// Arena height in authoritative subunits.
    public var heightSubunits: Int { cellsHigh * SpatialUnits.subunitsPerCell }
}
