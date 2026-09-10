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
    /// Tanks this projectile has already penetrated (ascending). A
    /// penetrating shell damages each distinct target once (§8.4) instead of
    /// re-hitting the tank it is still overlapping.
    public var hitTankIDs: [Int] = []
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
/// `ownerEntityID` is the emitting tank: active-count bookkeeping releases
/// the slot on that tank when the patch burns out, whoever owns it.
public struct FireHazardState: Codable, Equatable, Sendable {
    public let entityID: Int
    public let ownerEntityID: Int
    public let ownerPlayerID: PlayerID?
    public let teamID: Int
    public let filter: FireTeamFilter
    public var positionSubunits: Vec2i // center of a 1-cell patch
    public var lifetimeRemainingTicks: Int
    public let damagePerTouch: Int
    /// Foliage fire (ADR-0017): when the remaining lifetime reaches this
    /// value the flame spreads to the neighbouring foliage cells once; nil
    /// on non-foliage cells and after spreading.
    public var spreadsAtTicks: Int?

    public init(entityID: Int, ownerEntityID: Int, ownerPlayerID: PlayerID?, teamID: Int, filter: FireTeamFilter,
                positionSubunits: Vec2i, lifetimeRemainingTicks: Int, damagePerTouch: Int, spreadsAtTicks: Int? = nil) {
        self.entityID = entityID
        self.ownerEntityID = ownerEntityID
        self.ownerPlayerID = ownerPlayerID
        self.teamID = teamID
        self.filter = filter
        self.positionSubunits = positionSubunits
        self.lifetimeRemainingTicks = lifetimeRemainingTicks
        self.damagePerTouch = damagePerTouch
        self.spreadsAtTicks = spreadsAtTicks
    }
}

/// The defended base (§6.6). `topLeftSubunits` anchors a 2×2-cell structure.
public struct BaseState: Codable, Equatable, Sendable {
    public let teamID: Int
    public var topLeftSubunits: Vec2i
    public var durability: Int
    public var maxDurability: Int
    public var shieldRemainingTicks: Int
    /// Pre-shield terrain kinds of the fort ring in `Stage.baseFortRingCells`
    /// order, recorded when a shield hardens the ring and consumed when it
    /// expires. Empty when no hardening is pending (a shield that started
    /// active without hardening restores nothing).
    public var fortRingRestore: [TerrainKind]
    /// Flame cadence: the base burns at most once per fire-damage interval
    /// across all overlapping patches.
    public var burnCooldownTicks: Int

    /// Campaign base durability is 3 (§6.6, PROVISIONAL); damage states are
    /// visually distinct at 3/2/1/0.
    public init(teamID: Int, topLeftSubunits: Vec2i, durability: Int = 3,
                maxDurability: Int = 3, shieldRemainingTicks: Int = 0,
                fortRingRestore: [TerrainKind] = [], burnCooldownTicks: Int = 0) {
        self.teamID = teamID
        self.topLeftSubunits = topLeftSubunits
        self.durability = durability
        self.maxDurability = maxDurability
        self.shieldRemainingTicks = shieldRemainingTicks
        self.fortRingRestore = fortRingRestore
        self.burnCooldownTicks = burnCooldownTicks
    }

    public var sizeSubunits: Int { 2 * SpatialUnits.subunitsPerCell }
}
