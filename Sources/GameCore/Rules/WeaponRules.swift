/// Weapon data contract (§8.4). Values below are PROVISIONAL M2 Combat Lab
/// tuning seeded from reference-derived bases (§8.3); canonical content
/// migrates to Content/weapons/ JSON once the content pipeline carries
/// weapon schemas. The simulation never branches on display names.
public struct WeaponDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let family: WeaponFamily
    public let fireChannel: FireChannel
    public let ammoCost: Int
    public let refillAmount: Int
    public let maxAmmo: Int
    // Per-power-level arrays: exactly four entries (§8.4).
    public let cooldownTicks: [Int]
    public let maxActive: [Int]
    public let initialSpeedSubunitsPerTick: [Int]
    public let accelerationSubunitsPerTick2: [Int]
    public let maxSpeedSubunitsPerTick: [Int]
    public let lifetimeTicks: [Int]
    public let tankDamage: [Int]
    public let brickDamage: [Int]
    public let steelDamage: [Int]
    public let projectileDurability: [Int]
    public let penetrationCount: [Int]
    public let explosionRadiusSubunits: [Int]
    public let mineTriggerRadiusSubunits: [Int]
    public let statusEffectID: String?
    public let friendlyFirePolicy: String
    public let presentationID: String

    public func level(_ array: [Int], _ power: Int) -> Int {
        array[max(0, min(3, power))]
    }
}

public enum WeaponFamily: String, Codable, Sendable {
    case normal, rapid, fire, ap, explosion, mine
}

/// Fire-hazard team filtering (§8.7).
public enum FireTeamFilter: String, Codable, Sendable {
    case both, alliedOnly, enemyOnly
}

/// The M2 weapon ruleset: the six required families plus combat-wide tuning.
public struct WeaponRuleset: Codable, Equatable, Sendable {
    public var weapons: [WeaponDefinition]
    /// Half-extent of a projectile's collision box, in subunits.
    public var projectileHalfExtentSubunits: Int
    /// Mine hardware collision half-extent, and arming delay after placement.
    public var mineHalfExtentSubunits: Int
    public var mineArmingTicks: Int
    /// Fire hazards damage at most once per this many ticks per tank.
    public var fireDamageIntervalTicks: Int
    /// Chain-detonation wave cap (§8.5, default 8).
    public var chainDetonationWaveCap: Int
    /// Difficulty-scoped allied base damage (ADR-0005); Standard default.
    public var alliedBaseDamage: Bool

    public func weapon(_ id: String) -> WeaponDefinition? {
        weapons.first { $0.id == id }
    }

    public static let provisional = WeaponRuleset(
        weapons: [
            WeaponDefinition(
                id: "normal", family: .normal, fireChannel: .normal,
                ammoCost: 0, refillAmount: 0, maxAmmo: 0,
                cooldownTicks: [14, 12, 10, 8], maxActive: [2, 2, 3, 3],
                initialSpeedSubunitsPerTick: [192, 192, 224, 224],
                accelerationSubunitsPerTick2: [0, 0, 0, 0],
                maxSpeedSubunitsPerTick: [192, 192, 224, 224],
                lifetimeTicks: [600, 600, 600, 600],
                tankDamage: [1, 1, 1, 2], brickDamage: [1, 1, 2, 2], steelDamage: [0, 0, 0, 1],
                projectileDurability: [1, 1, 1, 1], penetrationCount: [0, 0, 0, 0],
                explosionRadiusSubunits: [0, 0, 0, 0], mineTriggerRadiusSubunits: [0, 0, 0, 0],
                statusEffectID: nil, friendlyFirePolicy: "no_allied_damage",
                presentationID: "projectile_normal"),
            WeaponDefinition(
                id: "rapid", family: .rapid, fireChannel: .special,
                ammoCost: 1, refillAmount: 50, maxAmmo: 250,
                cooldownTicks: [8, 7, 6, 5], maxActive: [3, 4, 5, 6],
                initialSpeedSubunitsPerTick: [320, 320, 352, 384],
                accelerationSubunitsPerTick2: [0, 0, 0, 0],
                maxSpeedSubunitsPerTick: [320, 320, 352, 384],
                lifetimeTicks: [600, 600, 600, 600],
                tankDamage: [1, 1, 1, 1], brickDamage: [1, 1, 1, 2], steelDamage: [0, 0, 0, 0],
                projectileDurability: [1, 1, 1, 1], penetrationCount: [0, 0, 0, 0],
                explosionRadiusSubunits: [0, 0, 0, 0], mineTriggerRadiusSubunits: [0, 0, 0, 0],
                statusEffectID: nil, friendlyFirePolicy: "no_allied_damage",
                presentationID: "projectile_rapid"),
            WeaponDefinition(
                id: "fire", family: .fire, fireChannel: .special,
                ammoCost: 1, refillAmount: 30, maxAmmo: 150,
                cooldownTicks: [45, 40, 35, 30], maxActive: [12, 16, 20, 24],
                initialSpeedSubunitsPerTick: [0, 0, 0, 0],
                accelerationSubunitsPerTick2: [0, 0, 0, 0],
                maxSpeedSubunitsPerTick: [0, 0, 0, 0],
                lifetimeTicks: [240, 270, 300, 360], // hazard lifetime
                tankDamage: [1, 1, 1, 2], brickDamage: [0, 0, 0, 0], steelDamage: [0, 0, 0, 0],
                projectileDurability: [0, 0, 0, 0], penetrationCount: [0, 0, 0, 0],
                explosionRadiusSubunits: [0, 0, 0, 0], mineTriggerRadiusSubunits: [0, 0, 0, 0],
                statusEffectID: "burning", friendlyFirePolicy: "enemy_only",
                presentationID: "fx_fire_patch"),
            WeaponDefinition(
                id: "ap", family: .ap, fireChannel: .special,
                ammoCost: 1, refillAmount: 10, maxAmmo: 50,
                cooldownTicks: [40, 36, 32, 28], maxActive: [1, 1, 2, 2],
                initialSpeedSubunitsPerTick: [80, 80, 96, 112],
                accelerationSubunitsPerTick2: [8, 10, 12, 16],
                maxSpeedSubunitsPerTick: [448, 512, 576, 640],
                lifetimeTicks: [600, 600, 600, 600],
                tankDamage: [2, 2, 3, 3], brickDamage: [2, 2, 2, 2], steelDamage: [0, 1, 1, 2],
                projectileDurability: [2, 2, 3, 3], penetrationCount: [1, 2, 3, 4],
                explosionRadiusSubunits: [0, 0, 0, 0], mineTriggerRadiusSubunits: [0, 0, 0, 0],
                statusEffectID: nil, friendlyFirePolicy: "no_allied_damage",
                presentationID: "projectile_ap"),
            WeaponDefinition(
                id: "explosion", family: .explosion, fireChannel: .special,
                ammoCost: 1, refillAmount: 20, maxAmmo: 100,
                cooldownTicks: [50, 46, 42, 38], maxActive: [1, 1, 2, 2],
                initialSpeedSubunitsPerTick: [72, 72, 80, 96],
                accelerationSubunitsPerTick2: [4, 4, 6, 8],
                maxSpeedSubunitsPerTick: [256, 288, 320, 384],
                lifetimeTicks: [600, 600, 600, 600],
                tankDamage: [2, 2, 2, 3], brickDamage: [2, 2, 2, 2], steelDamage: [0, 0, 1, 1],
                projectileDurability: [2, 2, 2, 2], penetrationCount: [0, 0, 0, 0],
                explosionRadiusSubunits: [1024, 1280, 1536, 2048],
                mineTriggerRadiusSubunits: [0, 0, 0, 0],
                statusEffectID: nil, friendlyFirePolicy: "no_allied_damage",
                presentationID: "projectile_explosion"),
            WeaponDefinition(
                id: "mine", family: .mine, fireChannel: .special,
                ammoCost: 1, refillAmount: 15, maxAmmo: 75,
                cooldownTicks: [30, 28, 26, 24], maxActive: [3, 4, 5, 6],
                initialSpeedSubunitsPerTick: [0, 0, 0, 0],
                accelerationSubunitsPerTick2: [0, 0, 0, 0],
                maxSpeedSubunitsPerTick: [0, 0, 0, 0],
                lifetimeTicks: [0, 0, 0, 0], // mines persist until triggered
                tankDamage: [2, 2, 3, 4], brickDamage: [2, 2, 2, 2], steelDamage: [0, 0, 1, 1],
                projectileDurability: [0, 0, 0, 0], penetrationCount: [0, 0, 0, 0],
                explosionRadiusSubunits: [1024, 1152, 1280, 1536],
                mineTriggerRadiusSubunits: [768, 832, 896, 1024],
                statusEffectID: nil, friendlyFirePolicy: "no_allied_damage",
                presentationID: "mine"),
        ],
        projectileHalfExtentSubunits: 96,
        mineHalfExtentSubunits: 256,
        mineArmingTicks: 45,
        fireDamageIntervalTicks: 30,
        chainDetonationWaveCap: 8,
        alliedBaseDamage: true)
}
