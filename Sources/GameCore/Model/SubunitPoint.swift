/// An authoritative position in arena subunits (see `ArenaGeometry.subunitsPerCell`).
///
/// Origin is the arena's top-left corner; `y` grows downward.
public struct SubunitPoint: Hashable, Sendable {
    /// Horizontal offset from the arena origin, in subunits.
    public var x: Int32

    /// Vertical offset from the arena origin, in subunits. Grows downward.
    public var y: Int32

    public init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }

    /// Builds a point from whole-cell coordinates, landing on the cell's top-left corner.
    public init(column: Int32, row: Int32) {
        self.x = column * ArenaGeometry.subunitsPerCell
        self.y = row * ArenaGeometry.subunitsPerCell
    }

    /// The cell containing this point.
    ///
    /// Uses flooring division so negative coordinates (out-of-arena projectiles, for
    /// example) map to the cell they are visually inside rather than truncating toward
    /// zero. A point exactly on a cell boundary belongs to the cell it starts.
    public var cell: (column: Int32, row: Int32) {
        (Self.floorDiv(x, ArenaGeometry.subunitsPerCell),
         Self.floorDiv(y, ArenaGeometry.subunitsPerCell))
    }

    /// Integer division that rounds toward negative infinity.
    private static func floorDiv(_ value: Int32, _ divisor: Int32) -> Int32 {
        let quotient = value / divisor
        let remainder = value % divisor
        return (remainder != 0 && (remainder < 0) != (divisor < 0)) ? quotient - 1 : quotient
    }
}
