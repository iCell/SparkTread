import Testing
@testable import GameCore

/// ADR-0015: the enemy brain reads its behaviour from the stage's profile;
/// authored director phases fire once, in order, on the spawn count.
private func makeStageWorld(profile: EnemyBehaviorProfile = .standard, enemies: [String] = ["normal_a", "normal_a", "normal_a"],
                            phases: [DirectorPhase] = [], maxAlive: Int = 2, delay: Int = 0,
                            base: Int = 3) -> WorldState {
    var terrain = TerrainGrid(arena: .universal)
    let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
    for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
    for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
    var world = WorldState(terrain: terrain, seed: 21)
    world.addPlayer(PlayerState(playerID: .one))
    world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                    positionSubunits: Vec2i(x: 20 * 1024, y: 20 * 1024), facing: .up)
    world.withTanksInEntityOrder { $0.spawnProtectionTicks = 0 }
    world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 40 * 1024, y: 22 * 1024), durability: base)
    world.stage = StageState(
        spawnQueue: enemies, maxAliveEnemies: maxAlive, enemyStartDelayTicks: delay,
        spawnPointsCells: [Vec2i(x: 4, y: 1), Vec2i(x: 30, y: 1)],
        playerRespawnCell: Vec2i(x: 20, y: 20), dropTable: [], dropChancePercent: 0,
        enemyBehavior: profile, directorPhases: phases)
    return world
}

private func tick(_ world: inout WorldState, _ n: Int, events: inout [DomainEvent]) {
    for _ in 0..<n { events += Simulation.step(&world, commands: [PlayerCommand(playerID: .one, targetTick: world.tick)]) }
}

@Suite struct EnemyBehaviorProfileTests {
    @Test func theStandardProfileIsTheAuthoredBehaviourAndValidates() {
        let p = EnemyBehaviorProfile.standard
        #expect(p.decisionIntervalTicks == 30 && p.baseFocusPercent == 100 && p.wanderPercent == 10
                && p.fireWindowPercent == 100 && p.minePlacePercent == 20 && p.courseCommitPercent == 55)
        #expect(p.validationIssues().isEmpty)
        var bad = p
        bad.decisionIntervalTicks = 0; bad.wanderPercent = 101; bad.fireWindowPercent = -1
        #expect(bad.validationIssues().count == 3)
        var world = makeStageWorld(profile: bad)
        #expect(WorldInvariants.violations(in: world).contains { $0.contains("enemy behaviour") })
        world.stage?.enemyBehavior = .standard
        #expect(WorldInvariants.violations(in: world).isEmpty)
    }

    @Test func theProfileIsAuthoritativeStateWithACompatibleDecoder() throws {
        var veteran = EnemyBehaviorProfile.standard
        veteran.decisionIntervalTicks = 20
        let a = makeStageWorld(), b = makeStageWorld(profile: veteran)
        #expect(a.checksum() != b.checksum())
        #expect(a.stage?.directorPhasesFired == 0 && a.stage?.directorSpawned == 0)
    }

    @Test func aClosedFireWindowNeverFiresAndAWideOneFiresMore() {
        func shots(_ profile: EnemyBehaviorProfile) -> Int {
            // One enemy directly above the player, facing it: aligned from the start.
            var world = makeStageWorld(profile: profile, enemies: [], maxAlive: 1)
            world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                            positionSubunits: Vec2i(x: 20 * 1024, y: 8 * 1024), facing: .down)
            world.withTanksInEntityOrder { $0.spawnProtectionTicks = 0 }
            var events: [DomainEvent] = []
            tick(&world, 240, events: &events)
            return events.filter { if case .weaponFired(_, nil, _, _, _, _) = $0 { true } else { false } }.count
        }
        var silent = EnemyBehaviorProfile.standard
        silent.fireWindowPercent = 0
        var eager = EnemyBehaviorProfile.standard
        eager.fireWindowPercent = 400
        #expect(shots(silent) == 0)
        #expect(shots(.standard) > 0)
        #expect(shots(eager) > shots(.standard))
    }

    @Test func theDecisionIntervalPacesMovementDecisions() {
        func changes(_ interval: Int) -> Int {
            var profile = EnemyBehaviorProfile.standard
            profile.decisionIntervalTicks = interval
            profile.wanderPercent = 100 // every decision is a steer: intents change often
            var world = makeStageWorld(profile: profile, enemies: ["normal_a"], maxAlive: 1)
            var events: [DomainEvent] = []
            tick(&world, 100, events: &events) // telegraph and spawn
            var intents: [Direction?] = []
            for _ in 0..<600 {
                tick(&world, 1, events: &events)
                intents.append(world.tanks.first { $0.teamID != 1 }?.movementIntent)
            }
            return zip(intents, intents.dropFirst()).filter { $0 != $1 }.count
        }
        #expect(changes(10) > changes(60))
    }
}

@Suite struct DirectorPhaseTests {
    @Test func phasesFireOnceInOrderPushReinforcementsRaiseTheCapAndRepairTheBase() {
        let phases = [
            DirectorPhase(id: "elite", afterSpawned: 2, reinforcements: ["ap_c", "mine_c"], maxAliveEnemies: 4, repairsBase: true),
            DirectorPhase(id: "late", afterSpawned: 3, reinforcements: ["rapid_a"]),
        ]
        var world = makeStageWorld(enemies: ["normal_a", "normal_a", "normal_a", "normal_a"], phases: phases,
                                   maxAlive: 2, base: 1)
        world.base?.maxDurability = 3
        var events: [DomainEvent] = []
        tick(&world, 1, events: &events) // two telegraphs scheduled (cap 2): spawned count 2
        #expect(world.stage?.directorSpawned == 2 && world.stage?.directorPhasesFired == 0)
        tick(&world, 1, events: &events) // the phase fires at the next director pass
        let stage = world.stage!
        #expect(stage.directorPhasesFired == 1)
        // The reinforcements jumped the queue and, with the cap raised in the
        // same pass, were scheduled at once: the normals wait behind them.
        #expect(world.spawnTelegraphs.map(\.archetypeID) == ["normal_a", "normal_a", "ap_c", "mine_c"])
        #expect(stage.spawnQueue == ["normal_a", "normal_a"] && stage.directorSpawned == 4)
        #expect(stage.maxAliveEnemies == 4)
        #expect(world.base?.durability == 3)
        #expect(events.contains(.directorPhaseStarted(id: "elite", reinforcements: 2)))
        #expect(events.contains(.baseRepaired(restored: 2)))
        // Spawned 4 ≥ 3: the second phase fires on the next pass.
        tick(&world, 1, events: &events)
        #expect(world.stage?.directorPhasesFired == 2)
        #expect(world.stage?.spawnQueue.first == "rapid_a")
        tick(&world, 600, events: &events)
        #expect(world.stage?.directorPhasesFired == 2) // never again
        #expect(events.filter { if case .directorPhaseStarted = $0 { true } else { false } }.count == 2)
    }

    @Test func aRepairOfAFullBaseEmitsNothingAndADestroyedBaseIsNotRevived() {
        var world = makeStageWorld(enemies: ["normal_a", "normal_a"],
                                   phases: [DirectorPhase(id: "r", afterSpawned: 1, repairsBase: true)], maxAlive: 2)
        var events: [DomainEvent] = []
        tick(&world, 2, events: &events)
        #expect(!events.contains { if case .baseRepaired = $0 { true } else { false } })
        var lost = makeStageWorld(enemies: ["normal_a", "normal_a"],
                                  phases: [DirectorPhase(id: "r", afterSpawned: 1, repairsBase: true)], maxAlive: 2, base: 0)
        var lostEvents: [DomainEvent] = []
        tick(&lost, 2, events: &lostEvents)
        #expect(lost.base?.durability == 0 && lost.stage?.phase == .lost)
    }

    @Test func carriedPickupsStayPairedWhenReinforcementsJumpTheQueue() {
        var world = makeStageWorld(enemies: ["normal_a", "normal_b", "normal_c"],
                                   phases: [DirectorPhase(id: "e", afterSpawned: 1, reinforcements: ["ap_a"])], maxAlive: 1)
        world.stage?.carriedPickupQueue = [nil, "power_up", nil]
        var events: [DomainEvent] = []
        tick(&world, 2, events: &events)
        let stage = world.stage!
        #expect(stage.spawnQueue == ["ap_a", "normal_b", "normal_c"])
        #expect(stage.carriedPickupQueue == [nil, "power_up", nil])
        #expect(WorldInvariants.violations(in: world).isEmpty)
    }
}
