/// Cardinal direction convention (§6.2). World is Y-down (§6.1); the
/// SpriteKit adapter owns the single Y-axis conversion.
public enum Direction: Int, Codable, Sendable, CaseIterable, Equatable {
    case up = 0
    case right = 1
    case down = 2
    case left = 3

    public var vector: Vec2i {
        switch self {
        case .up: Vec2i(x: 0, y: -1)
        case .right: Vec2i(x: 1, y: 0)
        case .down: Vec2i(x: 0, y: 1)
        case .left: Vec2i(x: -1, y: 0)
        }
    }

    public var opposite: Direction { Direction(rawValue: (rawValue + 2) % 4)! }

    /// Perpendicular axis check: turning between horizontal and vertical.
    public func isPerpendicular(to other: Direction) -> Bool {
        (rawValue % 2) != (other.rawValue % 2)
    }
}

/// Integer 2D vector in authoritative subunits (ADR-0001).
public struct Vec2i: Codable, Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public static func + (l: Vec2i, r: Vec2i) -> Vec2i { Vec2i(x: l.x + r.x, y: l.y + r.y) }
    public static func * (v: Vec2i, s: Int) -> Vec2i { Vec2i(x: v.x * s, y: v.y * s) }
}
