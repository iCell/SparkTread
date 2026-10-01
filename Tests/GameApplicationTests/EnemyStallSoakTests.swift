import Foundation
import Testing
import GameCore
@testable import GameApplication

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// Owner-reported stall (2026-09-16 screenshot): enemies wedged against a
/// wall or another tank stand still indefinitely. An enemy that neither
/// moves nor fires for a whole window is a stall — standing to dig a wall
/// is legitimate only while the shots actually come.
@Suite struct EnemyStallSoakTests {
    @Test(arguments: [
        "frontier_01_first_defense",
        "frontier_02_hidden_in_grass",
        "frontier_03_desert_stairs",
    ])
    func enemiesNeverStallForFifteenSeconds(stageID: String) throws {
        let url = repoRoot.appendingPathComponent("Content/stages/\(stageID).json")
        var world = try StageLoader.loadWorld(at: url)
        // Keep the objective alive for the whole soak: the base and the
        // idle player must not end the stage under sustained AI fire.
        world.base?.durability = 99
        world.base?.maxDurability = 99
        world.withPlayer(.one) { $0.lives = 99 }

        let stallWindow = 900 // 15 s without moving or firing
        var stationarySince: [Int: Int] = [:]
        var lastPosition: [Int: Vec2i] = [:]
        var stalls: [String] = []
        for _ in 0..<9000 {
            let events = Simulation.step(&world, commands: [])
            guard world.stage?.phase == .playing else { break }
            var fired = Set<Int>()
            for case .weaponFired(let id, _, _, _, _, _) in events { fired.insert(id) }
            for tank in world.tanks where tank.ownerPlayerID == nil && tank.armor > 0 {
                guard tank.statusEffects["frozen"] == nil else { continue }
                let moved = lastPosition[tank.entityID] != tank.positionSubunits
                lastPosition[tank.entityID] = tank.positionSubunits
                if moved || fired.contains(tank.entityID) {
                    stationarySince[tank.entityID] = world.tick
                    continue
                }
                let since = stationarySince[tank.entityID, default: world.tick]
                stationarySince[tank.entityID] = since
                if world.tick - since == stallWindow {
                    let cell = SpatialUnits.subunitsPerCell
                    stalls.append("""
                        \(stageID) tick \(world.tick): enemy \(tank.entityID) \
                        (\(tank.archetypeID)) stalled at cell \
                        (\(tank.positionSubunits.x / cell),\(tank.positionSubunits.y / cell)) \
                        subunits \(tank.positionSubunits) facing \(tank.facing) \
                        intent \(String(describing: tank.movementIntent))
                        """)
                }
            }
        }
        #expect(stalls.isEmpty, Comment(rawValue: stalls.joined(separator: "\n")))
    }
}
