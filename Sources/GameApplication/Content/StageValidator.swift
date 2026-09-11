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
        public var difficulties: Set<String> = ["casual", "standard", "veteran"]
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
            terrainKinds: Set(["ground", "brick", "steel", "white_brick", "white_steel",
                               "water", "ice", "foliage", "base"]))
    }

    /// Content budget: the most enemies one stage may schedule (per entry
    /// and in total). The reference schedules about twenty; the budget is
    /// generous but finite so the loader never admits an unbounded queue.
    public static let maxEnemiesPerStage = 500
    /// §10.6 fairness floor for spawn telegraphs.
    public static let telegraphFairnessFloor = 45
    /// Campaign positions are small integers; the tier table (ADR-0012)
    /// saturates far below this.
    public static let maxStageNumber = 999

    public static func validate(_ def: StageDefinition, known: KnownIDs = .reference) -> [String] {
        var issues: [String] = []
        let arena = ArenaSpecification.universal
        func inBounds(_ c: [Int]) -> Bool {
            c.count == 2 && c[0] >= 0 && c[0] < arena.cellsWide && c[1] >= 0 && c[1] < arena.cellsHigh
        }

        if def.schemaVersion != 1 { issues.append("schema_version \(def.schemaVersion) unsupported (expected 1)") }
        if def.id.isEmpty { issues.append("id is empty") }
        if let number = def.stageNumber {
            if number < 1 || number > maxStageNumber { issues.append("stage_number \(number) outside 1…\(maxStageNumber)") }
        } else {
            issues.append("stage_number missing")
        }
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
            for rect in layer.rects ?? [] {
                if rect.count != 4 || rect[0] > rect[2] || rect[1] > rect[3] {
                    issues.append("malformed rect \(rect) in layer '\(layer.kind)'")
                } else if !inBounds([rect[0], rect[1]]) || !inBounds([rect[2], rect[3]]) {
                    issues.append("rect \(rect) in layer '\(layer.kind)' out of bounds")
                }
            }
            for cell in layer.cells ?? [] where !inBounds(cell) {
                issues.append("cell \(cell) in layer '\(layer.kind)' malformed or out of bounds")
            }
        }

        // Two solidity notions: spawn legality can't place a tank inside any
        // solid cell (brick/steel/water/base); reachability-for-threat floods
        // THROUGH brick (enemies break it) but not steel/water/base.
        let spawnSolid = solidCells(def, brickIsSolid: true)
        let hardWalls = solidCells(def, brickIsSolid: false)
        func footprintInBounds(_ c: [Int]) -> Bool {
            inBounds(c) && c[0] < arena.cellsWide - 1 && c[1] < arena.cellsHigh - 1
        }
        func blocked(_ c: [Int]) -> Bool {
            for dy in 0..<2 { for dx in 0..<2 {
                let x = c[0] + dx, y = c[1] + dy
                if spawnSolid.contains(x * 100 + y) { return true }
                if footprintInBounds(def.baseSpawn),
                   x >= def.baseSpawn[0], x < def.baseSpawn[0] + 2,
                   y >= def.baseSpawn[1], y < def.baseSpawn[1] + 2 { return true }
            } }
            return false
        }

        if !footprintInBounds(def.baseSpawn) { issues.append("base_spawn \(def.baseSpawn) footprint out of bounds") }
        guard let playerCell = def.playerSpawnsByID["1"] else {
            issues.append("player_spawns_by_id missing player 1")
            return issues
        }
        if !footprintInBounds(playerCell) { issues.append("player 1 spawn \(playerCell) footprint out of bounds") }
        else if blocked(playerCell) { issues.append("player 1 spawn \(playerCell) inside blocking terrain") }

        if def.enemySpawns.isEmpty { issues.append("enemy_spawns is empty") }
        for spawn in def.enemySpawns {
            if !footprintInBounds(spawn) { issues.append("enemy spawn \(spawn) footprint out of bounds") }
            else if blocked(spawn) { issues.append("enemy spawn \(spawn) inside blocking terrain") }
        }

        var totalEnemies = 0
        // Content budget (R15-02): a count the builder would turn into an
        // effectively unbounded queue is rejected per entry, before any sum
        // or allocation — an overflow check on the total is not enough.
        for entry in def.enemyComposition where entry.count > maxEnemiesPerStage {
            issues.append("enemy '\(entry.archetype)' count \(entry.count) exceeds the stage budget of \(maxEnemiesPerStage)")
        }
        for entry in def.enemyComposition {
            if !known.enemies.contains(entry.archetype) {
                issues.append("unknown enemy archetype '\(entry.archetype)'")
            }
            if entry.count <= 0 { issues.append("enemy '\(entry.archetype)' count \(entry.count) must be positive") }
            let (sum, overflow) = totalEnemies.addingReportingOverflow(max(0, entry.count))
            if overflow { issues.append("enemy_composition total count overflows") }
            else { totalEnemies = sum }
        }
        if totalEnemies == 0 { issues.append("enemy_composition is empty") }
        var phaseIDs = Set<String>()
        var lastTrigger = -1
        for phase in def.directorPhases ?? [] {
            if phase.id.isEmpty { issues.append("director phase without id") }
            if !phaseIDs.insert(phase.id).inserted { issues.append("director phase '\(phase.id)' repeats") }
            if phase.afterSpawned < 0 || phase.afterSpawned > totalEnemies {
                issues.append("director phase '\(phase.id)' after_spawned \(phase.afterSpawned) outside 0…\(totalEnemies)")
            }
            if phase.afterSpawned < lastTrigger { issues.append("director phase '\(phase.id)' out of trigger order") }
            lastTrigger = max(lastTrigger, phase.afterSpawned)
            for archetype in phase.reinforcements where !known.enemies.contains(archetype) {
                issues.append("director phase '\(phase.id)' unknown enemy archetype '\(archetype)'")
            }
            if phase.reinforcements.count > maxEnemiesPerStage { issues.append("director phase '\(phase.id)' reinforcements exceed the stage budget") }
            if let cap = phase.maxAliveEnemies, cap <= 0 || cap > WorldInvariants.maxCount {
                issues.append("director phase '\(phase.id)' max_alive_enemies \(cap) out of domain")
            }
        }
        if totalEnemies > maxEnemiesPerStage { issues.append("enemy_composition total \(totalEnemies) exceeds the stage budget of \(maxEnemiesPerStage)") }
        if def.maxAliveEnemies <= 0 { issues.append("max_alive_enemies must be positive") }
        if def.maxAliveEnemies > WorldInvariants.maxCount { issues.append("max_alive_enemies \(def.maxAliveEnemies) out of domain") }
        if def.initialEnemyDelayTicks < 0 { issues.append("initial_enemy_delay_ticks negative") }
        if def.initialEnemyDelayTicks > WorldInvariants.maxTicks { issues.append("initial_enemy_delay_ticks \(def.initialEnemyDelayTicks) out of domain") }
        if def.telegraphTicks < telegraphFairnessFloor { issues.append("telegraph_ticks \(def.telegraphTicks) below the 45-tick fairness floor") }
        if def.telegraphTicks > WorldInvariants.maxTicks { issues.append("telegraph_ticks \(def.telegraphTicks) out of domain") }

        for pickup in def.pickupSpawns {
            if !known.pickups.contains(pickup.id) { issues.append("unknown pickup '\(pickup.id)'") }
            if !inBounds(pickup.cell) { issues.append("pickup \(pickup.id) at \(pickup.cell) out of bounds") }
        }

        // Carrier drops index into the interleaved spawn queue (§11).
        var seenCarrierIndices = Set<Int>()
        for drop in def.carriedDrops ?? [] {
            if !known.pickups.contains(drop.pickup) {
                issues.append("carried drop references unknown pickup '\(drop.pickup)'")
            }
            if drop.queueIndex < 0 || drop.queueIndex >= totalEnemies {
                issues.append("carried drop queue_index \(drop.queueIndex) outside 0..<\(totalEnemies)")
            }
            if !seenCarrierIndices.insert(drop.queueIndex).inserted {
                issues.append("duplicate carried drop queue_index \(drop.queueIndex)")
            }
        }

        // Hidden treasures must sit under authored brick (§11): a hidden
        // pickup on open ground would reveal itself on the first tick.
        for hidden in def.hiddenPickups ?? [] {
            if !known.pickups.contains(hidden.id) {
                issues.append("hidden pickup references unknown pickup '\(hidden.id)'")
            }
            if !inBounds(hidden.cell) {
                issues.append("hidden pickup \(hidden.id) at \(hidden.cell) out of bounds")
            } else if authoredKind(def, at: hidden.cell) != "brick" {
                issues.append("hidden pickup \(hidden.id) at \(hidden.cell) is not covered by brick")
            }
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

    /// The final authored terrain kind at a cell, replaying layers in order
    /// (later layers overwrite, mirroring StageBuilder).
    private static func authoredKind(_ def: StageDefinition, at c: [Int]) -> String {
        let arena = ArenaSpecification.universal
        var kind = c[0] == 0 || c[1] == 0 || c[0] == arena.cellsWide - 1
            || c[1] == arena.cellsHigh - 1 ? def.terrain.border : "ground"
        for layer in def.terrain.layers {
            for rect in layer.rects ?? []
            where rect.count == 4 && c[0] >= rect[0] && c[0] <= rect[2]
                && c[1] >= rect[1] && c[1] <= rect[3] {
                kind = layer.kind
            }
            for cell in layer.cells ?? [] where cell == c {
                kind = layer.kind
            }
        }
        return kind
    }

    private static func solidCells(_ def: StageDefinition, brickIsSolid: Bool) -> Set<Int> {
        let arena = ArenaSpecification.universal
        var solid = Set<Int>()
        let solidKinds = brickIsSolid
            ? ["brick", "white_brick", "steel", "white_steel", "water", "base"]
            : ["steel", "white_steel", "water", "base"]
        // Sample the bounded arena rather than iterating untrusted ranges.
        // Later layers can clear walls, exactly as in StageBuilder.
        for y in 0..<arena.cellsHigh {
            for x in 0..<arena.cellsWide {
                if solidKinds.contains(authoredKind(def, at: [x, y])) {
                    solid.insert(x * 100 + y)
                }
            }
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
        for spawn in def.enemySpawns
        where spawn.count == 2 && spawn[0] >= 0 && spawn[0] < arena.cellsWide
            && spawn[1] >= 0 && spawn[1] < arena.cellsHigh
            && !hardWalls.contains(spawn[0] * 100 + spawn[1]) {
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
