/// Combat entities (M2). All value types, Codable, kept in ascending
/// entity-ID order inside WorldState (ADR-0003, §14.3).

/// A projectile in flight. `positionSubunits` is the CENTER of its collision
/// box (half-extent from the weapon ruleset).
public struct ProjectileState: Codable, Equatable, Sendable {
    public let entityID: Int
    public let weaponID: String
    public let ownerEntityID: Int
    public let ownerPlayerID: PlayerID?
    public let teamID: Int
    public let powerLevel: Int
    public var positionSubunits: Vec2i
    public let direction: Direction
    public var speedSubunitsPerTick: Int
    public var lifetimeRemainingTicks: Int
    public var penetrationRemaining: Int
    public let durability: Int
}

public enum MinePhase: String, Codable, Sendable {
    case arming, armed
}

/// A placed mine. Position is the center of its hardware box.
public struct MineState: Codable, Equatable, Sendable {
    public let entityID: Int
    public let level: Int
    public let ownerEntityID: Int
    public let ownerPlayerID: PlayerID?
    public let teamID: Int
    public var positionSubunits: Vec2i
    public var phase: MinePhase
    public var phaseTicksRemaining: Int
    public let triggerRadiusSubunits: Int
    public let onWater: Bool
}

/// A lingering flame patch (fire family). Cell-sized area of denial.
public struct FireHazardState: Codable, Equatable, Sendable {
    public let entityID: Int
    public let ownerPlayerID: PlayerID?
    public let teamID: Int
    public let filter: FireTeamFilter
    public var positionSubunits: Vec2i // center of a 1-cell patch
    public var lifetimeRemainingTicks: Int
    public let damagePerTouch: Int
}

/// The defended base (minimal M2 shape; full rules land in M3).
/// `topLeftSubunits` anchors a 2×2-cell structure.
public struct BaseState: Codable, Equatable, Sendable {
    public let teamID: Int
    public var topLeftSubunits: Vec2i
    public var durability: Int
    public var maxDurability: Int
    public var shieldRemainingTicks: Int

    public init(teamID: Int, topLeftSubunits: Vec2i, durability: Int = 100,
                maxDurability: Int = 100, shieldRemainingTicks: Int = 0) {
        self.teamID = teamID
        self.topLeftSubunits = topLeftSubunits
        self.durability = durability
        self.maxDurability = maxDurability
        self.shieldRemainingTicks = shieldRemainingTicks
    }

    public var sizeSubunits: Int { 2 * SpatialUnits.subunitsPerCell }
}
