/// Stage-scope authoritative state (M3): finite enemy composition, spawn
/// telegraphs, pickups, drop table, and the win/loss phase. Value-typed and
/// Codable like everything else (ADR-0003).

public enum StagePhase: String, Codable, Sendable {
    case playing, won, lost
}

/// A telegraphed enemy spawn (§6.8): visible for at least the telegraph
/// duration before the tank appears; blocked spawns defer deterministically.
public struct SpawnTelegraph: Codable, Equatable, Sendable {
    public let entityID: Int
    public let archetypeID: String
    public var spawnPointIndex: Int
    public var positionSubunits: Vec2i // tank top-left when it spawns
    public var ticksRemaining: Int
    public var deferTicks: Int

    public init(entityID: Int, archetypeID: String, spawnPointIndex: Int,
                positionSubunits: Vec2i, ticksRemaining: Int) {
        self.entityID = entityID
        self.archetypeID = archetypeID
        self.spawnPointIndex = spawnPointIndex
        self.positionSubunits = positionSubunits
        self.ticksRemaining = ticksRemaining
        self.deferTicks = 0
    }
}

/// A collectible pickup entity (§9.3): deterministic position, lifetime,
/// and an avoidance grace period before collection is possible.
public struct PickupState: Codable, Equatable, Sendable {
    public let entityID: Int
    public let pickupID: String
    public var positionSubunits: Vec2i // cell center
    public var lifetimeRemainingTicks: Int
    public var graceTicksRemaining: Int

    public init(entityID: Int, pickupID: String, positionSubunits: Vec2i,
                lifetimeRemainingTicks: Int = 1800, graceTicksRemaining: Int = 45) {
        self.entityID = entityID
        self.pickupID = pickupID
        self.positionSubunits = positionSubunits
        self.lifetimeRemainingTicks = lifetimeRemainingTicks
        self.graceTicksRemaining = graceTicksRemaining
    }
}

/// Stage composition and objective state. `remaining` counts enemies not yet
/// telegraphed; alive/spawning are tracked through the world's tanks and the
/// telegraph list (§18.2: remaining + alive + spawning = expected total).
public struct StageState: Codable, Equatable, Sendable {
    public var phase: StagePhase
    /// Ordered archetype queue (spawn order is stage data, not dictionary
    /// order — §14.3).
    public var spawnQueue: [String]
    public var maxAliveEnemies: Int
    public var enemyStartDelayTicks: Int
    /// Spawn points as tank top-left cell coordinates.
    public var spawnPointsCells: [Vec2i]
    public var nextSpawnPointIndex: Int
    public var telegraphTicks: Int
    /// Player respawn cell (top-left), ring-scanned when blocked (§6.5).
    public var playerRespawnCell: Vec2i
    public var dropTable: [String]
    /// Percent chance (0–100) that a kill rolls a drop.
    public var dropChancePercent: Int

    public init(spawnQueue: [String], maxAliveEnemies: Int, enemyStartDelayTicks: Int = 240,
                spawnPointsCells: [Vec2i], telegraphTicks: Int = 45,
                playerRespawnCell: Vec2i, dropTable: [String], dropChancePercent: Int = 45) {
        self.phase = .playing
        self.spawnQueue = spawnQueue
        self.maxAliveEnemies = maxAliveEnemies
        self.enemyStartDelayTicks = enemyStartDelayTicks
        self.spawnPointsCells = spawnPointsCells
        self.nextSpawnPointIndex = 0
        self.telegraphTicks = telegraphTicks
        self.playerRespawnCell = playerRespawnCell
        self.dropTable = dropTable
        self.dropChancePercent = dropChancePercent
    }
}

/// Enemy archetype attributes (§10.1): 6 weapon families × 4 tiers. The
/// reference-derived table is the starting dataset; PROVISIONAL tuning.
public enum EnemyArchetypes {
    public struct Attributes: Sendable {
        public let armor: Int
        /// Enemy speed level -4…4 (reference curve; 0 = 0.6× player base).
        public let speedLevel: Int
        public let powerLevel: Int
        public let score: Int
        /// Damage shield for armored tiers (chip vs shatter rules in Combat).
        public let shieldHP: Int
        /// 0–100: how strongly this archetype pressures the base over the player.
        public let baseFocusPercent: Int
        /// Equipment variant (mine/traversal interactions, §8.6).
        public let equipmentID: String?
    }

    /// The reference-recovered per-slot table (GAME_MECHANICS_SPEC §8.2):
    /// each weapon family has a distinct property identity — Normal is
    /// 1-armor teaching fodder, Rapid is fragile but the fastest thing on
    /// the field, AP is a 5–6-armor near-stationary fortress, and so on.
    /// (armor, enemy speed level -4…4, power level, equipment, score).
    /// Scores are provisional (the reference reward-class semantics are
    /// unverified); shields are a modern addition on the AP heavies.
    private static let referenceTable: [String: (Int, Int, Int, String?, Int)] = [
        "normal_a": (1, -1, 0, nil, 100),
        "normal_b": (1, -1, 1, "amphi_tank", 150),
        "normal_c": (1, 0, 1, nil, 200),
        "normal_d": (1, 0, 2, "shield_of_moon", 250),
        "rapid_a": (1, 1, 0, nil, 200),
        "rapid_b": (1, 1, 1, "anti_skid", 250),
        "rapid_c": (2, 2, 2, nil, 300),
        "rapid_d": (2, 2, 3, "memory_of_sea", 350),
        "fire_a": (2, -1, 0, nil, 300),
        "fire_b": (2, -1, 1, nil, 350),
        "fire_c": (3, 0, 2, nil, 400),
        "fire_d": (3, 0, 3, "shield_of_moon", 450),
        "ap_a": (5, -4, 0, nil, 400),
        "ap_b": (5, -3, 1, nil, 450),
        "ap_c": (6, -4, 1, nil, 500),
        "ap_d": (6, -3, 2, "amphi_tank", 550),
        "explosion_a": (3, -1, 0, nil, 300),
        "explosion_b": (3, -1, 1, "amphi_tank", 350),
        "explosion_c": (4, -2, 2, nil, 400),
        "explosion_d": (4, -2, 3, "anti_skid", 450),
        "mine_a": (2, -1, 0, nil, 200),
        "mine_b": (2, -1, 1, "anti_skid", 250),
        "mine_c": (2, 0, 1, nil, 300),
        "mine_d": (2, 0, 2, "memory_of_sea", 350),
    ]

    public static func attributes(for archetypeID: String) -> Attributes {
        let family = archetypeID.split(separator: "_").first.map(String.init) ?? "normal"
        let row = referenceTable[archetypeID] ?? (1, -1, 0, nil, 100)
        // Modern addition (owner shield rule): the AP fortresses carry the
        // damage shields — the archetype that teaches "switch to explosives".
        let shield = archetypeID == "ap_c" ? 2 : archetypeID == "ap_d" ? 3 : 0
        // Rapid family hunts the player; AP/explosion lean into the base.
        let baseFocus = switch family {
        case "rapid": 30
        case "ap", "explosion": 70
        default: 50
        }
        return Attributes(armor: row.0, speedLevel: row.1, powerLevel: row.2,
                          score: row.4, shieldHP: shield, baseFocusPercent: baseFocus,
                          equipmentID: row.3)
    }
}

extension WorldState {
    /// Spawns a pickup at (or ring-scanned near) a cell — used by stage
    /// authoring for visible starter pickups and by kill drops.
    public mutating func spawnStagePickup(
        _ pickupID: String, nearCell cell: Vec2i, events: inout [DomainEvent]
    ) {
        Stage.spawnPickup(&self, pickupID: pickupID, nearCell: cell, events: &events)
    }
}

/// Deterministic ring-scan (§6.5, §9.3): cells around an origin ordered by
/// Chebyshev radius, then top-to-bottom, then left-to-right.
public enum RingScan {
    public static func cells(around origin: Vec2i, maxRadius: Int) -> [Vec2i] {
        var result = [origin]
        for radius in 1...maxRadius {
            var ring: [Vec2i] = []
            for dy in -radius...radius {
                for dx in -radius...radius where max(abs(dx), abs(dy)) == radius {
                    ring.append(Vec2i(x: origin.x + dx, y: origin.y + dy))
                }
            }
            ring.sort { ($0.y, $0.x) < ($1.y, $1.x) }
            result += ring
        }
        return result
    }
}
