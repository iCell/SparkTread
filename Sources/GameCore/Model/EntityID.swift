/// Stable identifier for a simulation entity.
///
/// `Comparable` is a load-bearing conformance, not a convenience: the tick pipeline
/// processes entities in ascending id order so that collision and event ordering is
/// reproducible. Dictionary/Set iteration order is never used for that purpose.
public struct EntityID: RawRepresentable, Hashable, Comparable, Sendable {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// Convenience initializer for literal call sites.
    public init(_ rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static func < (lhs: EntityID, rhs: EntityID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
