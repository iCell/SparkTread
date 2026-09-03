/// Fixed arena dimensions and the subunit resolution every authoritative position uses.
///
/// Coordinate convention for the whole simulation: the origin is the **top-left** corner of
/// the arena, `+x` grows to the right and `+y` grows **downward**. Presentation code is
/// responsible for flipping into SpriteKit's bottom-left space; the simulation never does.
///
/// Positions are stored in *subunits* rather than cells so that movement can be sub-cell
/// smooth while staying exact integer arithmetic. There are no floats here by design.
public enum ArenaGeometry {
    /// Arena width in cells (fixed by ADR-0003).
    public static let columns: Int32 = 48

    /// Arena height in cells (fixed by ADR-0003).
    public static let rows: Int32 = 27

    /// Integer subdivisions per cell edge. All authoritative positions are multiples of 1.
    public static let subunitsPerCell: Int32 = 1024

    /// Every tank occupies a 2x2 cell footprint.
    public static let tankFootprintCells: Int32 = 2

    /// Arena width expressed in subunits.
    public static var arenaWidthSubunits: Int32 { columns * subunitsPerCell }

    /// Arena height expressed in subunits.
    public static var arenaHeightSubunits: Int32 { rows * subunitsPerCell }
}
