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

    /// Documented domains (§15.3) so validation is total over decoded
    /// integers and the simulation's arithmetic stays far from overflow.
    public static let maxTicks = 216_000
    public static let maxCount = 1_000_000
    public static let maxDamage = 99
    public static let maxRadiusSubunits = 65_536

    /// §8.4: every per-level array has exactly four entries; every value
    /// sits inside its domain; per-tick displacement never exceeds the §7.4
    /// cap.
    public func validationIssues() -> [String] {
        var issues: [String] = []
        func check(_ name: String, _ values: [Int], max upper: Int) {
            if values.count != 4 { issues.append("\(id).\(name) must have exactly 4 entries") }
            if values.contains(where: { $0 < 0 || $0 > upper }) { issues.append("\(id).\(name) must be 0…\(upper)") }
        }
        check("cooldown_ticks", cooldownTicks, max: Self.maxTicks)
        check("max_active", maxActive, max: Self.maxCount)
        check("initial_speed_subunits_per_tick", initialSpeedSubunitsPerTick, max: SpatialUnits.maxPerTickDisplacementSubunits)
        check("acceleration_subunits_per_tick2", accelerationSubunitsPerTick2, max: SpatialUnits.maxPerTickDisplacementSubunits)
        check("max_speed_subunits_per_tick", maxSpeedSubunitsPerTick, max: SpatialUnits.maxPerTickDisplacementSubunits)
        check("lifetime_ticks", lifetimeTicks, max: Self.maxTicks)
        check("tank_damage", tankDamage, max: Self.maxDamage)
        check("brick_damage", brickDamage, max: Self.maxDamage)
        check("steel_damage", steelDamage, max: Self.maxDamage)
        check("projectile_durability", projectileDurability, max: Self.maxCount)
        check("penetration_count", penetrationCount, max: Self.maxCount)
        check("explosion_radius_subunits", explosionRadiusSubunits, max: Self.maxRadiusSubunits)
        check("mine_trigger_radius_subunits", mineTriggerRadiusSubunits, max: Self.maxRadiusSubunits)
        for (name, value) in [("ammo_cost", ammoCost), ("refill_amount", refillAmount), ("max_ammo", maxAmmo)]
        where value < 0 || value > Self.maxCount {
            issues.append("\(id).\(name) must be 0…\(Self.maxCount)")
        }
        return issues
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
    /// Mine launch/flight (§8.6, ADR-0016), per mine level 0…3: how far
    /// the triggering tank is thrown along its travel direction, how long
    /// it stays airborne (uncontrollable, untargetable, suspended from all
    /// interactions), and how long it is slowed after landing. Level 0
    /// launches nothing. `mineLaunchEnabled` disables the whole effect.
    public var mineLaunchDistanceSubunits: [Int]
    public var mineAirborneTicks: [Int]
    public var mineSlowTicks: [Int]
    public var mineLaunchEnabled: Bool

    public init(weapons: [WeaponDefinition], projectileHalfExtentSubunits: Int, mineHalfExtentSubunits: Int,
                mineArmingTicks: Int, fireDamageIntervalTicks: Int, chainDetonationWaveCap: Int,
                alliedBaseDamage: Bool,
                mineLaunchDistanceSubunits: [Int] = [0, 1024, 1536, 2048],
                mineAirborneTicks: [Int] = [0, 18, 24, 30],
                mineSlowTicks: [Int] = [0, 60, 90, 120],
                mineLaunchEnabled: Bool = true) {
        self.weapons = weapons
        self.projectileHalfExtentSubunits = projectileHalfExtentSubunits
        self.mineHalfExtentSubunits = mineHalfExtentSubunits
        self.mineArmingTicks = mineArmingTicks
        self.fireDamageIntervalTicks = fireDamageIntervalTicks
        self.chainDetonationWaveCap = chainDetonationWaveCap
        self.alliedBaseDamage = alliedBaseDamage
        self.mineLaunchDistanceSubunits = mineLaunchDistanceSubunits
        self.mineAirborneTicks = mineAirborneTicks
        self.mineSlowTicks = mineSlowTicks
        self.mineLaunchEnabled = mineLaunchEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case weapons, projectileHalfExtentSubunits, mineHalfExtentSubunits, mineArmingTicks
        case fireDamageIntervalTicks, chainDetonationWaveCap, alliedBaseDamage
        case mineLaunchDistanceSubunits, mineAirborneTicks, mineSlowTicks, mineLaunchEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weapons = try c.decode([WeaponDefinition].self, forKey: .weapons)
        projectileHalfExtentSubunits = try c.decode(Int.self, forKey: .projectileHalfExtentSubunits)
        mineHalfExtentSubunits = try c.decode(Int.self, forKey: .mineHalfExtentSubunits)
        mineArmingTicks = try c.decode(Int.self, forKey: .mineArmingTicks)
        fireDamageIntervalTicks = try c.decode(Int.self, forKey: .fireDamageIntervalTicks)
        chainDetonationWaveCap = try c.decode(Int.self, forKey: .chainDetonationWaveCap)
        alliedBaseDamage = try c.decode(Bool.self, forKey: .alliedBaseDamage)
        mineLaunchDistanceSubunits = try c.decodeIfPresent([Int].self, forKey: .mineLaunchDistanceSubunits) ?? [0, 1024, 1536, 2048]
        mineAirborneTicks = try c.decodeIfPresent([Int].self, forKey: .mineAirborneTicks) ?? [0, 18, 24, 30]
        mineSlowTicks = try c.decodeIfPresent([Int].self, forKey: .mineSlowTicks) ?? [0, 60, 90, 120]
        mineLaunchEnabled = try c.decodeIfPresent(Bool.self, forKey: .mineLaunchEnabled) ?? true
    }

    public func weapon(_ id: String) -> WeaponDefinition? {
        weapons.first { $0.id == id }
    }

    /// Ruleset-wide validation (§15.3): unique IDs, the `normal` weapon
    /// present, geometry inside a cell, cadence values inside their domains.
    public func validationIssues() -> [String] {
        var issues = weapons.flatMap { $0.validationIssues() }
        if Set(weapons.map(\.id)).count != weapons.count { issues.append("weapon ids must be unique") }
        if weapon("normal") == nil { issues.append("the normal weapon is required") }
        let cell = SpatialUnits.subunitsPerCell
        if projectileHalfExtentSubunits < 1 || projectileHalfExtentSubunits > cell {
            issues.append("projectile_half_extent_subunits must be 1…\(cell)")
        }
        if mineHalfExtentSubunits < 1 || mineHalfExtentSubunits > cell {
            issues.append("mine_half_extent_subunits must be 1…\(cell)")
        }
        if mineArmingTicks < 0 || mineArmingTicks > WeaponDefinition.maxTicks { issues.append("mine_arming_ticks must be 0…\(WeaponDefinition.maxTicks)") }
        if fireDamageIntervalTicks < 1 || fireDamageIntervalTicks > WeaponDefinition.maxTicks {
            issues.append("fire_damage_interval_ticks must be 1…\(WeaponDefinition.maxTicks)")
        }
        if chainDetonationWaveCap < 1 || chainDetonationWaveCap > 64 { issues.append("chain_detonation_wave_cap must be 1…64") }
        for (name, values) in [("mine_launch_distance_subunits", mineLaunchDistanceSubunits),
                               ("mine_airborne_ticks", mineAirborneTicks), ("mine_slow_ticks", mineSlowTicks)] {
            if values.count != 4 { issues.append("\(name) must have 4 entries") }
        }
        if mineLaunchDistanceSubunits.contains(where: { $0 < 0 || $0 > 8 * SpatialUnits.subunitsPerCell }) {
            issues.append("mine_launch_distance_subunits must be 0…\(8 * SpatialUnits.subunitsPerCell)")
        }
        if (mineAirborneTicks + mineSlowTicks).contains(where: { $0 < 0 || $0 > WeaponDefinition.maxTicks }) {
            issues.append("mine airborne/slow ticks must be 0…\(WeaponDefinition.maxTicks)")
        }
        if mineLaunchEnabled, zip(mineLaunchDistanceSubunits, mineAirborneTicks).contains(where: { $0 > 0 && $1 == 0 }) {
            issues.append("a launch distance needs airborne ticks")
        }
        return issues
    }

    public static let provisional = WeaponRuleset(
        weapons: [
            WeaponDefinition(
                id: "normal", family: .normal, fireChannel: .normal,
                ammoCost: 0, refillAmount: 0, maxAmmo: 0,
                cooldownTicks: [14, 12, 10, 8], maxActive: [6, 6, 8, 8],
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
