/// Terrain cell kinds (GAME_RULES §2.3, §3.1). A cell's `kind` is its top
/// layer — a wall, foliage, the base marker, or a bare surface — and its
/// `surface` is the ground, water or ice underneath. Four wall materials in
/// durability order: red brick, white brick (two rounds per quadrant), grey
/// steel (only AP) and white steel (indestructible).
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

    /// Brick-family walls chip quadrant by quadrant under brick-damaging
    /// weapons; steel-family walls resist everything but AP (grey steel).
    public var isBrickFamily: Bool { self == .brick || self == .whiteBrick }
    public var isSteelFamily: Bool { self == .steel || self == .whiteSteel }
    public var isWall: Bool { isBrickFamily || isSteelFamily }
    /// Kinds that carry a quadrant mask and block by quadrant.
    public var isSolidStructure: Bool { isWall || self == .base }
    /// Kinds that are a surface on their own (the layer under walls/foliage).
    public var isSurface: Bool { self == .ground || self == .water || self == .ice }

    /// White steel takes no damage from anything (GAME_RULES §3.1).
    public var isIndestructibleWall: Bool { self == .whiteSteel }

    /// Rounds a single quadrant costs: white brick cracks first.
    public var roundsPerQuadrant: Int { self == .whiteBrick ? 2 : 1 }
}

/// Outcome of one round of damage against a wall quadrant.
public enum WallDamage: Sendable, Equatable { case none, cracked, removed }

/// One terrain cell. Structures carry a four-bit quadrant mask: bit 0 =
/// top-left, 1 = top-right, 2 = bottom-left, 3 = bottom-right quadrant of
/// 512×512 subunits, in the Y-down world convention. Destroyed walls and
/// burnt foliage reveal `surface` (GAME_RULES §2.3).
public struct TerrainCell: Codable, Hashable, Sendable {
    public var kind: TerrainKind
    public var quadrantMask: Int
    /// Quadrants hit once but still standing (white brick only).
    public var crackMask: Int
    /// The surface under the top layer: `.ground`, `.water` or `.ice`.
    public var surface: TerrainKind
    /// Foliage burning state (GAME_RULES §7.4): the tick the cell first
    /// caught fire, and whether it has spread to its neighbours.
    public var ignitedAtTick: Int?
    public var hasSpread: Bool

    public init(kind: TerrainKind, quadrantMask: Int = 0b1111, crackMask: Int = 0,
                surface: TerrainKind? = nil) {
        self.kind = kind
        self.quadrantMask = kind.isSolidStructure ? quadrantMask : 0
        self.crackMask = kind.isSolidStructure ? (crackMask & self.quadrantMask) : 0
        self.surface = kind.isSurface ? kind : (surface ?? .ground)
        self.ignitedAtTick = nil
        self.hasSpread = false
    }

    /// The cell a destroyed structure or burnt foliage leaves behind.
    public var revealedSurface: TerrainCell { TerrainCell(kind: surface) }

    /// Whether any wall quadrant still stands in this cell.
    public var hasWall: Bool { kind.isWall && quadrantMask != 0 }

    /// Whether the cell's surface is water or ice (no lasting fire, no pickups).
    public var isWaterOrIce: Bool { surface == .water || surface == .ice }

    /// Whether a tank of the profile is blocked by the cell's surface
    /// (structures block per quadrant, see `TerrainGrid.blocksTank`).
    public func surfaceBlocksTank(profile: TraversalProfile) -> Bool {
        surface == .water && profile != .amphibious && !kind.isSolidStructure
    }

    /// Whether a pickup may occupy this cell (GAME_RULES §10.2).
    public var canHoldPickup: Bool {
        !kind.isSolidStructure && surface != .water
    }

    private enum CodingKeys: String, CodingKey {
        case kind, quadrantMask, crackMask, surface, ignitedAtTick, hasSpread
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(TerrainKind.self, forKey: .kind)
        let mask = try c.decode(Int.self, forKey: .quadrantMask)
        let cracks = try c.decodeIfPresent(Int.self, forKey: .crackMask) ?? 0
        let surface = try c.decodeIfPresent(TerrainKind.self, forKey: .surface)
        self.init(kind: kind, quadrantMask: mask, crackMask: cracks, surface: surface)
        ignitedAtTick = try c.decodeIfPresent(Int.self, forKey: .ignitedAtTick)
        hasSpread = try c.decodeIfPresent(Bool.self, forKey: .hasSpread) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(quadrantMask, forKey: .quadrantMask)
        if crackMask != 0 { try c.encode(crackMask, forKey: .crackMask) }
        if !kind.isSurface && surface != .ground { try c.encode(surface, forKey: .surface) }
        try c.encodeIfPresent(ignitedAtTick, forKey: .ignitedAtTick)
        if hasSpread { try c.encode(hasSpread, forKey: .hasSpread) }
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

    /// Whether the wall quadrant (qx, qy) — quadrant coordinates, 2 per
    /// cell — is standing.
    public func solidWallQuadrant(qx: Int, qy: Int) -> Bool {
        guard qx >= 0, qy >= 0 else { return false }
        let cx = qx / 2, cy = qy / 2
        guard isInside(cellX: cx, cellY: cy) else { return false }
        let cell = self[cx, cy]
        guard cell.kind.isWall else { return false }
        return cell.quadrantMask & (1 << ((qy % 2) * 2 + (qx % 2))) != 0
    }

    /// Whether an axis-aligned rectangle in subunits (top-left origin,
    /// exclusive max edge) intersects any tank-blocking geometry. Structures
    /// block only through their remaining quadrants; water blocks unless
    /// the profile is amphibious.
    public func blocksTank(minX: Int, minY: Int, maxX: Int, maxY: Int,
                           profile: TraversalProfile = .normal) -> Bool {
        if minX < 0 || minY < 0 || maxX > arena.widthSubunits || maxY > arena.heightSubunits {
            return true // outside the arena is always solid
        }
        let cell = SpatialUnits.subunitsPerCell
        let quadrant = SpatialUnits.subunitsPerQuadrant
        let firstCellX = minX / cell, lastCellX = (maxX - 1) / cell
        let firstCellY = minY / cell, lastCellY = (maxY - 1) / cell
        for cy in firstCellY...lastCellY {
            for cx in firstCellX...lastCellX {
                let c = self[cx, cy]
                if c.surfaceBlocksTank(profile: profile) { return true }
                guard c.kind.isSolidStructure else { continue }
                if c.quadrantMask == 0b1111 { return true }
                if c.quadrantMask == 0 { continue }
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

    /// Area (subunits²) of a rectangle that lies over water surface cells
    /// not covered by a structure — the monotone quantity of the water-exit
    /// rule (GAME_RULES §4.4).
    public func waterOverlapArea(minX: Int, minY: Int, maxX: Int, maxY: Int) -> Int {
        let cell = SpatialUnits.subunitsPerCell
        guard maxX > minX, maxY > minY else { return 0 }
        let loX = max(0, minX), loY = max(0, minY)
        let hiX = min(arena.widthSubunits, maxX), hiY = min(arena.heightSubunits, maxY)
        guard hiX > loX, hiY > loY else { return 0 }
        var area = 0
        for cy in (loY / cell)...((hiY - 1) / cell) {
            for cx in (loX / cell)...((hiX - 1) / cell) {
                let c = self[cx, cy]
                guard c.surface == .water, !c.kind.isSolidStructure else { continue }
                let w = min(hiX, (cx + 1) * cell) - max(loX, cx * cell)
                let h = min(hiY, (cy + 1) * cell) - max(loY, cy * cell)
                if w > 0 && h > 0 { area += w * h }
            }
        }
        return area
    }
}
