/// Stable player identity (§6.4). V1 runtime contains only player 1; the
/// data model holds capacity for 2 (D-018).
public struct PlayerID: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public init(_ value: Int) { self.rawValue = value }
    public static func < (l: PlayerID, r: PlayerID) -> Bool { l.rawValue < r.rawValue }
    public static let one = PlayerID(1)
    public static let two = PlayerID(2)
}

public enum LifeState: String, Codable, Sendable {
    case active, awaitingRespawn, eliminated
}

public struct PlayerState: Codable, Equatable, Sendable {
    public let playerID: PlayerID
    public var active: Bool
    public var lives: Int
    public var score: Int
    public var tankEntityID: Int?
    public var lifeState: LifeState
    public var specialAmmoByWeapon: [String: Int]
    /// Ticks until respawn while `lifeState == .awaitingRespawn` (§6.5).
    public var respawnCountdownTicks: Int
    /// Upgrades retained across campaign respawns (§6.5 retention policy).
    public var retainedSpeedLevel: Int
    public var retainedPowerLevel: Int
    public var retainedEquipmentID: String?
    public var retainedSpecialWeaponID: String

    public init(playerID: PlayerID, active: Bool = true, lives: Int = 3, score: Int = 0,
                tankEntityID: Int? = nil, lifeState: LifeState = .active,
                specialAmmoByWeapon: [String: Int] = ["rapid": 50]) {
        self.playerID = playerID
        self.active = active
        self.lives = lives
        self.score = score
        self.tankEntityID = tankEntityID
        self.lifeState = lifeState
        self.specialAmmoByWeapon = specialAmmoByWeapon
        self.respawnCountdownTicks = 0
        self.retainedSpeedLevel = 0
        self.retainedPowerLevel = 0
        self.retainedEquipmentID = nil
        self.retainedSpecialWeaponID = "rapid"
    }
}

public enum FireChannel: String, Codable, Sendable {
    case normal, special
}

/// Authoritative tank state (§6.4). `positionSubunits` is the TOP-LEFT corner
/// of the nominal 2048×2048-subunit footprint in the Y-down world; the
/// collision box insets each side by the ruleset's collision inset. The
/// turn-buffer and slide fields are serialized and checksummed from the first
/// golden even while slide logic is inert (M1 deliverable).
public struct TankState: Codable, Equatable, Sendable {
    public let entityID: Int
    public var teamID: Int
    public var ownerPlayerID: PlayerID?
    public var archetypeID: String
    public var positionSubunits: Vec2i
    public var facing: Direction
    public var movementIntent: Direction?
    public var bufferedDirection: Direction?
    public var bufferedDirectionRemainingTicks: Int
    public var slideDirection: Direction?
    public var slideMomentumSubunits: Int
    /// Integer movement accumulator (§7.1) in 1/60000 subunit steps: each tick
    /// adds base speed × permille multiplier; whole subunits are consumed.
    public var movementAccumulator: Int
    public var armor: Int
    public var maxArmor: Int
    /// Damage shield carried by armored enemy tiers: absorbs non-explosive
    /// hits point by point; explosion-class damage shatters it outright.
    public var shieldHP: Int
    public var speedLevel: Int
    public var powerLevel: Int
    public var specialWeaponID: String
    public var equipmentID: String?
    public var statusEffects: [String: Int]
    public var fireCooldowns: [FireChannel: Int]
    public var activeProjectileCounts: [String: Int]
    public var spawnProtectionTicks: Int
    /// Reference carrier rule (§11): a flashing enemy holds this pickup and
    /// drops it when it dies — at a random interior cell by default
    /// (`PickupRuleset.dropsSpawnAtRandomCells`, ADR-0010 item 7), near the
    /// death cell when that flag is off. Nil for non-carriers and players.
    public var carriedPickupID: String?

    public init(entityID: Int, teamID: Int, ownerPlayerID: PlayerID?, archetypeID: String,
                positionSubunits: Vec2i, facing: Direction) {
        self.entityID = entityID
        self.teamID = teamID
        self.ownerPlayerID = ownerPlayerID
        self.archetypeID = archetypeID
        self.positionSubunits = positionSubunits
        self.facing = facing
        self.movementIntent = nil
        self.bufferedDirection = nil
        self.bufferedDirectionRemainingTicks = 0
        self.slideDirection = nil
        self.slideMomentumSubunits = 0
        self.movementAccumulator = 0
        self.armor = 3
        self.maxArmor = 8
        self.shieldHP = 0
        self.speedLevel = 0
        self.powerLevel = 0
        self.specialWeaponID = "rapid"
        self.equipmentID = nil
        self.statusEffects = [:]
        self.fireCooldowns = [:]
        self.activeProjectileCounts = [:]
        self.spawnProtectionTicks = 120
        self.carriedPickupID = nil
    }
}
