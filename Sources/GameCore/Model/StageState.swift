/// Stage-scope authoritative state: finite enemy composition, spawn
/// processes, pickups and their placement queue, the Flag On Guard template
/// and the win/loss phase (GAME_RULES §9.3, §10, §11).

public enum StagePhase: String, Codable, Sendable {
    case playing, won, lost
}

/// An enemy spawn process (§9.3): 45 ticks at a reserved spawn point before
/// the tank appears; blocked spawns wait and switch point after 120 ticks.
public struct SpawnTelegraph: Codable, Equatable, Sendable {
    public let entityID: Int
    public let archetypeID: String
    public var spawnPointIndex: Int
    public var positionSubunits: Vec2i // tank top-left when it spawns
    public var ticksRemaining: Int
    public var deferTicks: Int
    public var carriedPickup: CarriedPickup?

    public var carriedPickupID: String? { carriedPickup?.pickupID }

    public init(entityID: Int, archetypeID: String, spawnPointIndex: Int,
                positionSubunits: Vec2i, ticksRemaining: Int,
                carriedPickup: CarriedPickup? = nil) {
        self.entityID = entityID
        self.archetypeID = archetypeID
        self.spawnPointIndex = spawnPointIndex
        self.positionSubunits = positionSubunits
        self.ticksRemaining = ticksRemaining
        self.deferTicks = 0
        self.carriedPickup = carriedPickup
    }
}

/// A placed pickup (§10.2): a grid-aligned 2×2-cell item.
public struct PickupState: Codable, Equatable, Sendable {
    public let entityID: Int
    public let pickupID: String
    /// Top-left cell of the 2×2 area.
    public let cell: Vec2i
    public var lifetimeRemainingTicks: Int
    public var graceTicksRemaining: Int
    /// Critical pickups never expire.
    public let critical: Bool

    public init(entityID: Int, pickupID: String, cell: Vec2i,
                lifetimeRemainingTicks: Int = 1800, graceTicksRemaining: Int = 0, critical: Bool = false) {
        self.entityID = entityID
        self.pickupID = pickupID
        self.cell = cell
        self.lifetimeRemainingTicks = lifetimeRemainingTicks
        self.graceTicksRemaining = graceTicksRemaining
        self.critical = critical
    }

    /// Center of the 2×2 area.
    public var positionSubunits: Vec2i {
        let size = SpatialUnits.subunitsPerCell
        return Vec2i(x: cell.x * size + size, y: cell.y * size + size)
    }

    public var sizeSubunits: Int { SpatialUnits.standardTankFootprintSubunits }
}

/// A pickup hidden under walls (§10.2): revealed when its 2×2 area holds
/// no wall quadrant.
public struct HiddenPickup: Codable, Equatable, Sendable {
    public var cell: Vec2i
    public var pickupID: String
    public var critical: Bool
    public init(cell: Vec2i, pickupID: String, critical: Bool = false) {
        self.cell = cell
        self.pickupID = pickupID
        self.critical = critical
    }
}

/// A drop waiting for a legal, reachable place (§10.2).
public struct PendingPickup: Codable, Equatable, Sendable {
    public let requestID: Int
    public let requestTick: Int
    public let pickupID: String
    public let critical: Bool
    public init(requestID: Int, requestTick: Int, pickupID: String, critical: Bool) {
        self.requestID = requestID
        self.requestTick = requestTick
        self.pickupID = pickupID
        self.critical = critical
    }
}

public struct StageState: Codable, Equatable, Sendable {
    public var phase: StagePhase
    /// Ordered archetype queue (spawn order is stage data).
    public var spawnQueue: [String]
    /// Parallel to `spawnQueue` (or empty): the pickup each queued enemy carries.
    public var carriedPickupQueue: [CarriedPickup?]
    public var hiddenPickups: [HiddenPickup]
    public var maxAliveEnemies: Int
    public var enemyStartDelayTicks: Int
    /// Spawn points as tank top-left cell coordinates.
    public var spawnPointsCells: [Vec2i]
    public var nextSpawnPointIndex: Int
    public var telegraphTicks: Int
    /// §9.3 cadence: whether the first wave has started, and the ticks until
    /// another spawn process may start.
    public var firstWaveStarted: Bool
    public var spawnCooldownTicks: Int
    /// Player respawn cell (top-left), ring-scanned when blocked.
    public var playerRespawnCell: Vec2i
    public var dropTable: [String]
    /// Percent chance (0–100) that an ordinary kill rolls a drop.
    public var dropChancePercent: Int
    /// Drops waiting for placement, and the next request id.
    public var pendingPickups: [PendingPickup]
    public var nextPickupRequestID: Int
    /// Flag On Guard wall cells (§11.2); empty = no temporary walls.
    public var fortTemplate: [Vec2i]
    /// §10.5 brick drops (owner 2026-10-08): permille chance per brick cell
    /// the PLAYER clears, the stage's cap, how many have been granted, and
    /// the cells cleared this tick awaiting the step-7 roll — always empty
    /// at a tick's end.
    public var brickDropChancePermille: Int
    public var brickDropCap: Int
    public var brickDropsGranted: Int
    public var clearedBrickCells: [Vec2i]
    /// Stage-clear bonuses (ADR-0012).
    public var clearBonus: ScoreRules.ClearBonus
    /// Difficulty-shaped enemy behaviour (ADR-0015).
    public var enemyBehavior: EnemyBehaviorProfile
    /// Authored director phases and how many have fired; `directorSpawned`
    /// counts enemies scheduled so far.
    public var directorPhases: [DirectorPhase]
    public var directorPhasesFired: Int
    public var directorSpawned: Int

    public init(spawnQueue: [String], maxAliveEnemies: Int, enemyStartDelayTicks: Int = 240,
                spawnPointsCells: [Vec2i], telegraphTicks: Int = LifecycleRules.spawnProcessTicks,
                playerRespawnCell: Vec2i, dropTable: [String], dropChancePercent: Int = 20,
                carriedPickupQueue: [CarriedPickup?] = [], hiddenPickups: [HiddenPickup] = [],
                fortTemplate: [Vec2i] = [],
                brickDropChancePermille: Int = 15, brickDropCap: Int = 2,
                clearBonus: ScoreRules.ClearBonus = .none,
                enemyBehavior: EnemyBehaviorProfile = .standard,
                directorPhases: [DirectorPhase] = []) {
        self.phase = .playing
        self.spawnQueue = spawnQueue
        self.carriedPickupQueue = carriedPickupQueue
        self.hiddenPickups = hiddenPickups
        self.maxAliveEnemies = maxAliveEnemies
        self.enemyStartDelayTicks = enemyStartDelayTicks
        self.spawnPointsCells = spawnPointsCells
        self.nextSpawnPointIndex = 0
        self.telegraphTicks = telegraphTicks
        self.firstWaveStarted = false
        self.spawnCooldownTicks = 0
        self.playerRespawnCell = playerRespawnCell
        self.dropTable = dropTable
        self.dropChancePercent = dropChancePercent
        self.pendingPickups = []
        self.nextPickupRequestID = 1
        self.fortTemplate = fortTemplate
        self.brickDropChancePermille = brickDropChancePermille
        self.brickDropCap = brickDropCap
        self.brickDropsGranted = 0
        self.clearedBrickCells = []
        self.clearBonus = clearBonus
        self.enemyBehavior = enemyBehavior
        self.directorPhases = directorPhases
        self.directorPhasesFired = 0
        self.directorSpawned = 0
    }
}

/// Enemy archetype attributes (GAME_RULES §9.1): five weapon families × four
/// tiers.
public enum EnemyArchetypes {
    public struct Attributes: Sendable {
        public let armor: Int
        /// Enemy speed level −4…4.
        public let speedLevel: Int
        public let powerLevel: Int
        public let score: Int
        public let shieldHP: Int
        /// 0–100: how strongly this archetype pressures the base.
        public let baseFocusPercent: Int
        public let equipmentID: String?
        /// Results-table category 0…7 (§13): row r holds 2r and 2r+1 at ×(r+1).
        public let rewardCategory: Int
    }

    public static let families = ["normal", "rapid", "fire", "ap", "explosion"]
    public static let tiers = ["a", "b", "c", "d"]
    /// The twenty archetype ids in §9.1 table order.
    public static let allIDs: [String] = families.flatMap { family in tiers.map { "\(family)_\($0)" } }

    /// (armor, shield, speed level, power level, equipment, score, category)
    private static let table: [String: (Int, Int, Int, Int, String?, Int, Int)] = [
        "normal_a": (1, 0, -1, 0, nil, 100, 0),
        "normal_b": (1, 0, -1, 1, "amphi_tank", 150, 0),
        "normal_c": (1, 0, 0, 1, nil, 200, 1),
        "normal_d": (1, 0, 0, 2, nil, 250, 1),
        "rapid_a": (1, 0, 1, 0, nil, 200, 2),
        "rapid_b": (1, 0, 1, 1, "anti_skid", 250, 2),
        "rapid_c": (2, 0, 2, 2, nil, 300, 3),
        "rapid_d": (2, 0, 2, 3, nil, 350, 3),
        "fire_a": (2, 0, -1, 0, nil, 300, 5),
        "fire_b": (2, 0, -1, 1, nil, 350, 5),
        "fire_c": (3, 0, 0, 2, nil, 400, 5),
        "fire_d": (3, 0, 0, 3, nil, 450, 5),
        "ap_a": (5, 0, -4, 0, nil, 400, 6),
        "ap_b": (5, 0, -3, 1, nil, 450, 6),
        "ap_c": (6, 2, -2, 1, nil, 500, 7),
        "ap_d": (6, 3, -3, 2, "amphi_tank", 550, 7),
        "explosion_a": (3, 0, -1, 0, nil, 300, 4),
        "explosion_b": (3, 0, -1, 1, "amphi_tank", 350, 4),
        "explosion_c": (4, 0, -2, 2, nil, 400, 4),
        "explosion_d": (4, 0, -2, 3, "anti_skid", 450, 4),
    ]

    public static func isKnown(_ archetypeID: String) -> Bool { table[archetypeID] != nil }

    public static func attributes(for archetypeID: String) -> Attributes {
        let family = archetypeID.split(separator: "_").first.map(String.init) ?? "normal"
        let row = table[archetypeID] ?? (1, 0, -1, 0, nil, 100, 0)
        let baseFocus = switch family {
        case "rapid": 50
        case "ap", "explosion": 90
        default: 80
        }
        return Attributes(armor: row.0, speedLevel: row.2, powerLevel: row.3,
                          score: row.5, shieldHP: row.1, baseFocusPercent: baseFocus,
                          equipmentID: row.4, rewardCategory: row.6)
    }
}

extension WorldState {
    /// Places a stage-authored pickup at its 2×2 cell; false when the area
    /// cannot hold it.
    @discardableResult
    public mutating func spawnStagePickup(
        _ pickupID: String, atCell cell: Vec2i, critical: Bool = false,
        rules: PickupRuleset = .provisional, events: inout [DomainEvent]
    ) -> Bool {
        guard Stage.pickupAreaIsLegal(self, cell: cell, avoidDynamic: true) else { return false }
        Stage.placePickup(&self, pickupID: pickupID, cell: cell, critical: critical,
                          graceTicks: 0, rules: rules, events: &events)
        return true
    }
}

/// Deterministic ring scan: cells around an origin ordered by Chebyshev
/// radius, then top-to-bottom, then left-to-right.
public enum RingScan {
    public static func cells(around origin: Vec2i, maxRadius: Int) -> [Vec2i] {
        var result = [origin]
        guard maxRadius >= 1 else { return result }
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
