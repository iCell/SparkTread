import GameCore

/// VS-01 "First Defense" (§11.3): teaches movement, normal fire, base
/// defense, brick destruction, and pickups. Primarily normal and rapid
/// enemies, a safe initial base wall, one visible starter pickup, and two
/// meaningful routes. Authored here as a code fixture; migration to
/// Content/stages JSON follows the content pipeline milestone.
public enum VS01Stage {
    public static let stageID = "frontier_01_first_defense"
    public static let seed: UInt64 = 0x5653_3031_4649_5253 // stable stage seed

    public static func makeWorld() -> WorldState {
        let arena = ArenaSpecification.universal
        var terrain = TerrainGrid(arena: arena)
        let cell = SpatialUnits.subunitsPerCell

        for x in 0..<arena.cellsWide {
            terrain[x, 0] = TerrainCell(kind: .steel)
            terrain[x, arena.cellsHigh - 1] = TerrainCell(kind: .steel)
        }
        for y in 0..<arena.cellsHigh {
            terrain[0, y] = TerrainCell(kind: .steel)
            terrain[arena.cellsWide - 1, y] = TerrainCell(kind: .steel)
        }

        func brick(_ x: Int, _ y: Int) { terrain[x, y] = TerrainCell(kind: .brick) }
        func brickRect(x: ClosedRange<Int>, y: ClosedRange<Int>) {
            for cy in y { for cx in x { brick(cx, cy) } }
        }

        // Mid-field cover: staggered brick blocks leaving two clear lanes
        // (left x≈10–13 and right x≈42–45) between enemy and player areas.
        brickRect(x: 6...9, y: 6...7)
        brickRect(x: 16...21, y: 6...7)
        brickRect(x: 28...33, y: 6...7)
        brickRect(x: 40...43, y: 8...9)
        brickRect(x: 48...51, y: 6...7)
        brickRect(x: 10...13, y: 12...13)
        brickRect(x: 22...27, y: 12...13)
        brickRect(x: 36...39, y: 14...15)
        brickRect(x: 46...49, y: 12...13)
        brickRect(x: 4...7, y: 17...18)
        brickRect(x: 16...19, y: 17...18)
        brickRect(x: 30...33, y: 19...20)

        // Base flush against the bottom border wall (reference-heritage),
        // with the classic three-sided brick ring: base cells (27–28, 24–25).
        for y in 23...25 { brick(26, y); brick(29, y) }
        brick(27, 23); brick(28, 23)

        // A small water pool and ice patch to seed terrain tactics.
        for y in 9...11 { for x in 12...15 { terrain[x, y] = TerrainCell(kind: .water) } }
        for y in 19...21 { for x in 42...45 { terrain[x, y] = TerrainCell(kind: .ice) } }

        var world = WorldState(terrain: terrain, seed: seed)
        world.addPlayer(PlayerState(playerID: .one))
        // No second local player or join path is exposed (§6.4).

        let playerSpawnCell = Vec2i(x: 21, y: 24)
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: playerSpawnCell.x * cell,
                                                y: playerSpawnCell.y * cell),
                        facing: .up)
        world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 27 * cell, y: 24 * cell))

        // Finite composition (VS-01: primarily normal and rapid).
        let composition: [(String, Int)] = [
            ("normal_a", 5), ("rapid_a", 3), ("normal_b", 4), ("rapid_b", 2),
        ]
        var queue: [String] = []
        // Interleave archetypes deterministically for varied pressure.
        var pools = composition
        while pools.contains(where: { $0.1 > 0 }) {
            for i in pools.indices where pools[i].1 > 0 {
                queue.append(pools[i].0)
                pools[i].1 -= 1
            }
        }

        world.stage = StageState(
            spawnQueue: queue,
            maxAliveEnemies: 4,
            spawnPointsCells: [Vec2i(x: 4, y: 1), Vec2i(x: 27, y: 1), Vec2i(x: 50, y: 1)],
            playerRespawnCell: playerSpawnCell,
            dropTable: ["speed_up", "power_up", "armor_up", "ammo_crate",
                        "base_shield", "invincibility", "rapid_weapon", "bomb"])

        // One visible starter pickup (VS-01 requirement).
        var events: [DomainEvent] = []
        world.spawnStagePickup("power_up", nearCell: Vec2i(x: 14, y: 16), events: &events)
        return world
    }
}
