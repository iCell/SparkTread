/// Terrain cell kinds (§7.3). Four wall materials, in the reference's
/// durability order (GAME_RULES §3.5, owner testimony): red brick, white
/// brick (twice the rounds), grey steel (only the AP shell, one round per
/// cell) and white steel (indestructible).
public enum TerrainKind: Int, Codable, Sendable, Equatable {
    case ground = 0
    case brick = 1
    case steel = 2
    case water = 3
    case ice = 4
    case foliage = 5
    case base = 6
    case whiteBrick = 7
    case whiteSteel = 8

    /// Whether the kind blocks a `normal`-profile tank (before quadrant
    /// masks); `blocksTank(profile:)` applies the equipment profile.
    public var blocksTanksByDefault: Bool {
        switch self {
        case .brick, .whiteBrick, .steel, .whiteSteel, .water, .base: true
        case .ground, .ice, .foliage: false
        }
    }

    /// Whether a pickup may sit on this kind (§9.3 placement legality). The
    /// same predicate decides when a hidden treasure's covering cell counts
    /// as destroyed: destruction normalizes an emptied brick/steel cell to
    /// `.ground`, so "final quadrant destroyed" and "can hold a pickup" agree.
    public var canHoldPickup: Bool {
        switch self {
        case .ground, .ice, .foliage: true
        case .brick, .whiteBrick, .steel, .whiteSteel, .water, .base: false
        }
    }

    /// Brick-family walls chip away quadrant by quadrant under any weapon
    /// that lists brick damage; steel-family walls use the steel column.
    public var isBrickFamily: Bool { self == .brick || self == .whiteBrick }
    public var isSteelFamily: Bool { self == .steel || self == .whiteSteel }
    public var isWall: Bool { isBrickFamily || isSteelFamily }

    /// White steel takes no damage from anything (owner, §3.5).
    public var isIndestructibleWall: Bool { self == .whiteSteel }

    /// Rounds a single quadrant costs, relative to red brick. White brick is
    /// the same wall with twice the durability: the first hit cracks the
    /// quadrant, the second removes it.
    public var roundsPerQuadrant: Int { self == .whiteBrick ? 2 : 1 }
}

/// Outcome of one round of damage against a wall quadrant.
public enum WallDamage: Sendable, Equatable { case none, cracked, removed }

/// One terrain cell. Destructible kinds carry a four-bit quadrant mask
/// (§7.4): bit 0 = top-left, 1 = top-right, 2 = bottom-left, 3 = bottom-right
/// quadrant of 512×512 subunits, in the Y-down world convention.
public struct TerrainCell: Codable, Hashable, Sendable {
    public var kind: TerrainKind
    public var quadrantMask: Int
    /// Quadrants that have taken one round but have not fallen yet — only
    /// white brick uses it (`roundsPerQuadrant` 2). Always a subset of
    /// `quadrantMask`; absent from older documents, where it decodes as 0.
    public var crackMask: Int

    public init(kind: TerrainKind, quadrantMask: Int = 0b1111, crackMask: Int = 0) {
        self.kind = kind
        self.quadrantMask = kind.blocksTanksByDefault ? quadrantMask : 0
        self.crackMask = kind.blocksTanksByDefault ? (crackMask & self.quadrantMask) : 0
    }

    private enum CodingKeys: String, CodingKey { case kind, quadrantMask, crackMask }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(TerrainKind.self, forKey: .kind)
        let mask = try c.decode(Int.self, forKey: .quadrantMask)
        let cracks = try c.decodeIfPresent(Int.self, forKey: .crackMask) ?? 0
        self.init(kind: kind, quadrantMask: mask, crackMask: cracks)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(quadrantMask, forKey: .quadrantMask)
        if crackMask != 0 { try c.encode(crackMask, forKey: .crackMask) }
    }
}

/// The authoritative terrain grid: row-major cells over the universal arena.
public struct TerrainGrid: Codable, Equatable, Sendable {
    public let arena: ArenaSpecification
    public private(set) var cells: [TerrainCell]

    public init(arena: ArenaSpecification, fill: TerrainKind = .ground) {
        self.arena = arena
        self.cells = Array(
            repeating: TerrainCell(kind: fill),
            count: arena.cellsWide * arena.cellsHigh)
    }

    public func isInside(cellX: Int, cellY: Int) -> Bool {
        cellX >= 0 && cellX < arena.cellsWide && cellY >= 0 && cellY < arena.cellsHigh
    }

    public subscript(cellX: Int, cellY: Int) -> TerrainCell {
        get {
            precondition(isInside(cellX: cellX, cellY: cellY), "terrain access out of bounds")
            return cells[cellY * arena.cellsWide + cellX]
        }
        set {
            precondition(isInside(cellX: cellX, cellY: cellY), "terrain access out of bounds")
            cells[cellY * arena.cellsWide + cellX] = newValue
        }
    }

    /// Whether an axis-aligned rectangle in subunits (top-left origin,
    /// exclusive max edge) intersects any tank-blocking geometry. Damaged
    /// destructible cells block only through their remaining quadrants.
    public func blocksTank(minX: Int, minY: Int, maxX: Int, maxY: Int,
                           profile: TraversalProfile = .normal) -> Bool {
        if minX < 0 || minY < 0 || maxX > arena.widthSubunits || maxY > arena.heightSubunits {
            return true // outside the arena is always solid (§ M1 exit: never leave bounds)
        }
        let cell = SpatialUnits.subunitsPerCell
        let quadrant = SpatialUnits.subunitsPerQuadrant
        let firstCellX = minX / cell, lastCellX = (maxX - 1) / cell
        let firstCellY = minY / cell, lastCellY = (maxY - 1) / cell
        for cy in firstCellY...lastCellY {
            for cx in firstCellX...lastCellX {
                let c = self[cx, cy]
                guard c.kind.blocksTank(profile: profile) else { continue }
                if c.quadrantMask == 0b1111 { return true }
                if c.quadrantMask == 0 { continue }
                // Test the overlap against each remaining quadrant.
                for bit in 0..<4 where c.quadrantMask & (1 << bit) != 0 {
                    let qx = cx * cell + (bit % 2) * quadrant
                    let qy = cy * cell + (bit / 2) * quadrant
                    if minX < qx + quadrant && maxX > qx && minY < qy + quadrant && maxY > qy {
                        return true
                    }
                }
            }
        }
        return false
    }
}
