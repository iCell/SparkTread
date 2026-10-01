/// Weapon data contract (GAME_RULES §5). Motion values are the R5 integer
/// rule values in milli-subunits; per-power-level arrays hold exactly four
/// entries (LV0…LV3). The simulation never branches on display names.
public struct WeaponDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let family: WeaponFamily
    public let fireChannel: FireChannel
    /// Special weapons: rounds a weapon pickup / Caisson adds, and the cap.
    public let refillAmount: Int
    public let maxAmmo: Int
    public let cooldownTicks: [Int]
    /// Own in-flight projectiles of this weapon per shooter (§5.3).
    public let maxActive: [Int]
    /// §5.2 motion: initial speed, signed acceleration and speed cap, all
    /// independent of power level.
    public let initialSpeedMilliSubunitsPerSecond: Int
    public let accelerationMilliSubunitsPerSecond2: Int
    public let maxSpeedMilliSubunitsPerSecond: Int
    public let lifetimeTicks: Int
    /// Armor damage of a direct hit (explosion family: of the blast).
    public let tankDamage: [Int]
    /// Depth of the §3.2 damage strip in quadrant rows (0 = no wall damage).
    public let stripDepthQuadrants: [Int]
    /// Strip depth for columns whose first material is red or white brick;
    /// nil = the same as `stripDepthQuadrants` (GAME_RULES R5.5: AP cuts
    /// brick two cells deep, steel one).
    public let brickStripDepthQuadrants: [Int]?
    /// Whether the strip damages grey steel (only AP, §3.1).
    public let breaksSteel: Bool
    /// Blast radius (0 = no blast).
    public let explosionRadiusSubunits: [Int]
    public let presentationID: String

    public init(id: String, family: WeaponFamily, fireChannel: FireChannel,
                refillAmount: Int, maxAmmo: Int, cooldownTicks: [Int], maxActive: [Int],
                initialSpeedMilliSubunitsPerSecond: Int, accelerationMilliSubunitsPerSecond2: Int,
                maxSpeedMilliSubunitsPerSecond: Int, lifetimeTicks: Int,
                tankDamage: [Int], stripDepthQuadrants: [Int], brickStripDepthQuadrants: [Int]? = nil,
                breaksSteel: Bool, explosionRadiusSubunits: [Int], presentationID: String) {
        self.id = id; self.family = family; self.fireChannel = fireChannel
        self.refillAmount = refillAmount; self.maxAmmo = maxAmmo
        self.cooldownTicks = cooldownTicks; self.maxActive = maxActive
        self.initialSpeedMilliSubunitsPerSecond = initialSpeedMilliSubunitsPerSecond
        self.accelerationMilliSubunitsPerSecond2 = accelerationMilliSubunitsPerSecond2
        self.maxSpeedMilliSubunitsPerSecond = maxSpeedMilliSubunitsPerSecond
        self.lifetimeTicks = lifetimeTicks
        self.tankDamage = tankDamage; self.stripDepthQuadrants = stripDepthQuadrants
        self.brickStripDepthQuadrants = brickStripDepthQuadrants
        self.breaksSteel = breaksSteel
        self.explosionRadiusSubunits = explosionRadiusSubunits
        self.presentationID = presentationID
    }

    public func level(_ array: [Int], _ power: Int) -> Int {
        array[max(0, min(3, power))]
    }

    /// The strip depth (quadrant rows) for a column whose first material is `kind`.
    public func stripDepth(for kind: TerrainKind, power: Int) -> Int {
        kind.isBrickFamily ? level(brickStripDepthQuadrants ?? stripDepthQuadrants, power)
            : level(stripDepthQuadrants, power)
    }

    /// Whether this weapon's strip damages a wall material (§3.1).
    public func damages(_ kind: TerrainKind) -> Bool {
        if kind.isBrickFamily { return stripDepthQuadrants.contains { $0 > 0 } }
        if kind == .steel { return breaksSteel }
        return false
    }

    /// Accumulator units per subunit of projectile travel: the §5.2 integer
    /// integration advances `60 × speed` per tick over 3 600 000.
    public static let travelUnitsPerSubunit = 3_600_000

    public static let maxTicks = 216_000
    public static let maxCount = 1_000_000
    public static let maxDamage = 99
    public static let maxRadiusSubunits = 65_536
    /// Fastest legal projectile: one per-tick displacement cap.
    public static var maxSpeedMilliSubunits: Int {
        SpatialUnits.maxPerTickDisplacementSubunits * SpatialUnits.milliSubunitsPerSubunit * 60
    }

    public func validationIssues() -> [String] {
        var issues: [String] = []
        func check(_ name: String, _ values: [Int], max upper: Int) {
            if values.count != 4 { issues.append("\(id).\(name) must have exactly 4 entries") }
            if values.contains(where: { $0 < 0 || $0 > upper }) { issues.append("\(id).\(name) must be 0…\(upper)") }
        }
        check("cooldown_ticks", cooldownTicks, max: Self.maxTicks)
        check("max_active", maxActive, max: Self.maxCount)
        check("tank_damage", tankDamage, max: Self.maxDamage)
        check("strip_depth_quadrants", stripDepthQuadrants, max: 8)
        if let brickStripDepthQuadrants { check("brick_strip_depth_quadrants", brickStripDepthQuadrants, max: 8) }
        check("explosion_radius_subunits", explosionRadiusSubunits, max: Self.maxRadiusSubunits)
        let speedCap = Self.maxSpeedMilliSubunits
        if initialSpeedMilliSubunitsPerSecond < 0 || initialSpeedMilliSubunitsPerSecond > speedCap {
            issues.append("\(id).initial_speed must be 0…\(speedCap)")
        }
        if maxSpeedMilliSubunitsPerSecond < 0 || maxSpeedMilliSubunitsPerSecond > speedCap {
            issues.append("\(id).max_speed must be 0…\(speedCap)")
        }
        if accelerationMilliSubunitsPerSecond2 < -speedCap || accelerationMilliSubunitsPerSecond2 > speedCap {
            issues.append("\(id).acceleration out of domain")
        }
        if lifetimeTicks < 1 || lifetimeTicks > Self.maxTicks { issues.append("\(id).lifetime_ticks must be 1…\(Self.maxTicks)") }
        for (name, value) in [("refill_amount", refillAmount), ("max_ammo", maxAmmo)]
        where value < 0 || value > Self.maxCount {
            issues.append("\(id).\(name) must be 0…\(Self.maxCount)")
        }
        return issues
    }
}

public enum WeaponFamily: String, Codable, Sendable {
    case normal, rapid, fire, ap, explosion
}

/// Ground-fire colour (GAME_RULES §7.3): who a flame hurts. Player fire is
/// yellow (enemy tanks), enemy fire orange (player tanks), stage fire red
/// (every tank).
public enum FireColor: String, Codable, Sendable {
    case yellow, orange, red

    public func hurts(teamID: Int) -> Bool {
        switch self {
        case .yellow: teamID != 1
        case .orange: teamID == 1
        case .red: true
        }
    }

    public static func of(sourceTeam teamID: Int) -> FireColor { teamID == 1 ? .yellow : .orange }
}

/// The weapon ruleset: the five families plus combat-wide tuning.
public struct WeaponRuleset: Codable, Equatable, Sendable {
    public var weapons: [WeaponDefinition]
    /// Half-extent of a projectile's collision box, in subunits.
    public var projectileHalfExtentSubunits: Int
    /// Ground fire: lifetime of a patch, and the per-victim damage cadence.
    public var firePatchLifetimeTicks: Int
    public var fireDamageIntervalTicks: Int
    /// Foliage: ticks from a cell's ignition to its one spread (§7.4).
    public var foliageSpreadDelayTicks: Int
    /// Difficulty-scoped allied base damage (ADR-0005); Standard default.
    public var alliedBaseDamage: Bool
    /// §5.1: how long a normal-fire press stays buffered.
    public var normalFireBufferTicks: Int
    /// §5.1: minimum spacing of dry-fire feedback while a special is held.
    public var dryFireFeedbackIntervalTicks: Int

    public init(weapons: [WeaponDefinition], projectileHalfExtentSubunits: Int = 96,
                firePatchLifetimeTicks: Int = 340, fireDamageIntervalTicks: Int = 30,
                foliageSpreadDelayTicks: Int = 20, alliedBaseDamage: Bool = true,
                normalFireBufferTicks: Int = 10, dryFireFeedbackIntervalTicks: Int = 30) {
        self.weapons = weapons
        self.projectileHalfExtentSubunits = projectileHalfExtentSubunits
        self.firePatchLifetimeTicks = firePatchLifetimeTicks
        self.fireDamageIntervalTicks = fireDamageIntervalTicks
        self.foliageSpreadDelayTicks = foliageSpreadDelayTicks
        self.alliedBaseDamage = alliedBaseDamage
        self.normalFireBufferTicks = normalFireBufferTicks
        self.dryFireFeedbackIntervalTicks = dryFireFeedbackIntervalTicks
    }

    public func weapon(_ id: String) -> WeaponDefinition? {
        weapons.first { $0.id == id }
    }

    public func validationIssues() -> [String] {
        var issues = weapons.flatMap { $0.validationIssues() }
        if Set(weapons.map(\.id)).count != weapons.count { issues.append("weapon ids must be unique") }
        if weapon("normal") == nil { issues.append("the normal weapon is required") }
        let cell = SpatialUnits.subunitsPerCell
        if projectileHalfExtentSubunits < 1 || projectileHalfExtentSubunits > cell {
            issues.append("projectile_half_extent_subunits must be 1…\(cell)")
        }
        let maxTicks = WeaponDefinition.maxTicks
        for (name, value, minimum) in [("fire_patch_lifetime_ticks", firePatchLifetimeTicks, 1),
                                       ("fire_damage_interval_ticks", fireDamageIntervalTicks, 1),
                                       ("foliage_spread_delay_ticks", foliageSpreadDelayTicks, 1),
                                       ("normal_fire_buffer_ticks", normalFireBufferTicks, 1),
                                       ("dry_fire_feedback_interval_ticks", dryFireFeedbackIntervalTicks, 1)]
        where value < minimum || value > maxTicks {
            issues.append("\(name) must be \(minimum)…\(maxTicks)")
        }
        return issues
    }

    /// GAME_RULES §5.2–§5.3 (R5.2: shells at 40 % of R5 speed, same ranges;
    /// R5.3/R5.6: the normal and rapid cooldowns follow the same time scale,
    /// so their shot spacing on the field is R5's again).
    public static let provisional = WeaponRuleset(weapons: [
        WeaponDefinition(
            id: "normal", family: .normal, fireChannel: .normal, refillAmount: 0, maxAmmo: 0,
            cooldownTicks: [35, 30, 25, 20], maxActive: [8, 9, 11, 14],
            initialSpeedMilliSubunitsPerSecond: 6_553_600, accelerationMilliSubunitsPerSecond2: -187_392,
            maxSpeedMilliSubunitsPerSecond: 6_553_600, lifetimeTicks: 270,
            tankDamage: [1, 1, 1, 2], stripDepthQuadrants: [1, 1, 2, 2], breaksSteel: false,
            explosionRadiusSubunits: [0, 0, 0, 0], presentationID: "projectile_normal"),
        WeaponDefinition(
            id: "rapid", family: .rapid, fireChannel: .special, refillAmount: 50, maxAmmo: 250,
            cooldownTicks: [20, 18, 15, 13], maxActive: [24, 28, 32, 36],
            initialSpeedMilliSubunitsPerSecond: 9_362_432, accelerationMilliSubunitsPerSecond2: -280_576,
            maxSpeedMilliSubunitsPerSecond: 9_362_432, lifetimeTicks: 412,
            tankDamage: [1, 1, 1, 1], stripDepthQuadrants: [1, 1, 1, 2], breaksSteel: false,
            explosionRadiusSubunits: [0, 0, 0, 0], presentationID: "projectile_rapid"),
        WeaponDefinition(
            id: "fire", family: .fire, fireChannel: .special, refillAmount: 30, maxAmmo: 150,
            cooldownTicks: [45, 40, 35, 30], maxActive: [3, 3, 4, 4],
            initialSpeedMilliSubunitsPerSecond: 6_553_600, accelerationMilliSubunitsPerSecond2: -562_176,
            maxSpeedMilliSubunitsPerSecond: 6_553_600, lifetimeTicks: 180,
            tankDamage: [0, 0, 0, 0], stripDepthQuadrants: [0, 0, 0, 0], breaksSteel: false,
            explosionRadiusSubunits: [0, 0, 0, 0], presentationID: "projectile_fire"),
        WeaponDefinition(
            id: "ap", family: .ap, fireChannel: .special, refillAmount: 10, maxAmmo: 50,
            cooldownTicks: [40, 36, 32, 28], maxActive: [1, 1, 2, 2],
            initialSpeedMilliSubunitsPerSecond: 2_340_864, accelerationMilliSubunitsPerSecond2: 2_808_832,
            maxSpeedMilliSubunitsPerSecond: 7_021_568, lifetimeTicks: 412,
            tankDamage: [2, 2, 3, 3], stripDepthQuadrants: [2, 2, 2, 2], brickStripDepthQuadrants: [4, 4, 4, 4],
            breaksSteel: true,
            explosionRadiusSubunits: [0, 0, 0, 0], presentationID: "projectile_ap"),
        WeaponDefinition(
            id: "explosion", family: .explosion, fireChannel: .special, refillAmount: 20, maxAmmo: 100,
            cooldownTicks: [50, 46, 42, 38], maxActive: [1, 1, 2, 2],
            initialSpeedMilliSubunitsPerSecond: 3_744_768, accelerationMilliSubunitsPerSecond2: 2_996_224,
            maxSpeedMilliSubunitsPerSecond: 7_489_536, lifetimeTicks: 412,
            tankDamage: [2, 2, 2, 3], stripDepthQuadrants: [0, 0, 0, 0], breaksSteel: false,
            explosionRadiusSubunits: [1024, 1280, 1536, 2048], presentationID: "projectile_explosion"),
    ])
}
