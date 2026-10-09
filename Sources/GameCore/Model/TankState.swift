/// Stable player identity. V1 runtime contains only player 1; the data
/// model holds capacity for 2.
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

/// Fixed lifecycle timings (GAME_RULES §9.3, §11.3).
public enum LifecycleRules {
    public static let playerRespawnDelayTicks = 60
    public static let playerSpawnProtectionTicks = 120
    public static let playerRespawnArmor = 3
    /// R5.11 (ADR-0024): what a replacement tank starts with — the
    /// campaign-start levels, not the dead tank's (GAME_RULES §11.3).
    public static let respawnSpeedLevel = 1
    public static let respawnPowerLevel = 0
    public static let enemySpawnProtectionTicks = 45
    public static let spawnProcessTicks = 45
    public static let spawnBlockedSwitchTicks = 120
    public static let spawnCadenceTicks = 30
    /// MaxCombos: consecutive qualifying kills at most this far apart.
    public static let comboWindowTicks = 120
}

/// R5.18 (ADR-0027, owner 2026-10-09: 如果当下的生命只有 1，则优先提高获取到
/// 加命装备的几率): while the player's reserves are at or under the
/// threshold, every extra-life entry of a stage's drop table counts
/// `extraLifeWeightScaleAtLowReserves` times in an enemy-death drop's
/// choice (GAME_RULES §10.2). Brick drops never carry a life (§10.5).
public enum DropRules {
    public static let lowReservesThreshold = 1
    public static let extraLifeWeightScaleAtLowReserves = 6
}

public struct PlayerState: Codable, Equatable, Sendable {
    public let playerID: PlayerID
    public var active: Bool
    /// Reserve tanks (GAME_RULES §11.3: one tank in play plus three reserve).
    public var lives: Int
    public var score: Int
    public var tankEntityID: Int?
    public var lifeState: LifeState
    public var specialAmmoByWeapon: [String: Int]
    /// Ticks until respawn while `lifeState == .awaitingRespawn`.
    public var respawnCountdownTicks: Int
    /// Growth retained across deaths and stages.
    public var retainedSpeedLevel: Int
    public var retainedPowerLevel: Int
    public var retainedEquipmentID: String?
    public var retainedSpecialWeaponID: String
    /// §13 statistics: current and best consecutive shot hits, current and
    /// best kill combo, and the tick of the last qualifying kill.
    public var hitStreak: Int
    public var maxHits: Int
    public var comboStreak: Int
    public var maxCombos: Int
    public var lastComboKillTick: Int?

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
        self.retainedSpeedLevel = 1
        self.retainedPowerLevel = 0
        self.retainedEquipmentID = nil
        self.retainedSpecialWeaponID = "rapid"
        self.hitStreak = 0
        self.maxHits = 0
        self.comboStreak = 0
        self.maxCombos = 0
        self.lastComboKillTick = nil
    }
}

public enum FireChannel: String, Codable, Sendable {
    case normal, special
}

/// The attack a tank's death is attributed to (GAME_RULES §13).
public struct KillAttribution: Codable, Equatable, Sendable {
    public var playerID: PlayerID?
    public var byBomb: Bool
    public init(playerID: PlayerID?, byBomb: Bool = false) {
        self.playerID = playerID
        self.byBomb = byBomb
    }
}

/// A pickup an enemy carries and drops on death.
public struct CarriedPickup: Codable, Equatable, Sendable {
    public var pickupID: String
    public var critical: Bool
    public init(pickupID: String, critical: Bool = false) {
        self.pickupID = pickupID
        self.critical = critical
    }
}

/// Authoritative tank state. `positionSubunits` is the TOP-LEFT corner of
/// the nominal 2048×2048 footprint; movement collision insets each side.
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
    /// Ice slide (§4.3): the saved slide direction, remaining budget, and
    /// the accumulator increment saved when the slide began.
    public var slideDirection: Direction?
    public var slideMomentumSubunits: Int
    public var slideIncrement: Int
    /// Integer movement accumulator (§4.1).
    public var movementAccumulator: Int
    public var armor: Int
    public var maxArmor: Int
    /// Extra damage shield (AP-C/D): non-explosive damage chips it, a blast
    /// shatters it; neither overflows into armor.
    public var shieldHP: Int
    public var speedLevel: Int
    public var powerLevel: Int
    public var specialWeaponID: String
    public var equipmentID: String?
    /// Timed statuses: "invincible", "frozen".
    public var statusEffects: [String: Int]
    public var fireCooldowns: [FireChannel: Int]
    public var activeProjectileCounts: [String: Int]
    public var spawnProtectionTicks: Int
    /// The pickup this enemy drops on death (flashing carrier).
    public var carriedPickup: CarriedPickup?
    /// §4.4: set while the tank lost AmphiTank and still overlaps water.
    public var leavingWater: Bool
    /// §7.2: the first tick at which ground fire may hurt this tank again.
    public var nextFireDamageTick: Int
    /// §5.1 input: remaining ticks of the buffered normal press, whether the
    /// special button was held last tick, and dry-fire feedback spacing.
    public var normalFireBufferTicks: Int
    public var specialHeldLastTick: Bool
    public var dryFireFeedbackTicks: Int
    /// Set by the attack that brought armor to zero.
    public var killedBy: KillAttribution?

    public var carriedPickupID: String? { carriedPickup?.pickupID }

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
        self.slideIncrement = 0
        self.movementAccumulator = 0
        self.armor = LifecycleRules.playerRespawnArmor
        self.maxArmor = 8
        self.shieldHP = 0
        self.speedLevel = 0
        self.powerLevel = 0
        self.specialWeaponID = "rapid"
        self.equipmentID = nil
        self.statusEffects = [:]
        self.fireCooldowns = [:]
        self.activeProjectileCounts = [:]
        self.spawnProtectionTicks = LifecycleRules.playerSpawnProtectionTicks
        self.carriedPickup = nil
        self.leavingWater = false
        self.nextFireDamageTick = 0
        self.normalFireBufferTicks = 0
        self.specialHeldLastTick = false
        self.dryFireFeedbackTicks = 0
        self.killedBy = nil
    }
}
