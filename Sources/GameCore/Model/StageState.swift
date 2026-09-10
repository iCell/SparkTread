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

    /// Pickup carried by the tank this telegraph will spawn (carrier rule).
    public var carriedPickupID: String?

    public init(entityID: Int, archetypeID: String, spawnPointIndex: Int,
                positionSubunits: Vec2i, ticksRemaining: Int,
                carriedPickupID: String? = nil) {
        self.entityID = entityID
        self.archetypeID = archetypeID
        self.spawnPointIndex = spawnPointIndex
        self.positionSubunits = positionSubunits
        self.ticksRemaining = ticksRemaining
        self.deferTicks = 0
        self.carriedPickupID = carriedPickupID
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
/// A pickup hidden under destructible terrain (the reference editor's
/// hidden-treasure layer): revealed when the covering brick is destroyed.
public struct HiddenPickup: Codable, Equatable, Sendable {
    public var cell: Vec2i
    public var pickupID: String
    public init(cell: Vec2i, pickupID: String) {
        self.cell = cell
        self.pickupID = pickupID
    }
}

public struct StageState: Codable, Equatable, Sendable {
    public var phase: StagePhase
    /// Ordered archetype queue (spawn order is stage data, not dictionary
    /// order — §14.3).
    public var spawnQueue: [String]
    /// Parallel to `spawnQueue`: the pickup each queued enemy carries (nil
    /// for non-carriers). Empty means no carriers. Dequeued together with
    /// `spawnQueue` so the pairing survives spawning.
    public var carriedPickupQueue: [String?]
    /// Treasures hidden under bricks, revealed on destruction (§11).
    public var hiddenPickups: [HiddenPickup]
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
    /// Score bonuses paid when the stage is won (ADR-0012): stage data set
    /// by content from the stage number (`ScoreRules.reference`); `.none`
    /// for worlds without a campaign position (lab, tests).
    public var clearBonus: ScoreRules.ClearBonus
    /// Difficulty-shaped enemy behaviour (ADR-0015), set by content from
    /// the difficulty definition; `.standard` when absent.
    public var enemyBehavior: EnemyBehaviorProfile
    /// Authored director phases in order (ADR-0015) and how many have
    /// fired; `directorSpawned` counts enemies scheduled so far.
    public var directorPhases: [DirectorPhase]
    public var directorPhasesFired: Int
    public var directorSpawned: Int

    public init(spawnQueue: [String], maxAliveEnemies: Int, enemyStartDelayTicks: Int = 240,
                spawnPointsCells: [Vec2i], telegraphTicks: Int = 45,
                playerRespawnCell: Vec2i, dropTable: [String], dropChancePercent: Int = 45,
                carriedPickupQueue: [String?] = [], hiddenPickups: [HiddenPickup] = [],
                clearBonus: ScoreRules.ClearBonus = .none,
                enemyBehavior: EnemyBehaviorProfile = .standard,
                directorPhases: [DirectorPhase] = []) {
        self.clearBonus = clearBonus
        self.enemyBehavior = enemyBehavior
        self.directorPhases = directorPhases
        self.directorPhasesFired = 0
        self.directorSpawned = 0
        self.phase = .playing
        self.spawnQueue = spawnQueue
        self.carriedPickupQueue = carriedPickupQueue
        self.hiddenPickups = hiddenPickups
        self.maxAliveEnemies = maxAliveEnemies
        self.enemyStartDelayTicks = enemyStartDelayTicks
        self.spawnPointsCells = spawnPointsCells
        self.nextSpawnPointIndex = 0
        self.telegraphTicks = telegraphTicks
        self.playerRespawnCell = playerRespawnCell
        self.dropTable = dropTable
        self.dropChancePercent = dropChancePercent
    }

    private enum CodingKeys: String, CodingKey {
        case phase, spawnQueue, carriedPickupQueue, hiddenPickups, maxAliveEnemies
        case enemyStartDelayTicks, spawnPointsCells, nextSpawnPointIndex, telegraphTicks
        case playerRespawnCell, dropTable, dropChancePercent, clearBonus
        case enemyBehavior, directorPhases, directorPhasesFired, directorSpawned
    }

    /// `clearBonus` was added after recordings of this format existed: a
    /// missing key decodes as `.none` (encoding always writes it).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decode(StagePhase.self, forKey: .phase)
        spawnQueue = try c.decode([String].self, forKey: .spawnQueue)
        carriedPickupQueue = try c.decode([String?].self, forKey: .carriedPickupQueue)
        hiddenPickups = try c.decode([HiddenPickup].self, forKey: .hiddenPickups)
        maxAliveEnemies = try c.decode(Int.self, forKey: .maxAliveEnemies)
        enemyStartDelayTicks = try c.decode(Int.self, forKey: .enemyStartDelayTicks)
        spawnPointsCells = try c.decode([Vec2i].self, forKey: .spawnPointsCells)
        nextSpawnPointIndex = try c.decode(Int.self, forKey: .nextSpawnPointIndex)
        telegraphTicks = try c.decode(Int.self, forKey: .telegraphTicks)
        playerRespawnCell = try c.decode(Vec2i.self, forKey: .playerRespawnCell)
        dropTable = try c.decode([String].self, forKey: .dropTable)
        dropChancePercent = try c.decode(Int.self, forKey: .dropChancePercent)
        clearBonus = try c.decodeIfPresent(ScoreRules.ClearBonus.self, forKey: .clearBonus) ?? .none
        enemyBehavior = try c.decodeIfPresent(EnemyBehaviorProfile.self, forKey: .enemyBehavior) ?? .standard
        directorPhases = try c.decodeIfPresent([DirectorPhase].self, forKey: .directorPhases) ?? []
        directorPhasesFired = try c.decodeIfPresent(Int.self, forKey: .directorPhasesFired) ?? 0
        directorSpawned = try c.decodeIfPresent(Int.self, forKey: .directorSpawned) ?? 0
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
        /// Results-table reward category 0…7 (GAME_MECHANICS_SPEC §8.2 last
        /// column; ADR-0012): the reference's results screen lists kills in
        /// these eight categories, four rows of two, multiplied ×1…×4 by row.
        public let rewardCategory: Int
    }

    /// The reference-recovered per-slot table (GAME_MECHANICS_SPEC §8.2):
    /// each weapon family has a distinct property identity — Normal is
    /// 1-armor teaching fodder, Rapid is fragile but the fastest thing on
    /// the field, AP is a 5–6-armor near-stationary fortress, and so on.
    /// (armor, enemy speed level -4…4, power level, equipment, score,
    /// reward category). Per-kill scores are provisional; the reward
    /// category is the recovered §8.2 column, whose results-table role was
    /// verified on the reference's results screens (ADR-0012); shields are
    /// a modern addition on the AP heavies.
    private static let referenceTable: [String: (Int, Int, Int, String?, Int, Int)] = [
        "normal_a": (1, -1, 0, nil, 100, 0),
        "normal_b": (1, -1, 1, "amphi_tank", 150, 0),
        "normal_c": (1, 0, 1, nil, 200, 1),
        "normal_d": (1, 0, 2, "shield_of_moon", 250, 1),
        "rapid_a": (1, 1, 0, nil, 200, 2),
        "rapid_b": (1, 1, 1, "anti_skid", 250, 2),
        "rapid_c": (2, 2, 2, nil, 300, 2),
        "rapid_d": (2, 2, 3, "memory_of_sea", 350, 2),
        "fire_a": (2, -1, 0, nil, 300, 5),
        "fire_b": (2, -1, 1, nil, 350, 5),
        "fire_c": (3, 0, 2, nil, 400, 5),
        "fire_d": (3, 0, 3, "shield_of_moon", 450, 5),
        "ap_a": (5, -4, 0, nil, 400, 6),
        "ap_b": (5, -3, 1, nil, 450, 6),
        "ap_c": (6, -4, 1, nil, 500, 7),
        "ap_d": (6, -3, 2, "amphi_tank", 550, 7),
        "explosion_a": (3, -1, 0, nil, 300, 4),
        "explosion_b": (3, -1, 1, "amphi_tank", 350, 4),
        "explosion_c": (4, -2, 2, nil, 400, 4),
        "explosion_d": (4, -2, 3, "anti_skid", 450, 4),
        "mine_a": (2, -1, 0, nil, 200, 3),
        "mine_b": (2, -1, 1, "anti_skid", 250, 3),
        "mine_c": (2, 0, 1, nil, 300, 3),
        "mine_d": (2, 0, 2, "memory_of_sea", 350, 3),
    ]

    public static func attributes(for archetypeID: String) -> Attributes {
        let family = archetypeID.split(separator: "_").first.map(String.init) ?? "normal"
        let row = referenceTable[archetypeID] ?? (1, -1, 0, nil, 100, 0)
        // Modern addition (owner shield rule): the AP fortresses carry the
        // damage shields — the archetype that teaches "switch to explosives".
        let shield = archetypeID == "ap_c" ? 2 : archetypeID == "ap_d" ? 3 : 0
        // Rapid family hunts the player; AP/explosion lean into the base.
        // Tuned up 2026-09-08 and again 2026-09-09 (owner: enemies must
        // come for the base) — with cost-field navigation the focus roll
        // now translates into an actual approach.
        let baseFocus = switch family {
        case "rapid": 50
        case "ap", "explosion": 90
        default: 80
        }
        return Attributes(armor: row.0, speedLevel: row.1, powerLevel: row.2,
                          score: row.4, shieldHP: shield, baseFocusPercent: baseFocus,
                          equipmentID: row.3, rewardCategory: row.5)
    }
}

extension WorldState {
    /// Spawns a pickup at (or ring-scanned near) a cell — used by stage
    /// authoring for visible starter pickups and by kill drops. Returns
    /// false when no cell within the scan radius can hold it.
    @discardableResult
    public mutating func spawnStagePickup(
        _ pickupID: String, nearCell cell: Vec2i, rules: PickupRuleset = .provisional,
        events: inout [DomainEvent]
    ) -> Bool {
        Stage.spawnPickup(&self, pickupID: pickupID, nearCell: cell, rules: rules, events: &events)
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
