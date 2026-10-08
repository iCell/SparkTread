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
            enemies: Set(EnemyArchetypes.allIDs),
            pickups: Set(["speed_up", "armor_up", "power_up", "level_up", "max_speed_power",
                          "amphi_tank", "anti_skid",
                          "score_200", "score_500", "score_1000", "score_2000",
                          "invincibility", "base_shield", "freeze_enemy", "bomb", "extra_life",
                          "max_armor_ammo", "ammo_crate",
                          "rapid_weapon", "fire_weapon", "ap_weapon", "explosion_weapon"]),
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
        // GAME_RULES §9.3: a phase triggers once N enemies were scheduled,
        // N never above what was planned before it (its own reinforcements
        // excluded), so every phase is reachable.
        var plannedBefore = totalEnemies
        for phase in def.directorPhases ?? [] {
            if phase.id.isEmpty { issues.append("director phase without id") }
            if !phaseIDs.insert(phase.id).inserted { issues.append("director phase '\(phase.id)' repeats") }
            if phase.afterSpawned < 0 || phase.afterSpawned > plannedBefore {
                issues.append("director phase '\(phase.id)' after_spawned \(phase.afterSpawned) outside 0…\(plannedBefore)")
            }
            plannedBefore += min(phase.reinforcements.count, maxEnemiesPerStage)
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

        func areaCells(_ c: [Int]) -> [[Int]] { [c, [c[0] + 1, c[1]], [c[0], c[1] + 1], [c[0] + 1, c[1] + 1]] }
        func areaOverlapsBase(_ c: [Int]) -> Bool {
            footprintInBounds(def.baseSpawn) && c[0] < def.baseSpawn[0] + 2 && c[0] + 2 > def.baseSpawn[0]
                && c[1] < def.baseSpawn[1] + 2 && c[1] + 2 > def.baseSpawn[1]
        }
        for pickup in def.pickupSpawns {
            if !known.pickups.contains(pickup.id) { issues.append("unknown pickup '\(pickup.id)'") }
            if !footprintInBounds(pickup.cell) {
                issues.append("pickup \(pickup.id) at \(pickup.cell) out of bounds")
            } else if areaOverlapsBase(pickup.cell) || areaCells(pickup.cell).contains(where: {
                let cell = authoredCell(def, at: $0)
                return cell.kind.isSolidStructure || cell.surface == .water
            }) {
                issues.append("pickup \(pickup.id) at \(pickup.cell) is not on open ground")
            }
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

        // Hidden pickups (GAME_RULES §10.2) sit under breakable walls: a
        // 2×2 area with at least one brick or grey-steel cell, no white
        // steel, no water, clear of the base.
        for hidden in def.hiddenPickups ?? [] {
            if !known.pickups.contains(hidden.id) {
                issues.append("hidden pickup references unknown pickup '\(hidden.id)'")
            }
            guard footprintInBounds(hidden.cell) else {
                issues.append("hidden pickup \(hidden.id) at \(hidden.cell) out of bounds")
                continue
            }
            let cells = areaCells(hidden.cell).map { authoredCell(def, at: $0) }
            if areaOverlapsBase(hidden.cell) || cells.contains(where: { $0.kind == .whiteSteel || $0.kind == .base || $0.surface == .water }) {
                issues.append("hidden pickup \(hidden.id) at \(hidden.cell) overlaps the base, white steel or water")
            } else if !cells.contains(where: { $0.kind.isBrickFamily || $0.kind == .steel }) {
                issues.append("hidden pickup \(hidden.id) at \(hidden.cell) is not covered by a wall")
            }
        }
        for cell in def.fortTemplate ?? [] where !inBounds(cell) {
            issues.append("fort template cell \(cell) malformed or out of bounds")
        }
        // A base shield hardens the template (§11.2): a stage without one
        // has a shield pickup that does nothing — the Training Arena shipped
        // that way until 2026-10-08 — and a template cell that is not brick
        // in the authored map hardens air.
        if (def.fortTemplate ?? []).isEmpty {
            issues.append("fortTemplate is empty: the base shield would harden nothing")
        }
        for cell in def.fortTemplate ?? [] where inBounds(cell) {
            let kind = authoredCell(def, at: cell).kind
            if !kind.isBrickFamily {
                issues.append("fort template cell \(cell) is \(kind), not brick")
            }
        }
        for fire in def.environmentFires ?? [] {
            if !inBounds(fire.cell) { issues.append("environment fire \(fire.cell) malformed or out of bounds") }
            if fire.lifetimeTicks < 1 || fire.lifetimeTicks > WorldInvariants.maxTicks {
                issues.append("environment fire lifetime \(fire.lifetimeTicks) out of domain")
            }
        }
        // GAME_RULES §2.3: walls and foliage never stand on water.
        for layer in def.terrain.layers where ["brick", "white_brick", "steel", "white_steel", "foliage", "base"].contains(layer.kind) {
            var placed: [[Int]] = layer.cells ?? []
            for rect in layer.rects ?? [] where rect.count == 4 && rect[0] <= rect[2] && rect[1] <= rect[3]
                && inBounds([rect[0], rect[1]]) && inBounds([rect[2], rect[3]]) {
                for y in rect[1]...rect[3] { for x in rect[0]...rect[2] { placed.append([x, y]) } }
            }
            if placed.contains(where: { inBounds($0) && authoredCell(def, at: $0).surface == .water }) {
                issues.append("layer '\(layer.kind)' places a wall or foliage on water")
            }
        }
        for drop in def.dropTable where !known.pickups.contains(drop) {
            issues.append("drop_table references unknown pickup '\(drop)'")
        }
        if def.dropChancePercent < 0 || def.dropChancePercent > 100 {
            issues.append("drop_chance_percent \(def.dropChancePercent) outside 0…100")
        }
        if let permille = def.brickDropChancePermille, permille < 0 || permille > 1000 {
            issues.append("brickDropChancePermille \(permille) outside 0…1000")
        }
        if let cap = def.brickDropCap, cap < 0 {
            issues.append("brickDropCap \(cap) negative")
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

    /// The final authored cell (top kind and surface), replaying layers
    /// the way StageBuilder stacks them.
    static func authoredCell(_ def: StageDefinition, at c: [Int]) -> TerrainCell {
        let arena = ArenaSpecification.universal
        func kind(_ name: String) -> TerrainKind {
            switch name {
            case "brick": .brick
            case "steel": .steel
            case "white_brick": .whiteBrick
            case "white_steel": .whiteSteel
            case "water": .water
            case "ice": .ice
            case "foliage": .foliage
            case "base": .base
            default: .ground
            }
        }
        let border = c[0] == 0 || c[1] == 0 || c[0] == arena.cellsWide - 1 || c[1] == arena.cellsHigh - 1
        var cell = TerrainCell(kind: border ? kind(def.terrain.border) : .ground)
        for layer in def.terrain.layers {
            let covers = (layer.rects ?? []).contains { rect in
                rect.count == 4 && c[0] >= rect[0] && c[0] <= rect[2] && c[1] >= rect[1] && c[1] <= rect[3]
            } || (layer.cells ?? []).contains { $0 == c }
            guard covers else { continue }
            let k = kind(layer.kind)
            cell = k.isSurface ? TerrainCell(kind: k) : TerrainCell(kind: k, surface: cell.surface)
        }
        return cell
    }

    private static func solidCells(_ def: StageDefinition, brickIsSolid: Bool) -> Set<Int> {
        let arena = ArenaSpecification.universal
        var solid = Set<Int>()
        // Sample the bounded arena rather than iterating untrusted ranges.
        for y in 0..<arena.cellsHigh {
            for x in 0..<arena.cellsWide {
                let cell = authoredCell(def, at: [x, y])
                let solidCell = cell.surface == .water || cell.kind == .base || cell.kind.isSteelFamily
                    || (brickIsSolid && cell.kind.isBrickFamily)
                if solidCell { solid.insert(x * 100 + y) }
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
