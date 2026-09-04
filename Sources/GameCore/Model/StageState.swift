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
        public let speedLevel: Int
        public let powerLevel: Int
        public let score: Int
        /// Damage shield for armored tiers (chip vs shatter rules in Combat).
        public let shieldHP: Int
        /// 0–100: how strongly this archetype pressures the base over the player.
        public let baseFocusPercent: Int
    }

    public static func attributes(for archetypeID: String) -> Attributes {
        let tier = archetypeID.split(separator: "_").last.map(String.init) ?? "a"
        let family = archetypeID.split(separator: "_").first.map(String.init) ?? "normal"
        let base: Attributes = switch tier {
        case "b": Attributes(armor: 3, speedLevel: 0, powerLevel: 0, score: 200, shieldHP: 0, baseFocusPercent: 55)
        case "c": Attributes(armor: 4, speedLevel: 1, powerLevel: 1, score: 300, shieldHP: 2, baseFocusPercent: 60)
        case "d": Attributes(armor: 5, speedLevel: 2, powerLevel: 1, score: 400, shieldHP: 3, baseFocusPercent: 65)
        default: Attributes(armor: 2, speedLevel: 1, powerLevel: 0, score: 100, shieldHP: 0, baseFocusPercent: 50)
        }
        // Rapid family hunts the player harder; normal family leans base.
        let bias = family == "rapid" ? -20 : 0
        return Attributes(armor: base.armor, speedLevel: base.speedLevel,
                          powerLevel: base.powerLevel, score: base.score, shieldHP: base.shieldHP,
                          baseFocusPercent: max(0, min(100, base.baseFocusPercent + bias)))
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
