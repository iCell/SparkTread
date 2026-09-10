import GameCore

/// Canonical stage schema (§11.1), decoded from Content/stages/*.json.
/// Codable is standard-library only — decoding (JSONDecoder, Foundation)
/// happens in StageLoader. Terrain is authored as rects/cells per kind
/// rather than a 56×27 dump so it stays reviewable and diffable.
public struct StageDefinition: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: String
    /// Campaign position, 1-based (required by the validator): selects the
    /// stage-clear bonus tier (`ScoreRules.reference`, ADR-0012). Optional
    /// in the schema so a missing key is reported, not a decoding failure.
    public var stageNumber: Int?
    public var displayNameKey: String
    public var themeID: String
    public var arenaSpecID: String
    /// Stable seed as a decimal string (JSON numbers can't hold UInt64 safely).
    public var seed: String
    public var terrain: TerrainSpec
    public var baseSpawn: [Int]              // [x, y] cell
    public var playerSpawnsByID: [String: [Int]]
    /// Ordered so the spawn queue is deterministic (§14.3 — no map iteration).
    public var enemyComposition: [EnemyEntry]
    public var enemySpawns: [[Int]]          // [[x, y]…] cells
    public var maxAliveEnemies: Int
    public var initialEnemyDelayTicks: Int
    public var telegraphTicks: Int
    public var pickupSpawns: [PickupSpawn]
    public var dropTable: [String]
    public var dropChancePercent: Int
    /// Carrier drops (reference rule): the enemy at `queueIndex` in the
    /// interleaved spawn queue carries `pickup` and drops it on death.
    public var carriedDrops: [CarriedDrop]?
    /// Treasures hidden under brick cells, revealed on destruction.
    public var hiddenPickups: [PickupSpawn]?

    public struct TerrainSpec: Codable, Equatable, Sendable {
        public var border: String            // terrain kind for the arena border
        public var layers: [Layer]

        public struct Layer: Codable, Equatable, Sendable {
            public var kind: String
            /// Filled rectangles [x0, y0, x1, y1] inclusive.
            public var rects: [[Int]]?
            /// Individual cells [x, y].
            public var cells: [[Int]]?
        }
    }

    public struct EnemyEntry: Codable, Equatable, Sendable {
        public var archetype: String
        public var count: Int
    }

    public struct PickupSpawn: Codable, Equatable, Sendable {
        public var id: String
        public var cell: [Int]
    }

    public struct CarriedDrop: Codable, Equatable, Sendable {
        public var queueIndex: Int
        public var pickup: String
    }
}
