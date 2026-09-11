import GameCore

/// The Training Arena (plan §5.2; owner direction 2026-09-10 late evening):
/// every terrain kind and wall state, one enemy per weapon family driving
/// and firing its family weapon, a pickup spawner, an invulnerable base, a
/// player with practically unlimited lives, and enemies that respawn the
/// moment they die. The arena is a stage world (the enemy brain and the
/// player lifecycle need one) whose objective can never resolve; its
/// lab-only rules live in `MovementLabSession` (`training: true`), never
/// in GameCore. The M1 movement fixture (`MovementLabFixture`) stays as
/// it is for the golden replay.
public enum TrainingArenaFixture {
    public static let seed: UInt64 = 0x5452_4149_4E41_5245 // "TRAINARE"
    public static let playerLives = 999
    public static let baseDurability = 999
    public static let playerSpawnCell = Vec2i(x: 23, y: 24)

    /// Enemy (re)spawn cells, used round-robin by the respawn rule.
    public static let enemySpawnCells: [Vec2i] = [
        Vec2i(x: 2, y: 1), Vec2i(x: 16, y: 1), Vec2i(x: 27, y: 1), Vec2i(x: 38, y: 1), Vec2i(x: 53, y: 1),
        Vec2i(x: 2, y: 12), Vec2i(x: 53, y: 12),
    ]

    /// Every pickup the content pipeline knows, in a display order.
    public static let pickupIDs: [String] = [
        "speed_up", "armor_up", "power_up", "level_up", "max_speed_power", "max_armor_ammo", "ammo_crate",
        "rapid_weapon", "fire_weapon", "ap_weapon", "explosion_weapon", "mine_weapon",
        "amphi_tank", "anti_skid", "shield_of_moon", "memory_of_sea",
        "invincibility", "base_shield", "freeze_enemy", "bomb", "extra_life",
        "score_200", "score_500", "score_1000", "score_2000",
    ]

    /// Every enemy archetype, offered on the training panel one button
    /// each (owner 2026-09-10: "点击一个按钮增加一个类型的坦克"), sorted by
    /// resistance — armour plus shield — from low to high, then by family
    /// and tier for ties. The arena starts with no enemies.
    public struct RosterEntry: Equatable, Sendable {
        public let archetypeID: String
        public let family: String
        public let tier: String
        public let resistance: Int
    }

    public static let enemyRoster: [RosterEntry] = {
        let families = ["normal", "rapid", "fire", "ap", "explosion", "mine"]
        var entries: [RosterEntry] = []
        for (f, family) in families.enumerated() {
            for (t, tier) in ["a", "b", "c", "d"].enumerated() {
                let id = "\(family)_\(tier)"
                let attributes = EnemyArchetypes.attributes(for: id)
                entries.append(RosterEntry(archetypeID: id, family: family, tier: tier.uppercased(),
                                           resistance: attributes.armor + attributes.shieldHP))
                _ = (f, t)
            }
        }
        return entries.sorted {
            if $0.resistance != $1.resistance { return $0.resistance < $1.resistance }
            let fa = families.firstIndex(of: $0.family) ?? 0, fb = families.firstIndex(of: $1.family) ?? 0
            if fa != fb { return fa < fb }
            return $0.tier < $1.tier
        }
    }()

    public static let enemyArchetypes: [String] = enemyRoster.map(\.archetypeID)

    /// The six weapon families the panel offers (owner 2026-09-10: one
    /// button per family, then its power level and equipment).
    public static let enemyFamilies = ["normal", "rapid", "fire", "ap", "explosion", "mine"]
    /// Equipment an enemy can carry (§8.6).
    public static let equipmentIDs = ["amphi_tank", "anti_skid", "shield_of_moon", "memory_of_sea"]

    public static func makeWorld() -> WorldState {
        let arena = ArenaSpecification.universal
        var terrain = TerrainGrid(arena: arena)
        for x in 0..<arena.cellsWide {
            terrain[x, 0] = TerrainCell(kind: .steel)
            terrain[x, arena.cellsHigh - 1] = TerrainCell(kind: .steel)
        }
        for y in 0..<arena.cellsHigh {
            terrain[0, y] = TerrainCell(kind: .steel)
            terrain[arena.cellsWide - 1, y] = TerrainCell(kind: .steel)
        }
        func fill(_ kind: TerrainKind, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, mask: Int = 0b1111) {
            for y in y0...y1 { for x in x0...x1 { terrain[x, y] = TerrainCell(kind: kind, quadrantMask: mask) } }
        }
        // Top-left: brick corridors and every damaged-brick state.
        fill(.brick, 3, 2, 4, 9); fill(.brick, 7, 2, 8, 9); fill(.brick, 11, 2, 12, 5)
        fill(.brick, 5, 6, 6, 6)
        for (i, mask) in [0b0001, 0b0011, 0b0101, 0b0111, 0b1000, 0b1100, 0b1010, 0b1110].enumerated() {
            fill(.brick, 3 + i, 11, 3 + i, 11, mask: mask)
        }
        // Top-left, second row: white brick — the same wall at twice the
        // rounds (GAME_RULES §3.5), so both tiers can be compared side by side.
        fill(.whiteBrick, 3, 13, 4, 16); fill(.whiteBrick, 7, 13, 8, 16)
        // Top-middle: grey steel (only the AP shell breaks it, one round per
        // cell) and white steel (nothing breaks it).
        fill(.steel, 18, 2, 19, 3); fill(.steel, 24, 2, 25, 3); fill(.steel, 30, 2, 31, 3)
        fill(.whiteSteel, 36, 2, 37, 3)
        for (i, mask) in [0b0011, 0b1100, 0b0101, 0b1010].enumerated() {
            fill(.steel, 20 + 4 * i, 4, 20 + 4 * i, 4, mask: mask)
        }
        // Top-right: a water pool with a foliage shore.
        fill(.water, 42, 2, 50, 7)
        fill(.foliage, 40, 8, 52, 10)
        // Middle: the enemy parade ground (y 6 and 9 stay open), an ice rink
        // below it, brick pillars either side (the smoke test's central crop
        // needs brick and ground).
        fill(.ice, 20, 12, 35, 16)
        fill(.brick, 14, 12, 15, 17); fill(.brick, 40, 12, 41, 17)
        fill(.brick, 17, 14, 18, 14); fill(.brick, 37, 14, 38, 14)
        // Bottom-left: foliage cover with brick inside it.
        fill(.foliage, 3, 15, 12, 22)
        fill(.brick, 6, 18, 7, 19)
        // Bottom-right: a mixed fortress.
        fill(.steel, 44, 16, 45, 22); fill(.brick, 46, 16, 51, 17); fill(.brick, 50, 18, 51, 22)
        fill(.water, 47, 19, 48, 21)
        // Base with its brick U.
        fill(.brick, 26, 22, 29, 22); fill(.brick, 26, 23, 26, 24); fill(.brick, 29, 23, 29, 24)

        var world = WorldState(terrain: terrain, seed: seed)
        var player = PlayerState(playerID: .one)
        player.lives = playerLives
        world.addPlayer(player)
        let cell = SpatialUnits.subunitsPerCell
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: playerSpawnCell.x * cell, y: playerSpawnCell.y * cell), facing: .up)
        world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 27 * cell, y: 23 * cell),
                               durability: baseDurability, maxDurability: baseDurability)
        world.stage = StageState(spawnQueue: [], maxAliveEnemies: 40, enemyStartDelayTicks: 0,
                                 spawnPointsCells: enemySpawnCells, telegraphTicks: 45,
                                 playerRespawnCell: playerSpawnCell, dropTable: [], dropChancePercent: 0)
        // No enemies until the training panel adds them.
        world.withTanksInEntityOrder { $0.spawnProtectionTicks = 0 }
        return world
    }

    /// Spawns an enemy the way the director does (attributes, family weapon).
    @discardableResult
    public static func spawnEnemy(_ world: inout WorldState, archetype: String, at cellPos: Vec2i) -> Int {
        let cell = SpatialUnits.subunitsPerCell
        let attributes = EnemyArchetypes.attributes(for: archetype)
        let id = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: archetype,
                                 positionSubunits: Vec2i(x: cellPos.x * cell, y: cellPos.y * cell), facing: .down)
        world.withTank(entityID: id) {
            $0.armor = attributes.armor
            $0.maxArmor = attributes.armor
            $0.shieldHP = attributes.shieldHP
            $0.equipmentID = attributes.equipmentID
            $0.speedLevel = attributes.speedLevel
            $0.powerLevel = attributes.powerLevel
            $0.specialWeaponID = String(archetype.split(separator: "_").first ?? "normal")
            $0.spawnProtectionTicks = 30
        }
        return id
    }

    /// The nearest cell around `origin` whose 2×2 footprint (with the
    /// collision inset) touches neither blocking terrain, a tank nor the
    /// base; nil when none within the scan radius is free.
    public static func freeCell(in world: WorldState, near origin: Vec2i, maxRadius: Int = 6) -> Vec2i? {
        let cell = SpatialUnits.subunitsPerCell, footprint = SpatialUnits.standardTankFootprintSubunits
        let inset = MovementRuleset.provisional.collisionInsetSubunits
        for candidate in RingScan.cells(around: origin, maxRadius: maxRadius) {
            let p = Vec2i(x: candidate.x * cell, y: candidate.y * cell)
            let box = (minX: p.x + inset, minY: p.y + inset, maxX: p.x + footprint - inset, maxY: p.y + footprint - inset)
            if world.terrain.blocksTank(minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY) { continue }
            var blocked = false
            for tank in world.tanks {
                let t = tank.positionSubunits
                if box.minX < t.x + footprint && box.maxX > t.x && box.minY < t.y + footprint && box.maxY > t.y { blocked = true; break }
            }
            if let base = world.base, !blocked {
                let b = base.topLeftSubunits
                if box.minX < b.x + base.sizeSubunits && box.maxX > b.x && box.minY < b.y + base.sizeSubunits && box.maxY > b.y { blocked = true }
            }
            if !blocked { return candidate }
        }
        return nil
    }
}
