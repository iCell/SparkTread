/// Combat entities. All value types, Codable, kept in ascending entity-ID
/// order inside WorldState.

/// A projectile in flight (GAME_RULES §5.2). `positionSubunits` is the
/// CENTER of its collision box.
public struct ProjectileState: Codable, Equatable, Sendable {
    public let entityID: Int
    public let weaponID: String
    public let ownerEntityID: Int
    public let ownerPlayerID: PlayerID?
    public let teamID: Int
    public let powerLevel: Int
    public var positionSubunits: Vec2i
    public let direction: Direction
    /// 60 × speed in mSU/s (the §5.2 integration variable W).
    public var velocity60: Int
    /// Travel accumulator in 1/3 600 000 subunit.
    public var travelRemainder: Int
    public var lifetimeRemainingTicks: Int
    /// The shooter's center on the spawn tick: the launch segment checked
    /// for a muzzle inside a wall (§5.4); nil once the shell has moved.
    public var launchOriginSubunits: Vec2i?
    /// §13 MaxHits: whether this shell has damaged an enemy yet.
    public var damagedEnemy: Bool

    public init(entityID: Int, weaponID: String, ownerEntityID: Int, ownerPlayerID: PlayerID?,
                teamID: Int, powerLevel: Int, positionSubunits: Vec2i, direction: Direction,
                velocity60: Int, lifetimeRemainingTicks: Int, launchOriginSubunits: Vec2i? = nil) {
        self.entityID = entityID
        self.weaponID = weaponID
        self.ownerEntityID = ownerEntityID
        self.ownerPlayerID = ownerPlayerID
        self.teamID = teamID
        self.powerLevel = powerLevel
        self.positionSubunits = positionSubunits
        self.direction = direction
        self.velocity60 = velocity60
        self.travelRemainder = 0
        self.lifetimeRemainingTicks = lifetimeRemainingTicks
        self.launchOriginSubunits = launchOriginSubunits
        self.damagedEnemy = false
    }
}

/// A ground-fire patch on one whole cell (GAME_RULES §7.2). Patches are
/// keyed by (cell, color, source); presentation paints yellow+orange in one
/// cell red, the rules never merge them.
public struct FireHazardState: Codable, Equatable, Sendable {
    public let entityID: Int
    public let cell: Vec2i
    public let color: FireColor
    /// Stable source: the emitting tank's entity id, or a negative stage
    /// environment-fire id.
    public let sourceKey: Int
    public let ownerPlayerID: PlayerID?
    public let createdTick: Int
    public var lifetimeRemainingTicks: Int

    public init(entityID: Int, cell: Vec2i, color: FireColor, sourceKey: Int,
                ownerPlayerID: PlayerID?, createdTick: Int, lifetimeRemainingTicks: Int) {
        self.entityID = entityID
        self.cell = cell
        self.color = color
        self.sourceKey = sourceKey
        self.ownerPlayerID = ownerPlayerID
        self.createdTick = createdTick
        self.lifetimeRemainingTicks = lifetimeRemainingTicks
    }

    public var isEnvironment: Bool { sourceKey < 0 }

    /// Center of the patch's cell.
    public var positionSubunits: Vec2i {
        let cell = SpatialUnits.subunitsPerCell
        return Vec2i(x: self.cell.x * cell + cell / 2, y: self.cell.y * cell + cell / 2)
    }
}

/// One Flag On Guard template cell (GAME_RULES §11.2): its full state when
/// the cycle began, and the quadrants hardened since the last pickup.
public struct FortCellRecord: Codable, Equatable, Sendable {
    public let cell: Vec2i
    public let original: TerrainCell
    public var hardenedMask: Int

    public init(cell: Vec2i, original: TerrainCell, hardenedMask: Int = 0) {
        self.cell = cell
        self.original = original
        self.hardenedMask = hardenedMask
    }
}

/// The defended base. `topLeftSubunits` anchors a 2×2-cell structure.
public struct BaseState: Codable, Equatable, Sendable {
    public let teamID: Int
    public var topLeftSubunits: Vec2i
    public var durability: Int
    public var maxDurability: Int
    public var shieldRemainingTicks: Int
    /// The Flag On Guard cycle: the template's original cells, recorded at
    /// the first pickup and kept until every cell is restored.
    public var fortRecord: [FortCellRecord]
    /// §7.2: the first tick at which ground fire may hurt the base again.
    public var nextFireDamageTick: Int

    public init(teamID: Int, topLeftSubunits: Vec2i, durability: Int = 3,
                maxDurability: Int = 3, shieldRemainingTicks: Int = 0,
                fortRecord: [FortCellRecord] = [], nextFireDamageTick: Int = 0) {
        self.teamID = teamID
        self.topLeftSubunits = topLeftSubunits
        self.durability = durability
        self.maxDurability = maxDurability
        self.shieldRemainingTicks = shieldRemainingTicks
        self.fortRecord = fortRecord
        self.nextFireDamageTick = nextFireDamageTick
    }

    public var sizeSubunits: Int { 2 * SpatialUnits.subunitsPerCell }
}
