/// The single authoritative spatial unit system (ADR-0001).
///
/// There is exactly one authoritative spatial unit: the subunit. All schema
/// fields for speed, acceleration, radius, and distance are expressed in
/// subunits. "Subpixel" and "logical pixel" are not part of the vocabulary.
public enum SpatialUnits {
    /// 1 terrain cell = 1024 × 1024 subunits.
    public static let subunitsPerCell: Int = 1024

    /// 1 destruction quadrant = 512 × 512 subunits (four per cell).
    public static let subunitsPerQuadrant: Int = 512

    /// Standard tank footprint edge = 2048 subunits (2 cells), minus a
    /// PROVISIONAL collision inset defined with the movement system in M1.
    public static let standardTankFootprintSubunits: Int = 2048

    /// Reference conversion: 1 reference-game pixel (16-pixel-cell era)
    /// = 64 subunits. Reference-derived tuning values MUST pass through this
    /// factor exactly once; pixel values never appear in modern content data.
    public static let subunitsPerReferencePixel: Int = 64

    /// Per-tick displacement sanity cap enforced by the content validator.
    public static let maxPerTickDisplacementSubunits: Int = 1023
}
