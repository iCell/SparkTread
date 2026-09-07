import GameCore

/// Stage content validation (§15.3): rejects references to unknown IDs,
/// out-of-bounds or blocking-terrain spawns, inconsistent counts, and
/// unreachable base/player regions. Pure logic over a decoded definition;
/// returns actionable messages. The canonical ID sets are passed in so the
/// registry stays the single source (GE-020).
public enum StageValidator {
    /// Registry-backed known IDs. Defaults mirror the seeded id_registry so
    /// GameApplication tests can validate without file I/O; the CLI passes
    /// the live registry.
    public struct KnownIDs: Sendable {
        public var enemies: Set<String>
        public var pickups: Set<String>
        public var themes: Set<String>
        public var terrainKinds: Set<String>
        public init(enemies: Set<String>, pickups: Set<String>,
                    themes: Set<String>, terrainKinds: Set<String>) {
            self.enemies = enemies
            self.pickups = pickups
            self.themes = themes
            self.terrainKinds = terrainKinds
        }
        public static let reference = KnownIDs(
            enemies: Set(["normal", "rapid", "fire", "ap", "explosion", "mine"].flatMap { fam in
                ["a", "b", "c", "d"].map { "\(fam)_\($0)" }
            }),
            pickups: Set(["speed_up", "armor_up", "power_up", "level_up", "max_speed_power",
                          "amphi_tank", "anti_skid", "shield_of_moon", "memory_of_sea",
                          "score_200", "score_500", "score_1000", "score_2000",
                          "invincibility", "base_shield", "freeze_enemy", "bomb", "extra_life",
                          "max_armor_ammo", "ammo_crate",
                          "rapid_weapon", "fire_weapon", "ap_weapon", "explosion_weapon", "mine_weapon"]),
            themes: Set(["frontier", "floodplain", "frozen_works", "iron_citadel"]),
            terrainKinds: Set(["ground", "brick", "steel", "water", "ice", "foliage", "base"]))
    }

    public static func validate(_ def: StageDefinition, known: KnownIDs = .reference) -> [String] {
        var issues: [String] = []
        let arena = ArenaSpecification.universal
        func inBounds(_ c: [Int]) -> Bool {
            c.count == 2 && c[0] >= 0 && c[0] < arena.cellsWide && c[1] >= 0 && c[1] < arena.cellsHigh
        }

        if def.schemaVersion != 1 { issues.append("schema_version \(def.schemaVersion) unsupported (expected 1)") }
        if def.id.isEmpty { issues.append("id is empty") }
        if !known.themes.contains(def.themeID) { issues.append("unknown theme_id '\(def.themeID)'") }
        if def.arenaSpecID != "universal" { issues.append("arena_spec_id must be 'universal'") }
        if UInt64(def.seed) == nil { issues.append("seed '\(def.seed)' is not a valid unsigned integer") }

        if !known.terrainKinds.contains(def.terrain.border) {
            issues.append("unknown border terrain '\(def.terrain.border)'")
        }
        for layer in def.terrain.layers {
            if !known.terrainKinds.contains(layer.kind) {
                issues.append("unknown terrain kind '\(layer.kind)'")
            }
            for rect in layer.rects ?? [] where rect.count != 4 || rect[0] > rect[2] || rect[1] > rect[3] {
                issues.append("malformed rect \(rect) in layer '\(layer.kind)'")
            }
        }

        // Two solidity notions: spawn legality can't place a tank inside any
        // solid cell (brick/steel/water/base); reachability-for-threat floods
        // THROUGH brick (enemies break it) but not steel/water/base.
        let spawnSolid = solidCells(def, brickIsSolid: true)
        let hardWalls = solidCells(def, brickIsSolid: false)
        func blocked(_ c: [Int]) -> Bool { spawnSolid.contains(c[0] * 100 + c[1]) }

        if !inBounds(def.baseSpawn) { issues.append("base_spawn \(def.baseSpawn) out of bounds") }
        guard let playerCell = def.playerSpawnsByID["1"] else {
            issues.append("player_spawns_by_id missing player 1")
            return issues
        }
        if !inBounds(playerCell) { issues.append("player 1 spawn \(playerCell) out of bounds") }
        else if blocked(playerCell) { issues.append("player 1 spawn \(playerCell) inside blocking terrain") }

        if def.enemySpawns.isEmpty { issues.append("enemy_spawns is empty") }
        for spawn in def.enemySpawns {
            if !inBounds(spawn) { issues.append("enemy spawn \(spawn) out of bounds") }
            else if blocked(spawn) { issues.append("enemy spawn \(spawn) inside blocking terrain") }
        }

        var totalEnemies = 0
        for entry in def.enemyComposition {
            if !known.enemies.contains(entry.archetype) {
                issues.append("unknown enemy archetype '\(entry.archetype)'")
            }
            if entry.count <= 0 { issues.append("enemy '\(entry.archetype)' count \(entry.count) must be positive") }
            totalEnemies += max(0, entry.count)
        }
        if totalEnemies == 0 { issues.append("enemy_composition is empty") }
        if def.maxAliveEnemies <= 0 { issues.append("max_alive_enemies must be positive") }
        if def.initialEnemyDelayTicks < 0 { issues.append("initial_enemy_delay_ticks negative") }
        if def.telegraphTicks < 45 { issues.append("telegraph_ticks \(def.telegraphTicks) below the 45-tick fairness floor") }

        for pickup in def.pickupSpawns {
            if !known.pickups.contains(pickup.id) { issues.append("unknown pickup '\(pickup.id)'") }
            if !inBounds(pickup.cell) { issues.append("pickup \(pickup.id) at \(pickup.cell) out of bounds") }
        }
        for drop in def.dropTable where !known.pickups.contains(drop) {
            issues.append("drop_table references unknown pickup '\(drop)'")
        }
        if def.dropChancePercent < 0 || def.dropChancePercent > 100 {
            issues.append("drop_chance_percent \(def.dropChancePercent) outside 0…100")
        }

        // Reachability (§15.3, §11.2): an enemy must be able to reach the
        // base region — either standing next to it or reaching brick that
        // covers it (brick is breakable, so a brick-fronted base still
        // counts as threatenable; a steel-sealed base does not).
        if inBounds(def.baseSpawn), !def.enemySpawns.isEmpty {
            let reachable = reachableFromAnyEnemySpawn(def, hardWalls: hardWalls)
            let baseCells = [def.baseSpawn, [def.baseSpawn[0] + 1, def.baseSpawn[1]],
                             [def.baseSpawn[0], def.baseSpawn[1] + 1],
                             [def.baseSpawn[0] + 1, def.baseSpawn[1] + 1]]
            let approachReachable = neighborsOf(baseCells).contains {
                inBounds($0) && reachable.contains($0[0] * 100 + $0[1])
            }
            if !approachReachable {
                issues.append("no enemy spawn can reach the base region on the undamaged map")
            }
        }
        return issues
    }

    private static func solidCells(_ def: StageDefinition, brickIsSolid: Bool) -> Set<Int> {
        let arena = ArenaSpecification.universal
        var solid = Set<Int>()
        let solidKinds = brickIsSolid
            ? ["brick", "steel", "water", "base"]
            : ["steel", "water", "base"]
        func markIfSolid(_ x: Int, _ y: Int, _ kindName: String) {
            if solidKinds.contains(kindName) { solid.insert(x * 100 + y) }
        }
        for x in 0..<arena.cellsWide {
            markIfSolid(x, 0, def.terrain.border)
            markIfSolid(x, arena.cellsHigh - 1, def.terrain.border)
        }
        for y in 0..<arena.cellsHigh {
            markIfSolid(0, y, def.terrain.border)
            markIfSolid(arena.cellsWide - 1, y, def.terrain.border)
        }
        for layer in def.terrain.layers {
            for rect in layer.rects ?? [] where rect.count == 4 {
                for cy in rect[1]...rect[3] { for cx in rect[0]...rect[2] { markIfSolid(cx, cy, layer.kind) } }
            }
            for cell in layer.cells ?? [] where cell.count == 2 { markIfSolid(cell[0], cell[1], layer.kind) }
        }
        return solid
    }

    private static func neighborsOf(_ cells: [[Int]]) -> [[Int]] {
        var result: [[Int]] = []
        for c in cells {
            for (dx, dy) in [(0, -1), (1, 0), (0, 1), (-1, 0)] { result.append([c[0] + dx, c[1] + dy]) }
        }
        return result
    }

    /// Flood fill from every enemy spawn (4-connected), passing through
    /// everything except `hardWalls` (steel/water/base) — brick is breakable
    /// so it is traversable for threat reachability.
    private static func reachableFromAnyEnemySpawn(_ def: StageDefinition, hardWalls: Set<Int>) -> Set<Int> {
        let arena = ArenaSpecification.universal
        var reachable = Set<Int>()
        var frontier: [[Int]] = []
        for spawn in def.enemySpawns where spawn.count == 2 && !hardWalls.contains(spawn[0] * 100 + spawn[1]) {
            let key = spawn[0] * 100 + spawn[1]
            if reachable.insert(key).inserted { frontier.append(spawn) }
        }
        while let c = frontier.popLast() {
            for (dx, dy) in [(0, -1), (1, 0), (0, 1), (-1, 0)] {
                let nx = c[0] + dx, ny = c[1] + dy
                guard nx >= 0, nx < arena.cellsWide, ny >= 0, ny < arena.cellsHigh else { continue }
                let key = nx * 100 + ny
                if !hardWalls.contains(key), reachable.insert(key).inserted { frontier.append([nx, ny]) }
            }
        }
        return reachable
    }
}
