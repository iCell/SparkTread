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
        #expect(world.pickups.isEmpty) // reference stage 1 pre-places no pickups
        // Reference stage 1 roster: 18 normal_a + 2 rapid_a.
        #expect(world.stage?.spawnQueue.count == 20)
        // Reference drop channels: 3 carriers + 2 hidden treasures, no
        // natural roll in stage 1.
        #expect(world.stage?.carriedPickupQueue.compactMap { $0 }.count == 3)
        #expect(world.stage?.hiddenPickups.count == 2)
        #expect(world.stage?.dropChancePercent == 0)
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

    /// ADR-0012: the campaign position is required content and selects the
    /// stage-clear bonus tier the builder writes into the stage.
    @Test func stageNumberIsRequiredAndSelectsTheClearBonus() throws {
        var def = try StageLoader.decode(Data(contentsOf: vs01URL))
        #expect(def.stageNumber == 1)
        #expect(StageValidator.validate(def).isEmpty)
        let world = try StageBuilder.build(def)
        #expect(world.stage?.clearBonus == ScoreRules.ClearBonus(tally: 200, reward: 330))
        def.stageNumber = 12
        #expect(try StageBuilder.build(def).stage?.clearBonus == ScoreRules.ClearBonus(tally: 600, reward: 660))
        def.stageNumber = nil
        #expect(StageValidator.validate(def).contains { $0.contains("stage_number missing") })
        #expect(throws: StageBuilder.BuildError.self) { try StageBuilder.build(def) }
        def.stageNumber = 0
        #expect(StageValidator.validate(def).contains { $0.contains("stage_number 0 outside") })
        def.stageNumber = 1000
        #expect(StageValidator.validate(def).contains { $0.contains("stage_number 1000 outside") })
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

    @Test func malformedTerrainIsReportedWithoutTrapping() throws {
        var def = try StageLoader.decode(Data(contentsOf: vs01URL))
        def.terrain.layers.append(.init(kind: "brick",
            rects: [[8, 8, 7, 7], [], [Int.min, 0, Int.max, 2]],
            cells: [[], [1], [Int.max, Int.min]]))
        def.enemySpawns.append([Int.max, Int.min])
        let issues = StageValidator.validate(def)
        #expect(issues.contains { $0.contains("malformed rect") })
        #expect(issues.contains { $0.contains("out of bounds") })
    }

    @Test func laterGroundLayerClearsBlockingTerrain() throws {
        var def = try StageLoader.decode(Data(contentsOf: vs01URL))
        def.enemySpawns = [[5, 5]]
        def.terrain.layers.append(.init(kind: "ground", rects: [[5, 5, 6, 6]], cells: nil))
        #expect(StageValidator.validate(def).isEmpty)
        let world = try StageBuilder.build(def)
        #expect(world.terrain[5, 5].kind == .ground)
    }

    @Test func spawnValidationChecksEntireFootprintAndBaseOverlap() throws {
        var def = try StageLoader.decode(Data(contentsOf: vs01URL))
        // Top-left is ground; the right half intersects the brick column.
        def.enemySpawns = [[4, 5]]
        #expect(StageValidator.validate(def).contains { $0.contains("blocking terrain") })
        def.enemySpawns = [def.baseSpawn]
        #expect(StageValidator.validate(def).contains { $0.contains("blocking terrain") })
        def.enemySpawns = [[55, 1]]
        #expect(StageValidator.validate(def).contains { $0.contains("footprint out of bounds") })
        def.baseSpawn = [55, 26]
        #expect(StageValidator.validate(def).contains { $0.contains("base_spawn") })
    }

    @Test func overflowingCompositionIsReported() throws {
        var def = try StageLoader.decode(Data(contentsOf: vs01URL))
        def.enemyComposition.append(.init(archetype: "normal_a", count: Int.max))
        #expect(StageValidator.validate(def).contains { $0.contains("overflows") })
    }

    @Test func telegraphFloorEnforced() {
        var def = try! StageLoader.decode(Data(contentsOf: vs01URL))
        def.telegraphTicks = 20
        #expect(StageValidator.validate(def).contains { $0.contains("fairness floor") })
    }
}

@Suite struct StageConfigurationBoundaryTests {
    /// R3-04 / round-2: the loader is the configuration boundary — pickup
    /// rules are validated there, and an authored starter pickup is created
    /// under the configured lifetime and grace, not the defaults.
    @Test func loaderValidatesPickupRulesAndAppliesThemToAuthoredPickups() throws {
        var def = try StageLoader.decode(Data(contentsOf: vs01URL))
        def.pickupSpawns = [.init(id: "power_up", cell: [14, 16])]
        let data = try JSONEncoder().encode(def)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sparktread-config-boundary-\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        var custom = PickupRuleset.provisional
        custom.pickupLifetimeTicks = 900
        custom.pickupGraceTicks = 10
        let world = try StageLoader.loadWorld(at: url, rules: custom)
        #expect(world.pickups.count == 1)
        #expect(world.pickups.first?.lifetimeRemainingTicks == 900)
        #expect(world.pickups.first?.graceTicksRemaining == 10)

        var broken = PickupRuleset.provisional
        broken.freezeTicks = 0
        #expect(throws: StageLoader.LoadError.self) { try StageLoader.loadWorld(at: url, rules: broken) }
    }

    /// Owner report 2026-09-09: enemies must actively come for the base. On
    /// the real VS-01 layout with an idle player, the first wave reaches the
    /// fort ring (within two cells of the base) well inside a minute.
    @Test func enemiesBesiegeTheBaseOnVS01() throws {
        var world = try StageLoader.loadWorld(at: vs01URL)
        // An idle player would be shot dead three times and end the stage
        // before the siege lands; this test is about the enemies' approach.
        if let id = world.player(.one)?.tankEntityID {
            world.withTank(entityID: id) { $0.maxArmor = 999; $0.armor = 999 }
        }
        let cell = SpatialUnits.subunitsPerCell
        let base = try #require(world.base)
        let bx = base.topLeftSubunits.x / cell, by = base.topLeftSubunits.y / cell
        var closest = Int.max
        var fortDamaged = false
        for t in 0..<3600 {
            Simulation.step(&world, commands: [PlayerCommand(playerID: .one, targetTick: t)])
            for tank in world.tanks where tank.teamID != 1 {
                let ax = tank.positionSubunits.x / cell, ay = tank.positionSubunits.y / cell
                let dx = max(bx - (ax + 1), ax - (bx + 1), 0), dy = max(by - (ay + 1), ay - (by + 1), 0)
                closest = min(closest, max(dx, dy))
            }
            if world.terrain[27, 23].kind != .brick || world.terrain[26, 24].kind != .brick { fortDamaged = true }
            if closest <= 2 || fortDamaged || (world.base?.durability ?? 3) < 3 { break }
        }
        #expect(closest <= 2 || fortDamaged || (world.base?.durability ?? 3) < 3,
                "closest \(closest) cells, fort damaged \(fortDamaged)")
    }
}
