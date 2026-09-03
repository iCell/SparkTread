/// The universal fixed-size arena (D-003, ADR-0004).
///
/// All shipping stages use one universal, approximately 16:9 arena. The
/// dimensions below are the PROVISIONAL implementation baseline; M1 may tune
/// them exactly once through an ADR before combat content is authored. Arena
/// logic never changes with device, safe area, window size, or display scale.
public struct ArenaSpecification: Equatable, Sendable {
    /// Terrain cells along X; valid cell coordinates are `0..<cellsWide`.
    public let cellsWide: Int
    /// Terrain cells along Y; valid cell coordinates are `0..<cellsHigh`.
    public let cellsHigh: Int

    public init(cellsWide: Int, cellsHigh: Int) {
        self.cellsWide = cellsWide
        self.cellsHigh = cellsHigh
    }

    /// The provisional universal baseline: 48×27 base terrain cells.
    public static let provisionalBaseline = ArenaSpecification(cellsWide: 48, cellsHigh: 27)

    /// Arena width in authoritative subunits.
    public var widthSubunits: Int { cellsWide * SpatialUnits.subunitsPerCell }

    /// Arena height in authoritative subunits.
    public var heightSubunits: Int { cellsHigh * SpatialUnits.subunitsPerCell }
}
