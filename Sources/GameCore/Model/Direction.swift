/// The four cardinal facings a tank, projectile, or command can use.
///
/// Raw values are stable and part of the replay/content format: they are serialized
/// directly, so the numbering must never be reordered.
public enum Direction: Int, CaseIterable, Sendable {
    case up = 0
    case right = 1
    case down = 2
    case left = 3

    /// Creates a direction from a stored raw index, returning `nil` for out-of-range values.
    ///
    /// Declared explicitly (rather than relying on the synthesized initializer alone) so the
    /// decode path from replays and content is an intentional, documented entry point.
    public init?(index: Int) {
        self.init(rawValue: index)
    }

    /// The facing 180 degrees away. Involutive: `d.opposite.opposite == d`.
    public var opposite: Direction {
        switch self {
        case .up: .down
        case .right: .left
        case .down: .up
        case .left: .right
        }
    }

    /// Unit sign vector in arena space. `y` grows downward, so `up` is `(0, -1)`.
    public var vector: (dx: Int32, dy: Int32) {
        switch self {
        case .up: (0, -1)
        case .right: (1, 0)
        case .down: (0, 1)
        case .left: (-1, 0)
        }
    }
}
