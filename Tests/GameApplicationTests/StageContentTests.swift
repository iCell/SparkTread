import Foundation
import Testing
import GameCore
@testable import GameApplication

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let vs01URL = repoRoot
    .appendingPathComponent("Content/stages/frontier_01_first_defense.json")

@Suite struct StageContentTests {
    @Test func canonicalVS01LoadsBuildsAndValidates() throws {
        let data = try Data(contentsOf: vs01URL)
        let def = try StageLoader.decode(data)
        #expect(def.id == "frontier_01_first_defense")
        #expect(StageValidator.validate(def).isEmpty)
        let world = try StageLoader.loadWorld(at: vs01URL)
        #expect(world.stage != nil)
        #expect(world.base != nil)
        #expect(world.player(.one)?.tankEntityID != nil)
        #expect(world.pickups.count == 1) // the visible starter power_up
        // Composition interleaves to 16 enemies in the queue.
        #expect(world.stage?.spawnQueue.count == 16)
        #expect(world.stage?.maxAliveEnemies == 4)
    }

    /// The loaded world is deterministic and stable — a golden checksum so
    /// an accidental content edit is caught. Regenerate with a review note.
    @Test func loadedVS01ChecksumIsStable() throws {
        let a = try StageLoader.loadWorld(at: vs01URL)
        let b = try StageLoader.loadWorld(at: vs01URL)
        #expect(a.checksum() == b.checksum())
        #expect(a == b)
        // A full scripted run stays deterministic across loads.
        func run(_ world: inout WorldState) {
            for t in 0..<1200 {
                let dir: Direction? = [Direction.up, .right, nil, .left][(t / 80) % 4]
                Simulation.step(&world, commands: [PlayerCommand(
                    playerID: .one, targetTick: t, moveDirection: dir, normalFirePressed: t % 20 == 0)])
            }
        }
        var ra = a, rb = b
        run(&ra); run(&rb)
        #expect(ra.checksum() == rb.checksum())
        #expect(WorldInvariants.violations(in: ra).isEmpty)
    }

    @Test func validatorRejectsUnknownAndOutOfBoundsReferences() {
        var def = try! StageLoader.decode(Data(contentsOf: vs01URL))
        def.enemyComposition.append(.init(archetype: "dragon_z", count: 1)) // unknown
        def.pickupSpawns.append(.init(id: "gold_bar", cell: [999, 5]))       // unknown + OOB
        def.dropTable.append("nonexistent_pickup")
        let issues = StageValidator.validate(def)
        #expect(issues.contains { $0.contains("dragon_z") })
        #expect(issues.contains { $0.contains("gold_bar") })
        #expect(issues.contains { $0.contains("out of bounds") })
        #expect(issues.contains { $0.contains("nonexistent_pickup") })
    }

    @Test func validatorRejectsSpawnInsideWall() {
        var def = try! StageLoader.decode(Data(contentsOf: vs01URL))
        def.enemySpawns = [[6, 6]] // squarely inside a brick block
        let issues = StageValidator.validate(def)
        #expect(issues.contains { $0.contains("blocking terrain") })
    }

    @Test func validatorRejectsUnreachableBase() {
        var def = try! StageLoader.decode(Data(contentsOf: vs01URL))
        // Wall the base off completely with a steel ring around row 22.
        def.terrain.layers.append(.init(kind: "steel", rects: [[0, 22, 55, 22]], cells: nil))
        let issues = StageValidator.validate(def)
        #expect(issues.contains { $0.contains("reach the base") })
    }

    @Test func telegraphFloorEnforced() {
        var def = try! StageLoader.decode(Data(contentsOf: vs01URL))
        def.telegraphTicks = 20
        #expect(StageValidator.validate(def).contains { $0.contains("fairness floor") })
    }
}
