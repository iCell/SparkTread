import Foundation
import Testing
@testable import GameCore

private func scriptedDirection(_ tick: Int) -> Direction? {
    // Deterministic pseudo-script: mixes holds, releases, and turns.
    switch (tick / 37) % 6 {
    case 0: .right
    case 1: .down
    case 2: tick % 5 == 0 ? nil : .left
    case 3: .up
    case 4: nil
    default: .right
    }
}

private func makeLabLikeWorld(seed: UInt64 = 7) -> WorldState {
    var terrain = TerrainGrid(arena: .universal)
    let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
    for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
    for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
    for y in 5...20 { terrain[14, y] = TerrainCell(kind: .brick); terrain[15, y] = TerrainCell(kind: .brick) }
    for x in 20...34 { terrain[x, 13] = TerrainCell(kind: .brick); terrain[x, 14] = TerrainCell(kind: .brick) }
    var world = WorldState(terrain: terrain, seed: seed)
    world.addPlayer(PlayerState(playerID: .one))
    world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                    positionSubunits: Vec2i(x: 2048, y: 2048), facing: .down)
    return world
}

private func run(_ world: inout WorldState, ticks: Int) {
    for _ in 0..<ticks {
        Simulation.step(&world, commands: [PlayerCommand(
            playerID: .one, targetTick: world.tick,
            moveDirection: scriptedDirection(world.tick))])
    }
}

@Suite struct DeterminismTests {
    /// M1 exit criterion: identical replay produces identical checksums.
    @Test func identicalScriptsProduceIdenticalChecksums() {
        var a = makeLabLikeWorld(), b = makeLabLikeWorld()
        for _ in 0..<20 {
            run(&a, ticks: 60)
            run(&b, ticks: 60)
            #expect(a.checksum() == b.checksum(), "diverged at tick \(a.tick)")
        }
        #expect(a == b)
    }

    /// ADR-0003 required test: run N → serialize → restore → run M equals an
    /// uninterrupted N+M run, checksum for checksum.
    @Test func serializeRestoreResumeMatchesUninterruptedRun() throws {
        var interrupted = makeLabLikeWorld()
        run(&interrupted, ticks: 500)

        let data = try JSONEncoder().encode(interrupted)
        var restored = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(restored == interrupted)
        #expect(restored.checksum() == interrupted.checksum())

        var uninterrupted = makeLabLikeWorld()
        run(&uninterrupted, ticks: 500)
        run(&restored, ticks: 700)
        run(&uninterrupted, ticks: 700)
        #expect(restored.checksum() == uninterrupted.checksum())
        #expect(restored == uninterrupted)
    }

    /// §6.4 / §18.1: a core-only two-PlayerID fixture accepts independent
    /// command streams and produces stable checksums — data-model readiness
    /// without any shipped multiplayer path.
    @Test func twoPlayerFixtureProducesStableChecksums() {
        func makeTwoPlayerWorld() -> WorldState {
            var world = makeLabLikeWorld()
            world.addPlayer(PlayerState(playerID: .two))
            world.spawnTank(teamID: 1, ownerPlayerID: .two, archetypeID: "player",
                            positionSubunits: Vec2i(x: 43 * 1024, y: 2048), facing: .down)
            return world
        }
        func run(_ world: inout WorldState) {
            for _ in 0..<600 {
                let t = world.tick
                Simulation.step(&world, commands: [
                    PlayerCommand(playerID: .one, targetTick: t, moveDirection: scriptedDirection(t)),
                    PlayerCommand(playerID: .two, targetTick: t, moveDirection: scriptedDirection(t + 191)),
                ])
            }
        }
        var a = makeTwoPlayerWorld(), b = makeTwoPlayerWorld()
        run(&a)
        run(&b)
        #expect(a.checksum() == b.checksum())
        #expect(a.tanks.count == 2)
        #expect(Set(a.tanks.map(\.entityID)).count == 2)
    }

    /// Commands addressed to the wrong tick or an unknown player are neutral.
    @Test func staleAndForeignCommandsAreIgnored() {
        var world = makeLabLikeWorld()
        Simulation.step(&world, commands: [
            PlayerCommand(playerID: .one, targetTick: 99, moveDirection: .right),
            PlayerCommand(playerID: PlayerID(9), targetTick: 0, moveDirection: .right),
        ])
        #expect(world.tanks[0].positionSubunits == Vec2i(x: 2048, y: 2048))
        #expect(world.tanks[0].movementIntent == nil)
    }
}

@Suite struct SoakTests {
    /// M1 exit criterion: a 30-minute (108,000-tick) soak shows no positional
    /// drift — the world stays valid and two identical runs stay identical.
    @Test func thirtyMinuteSoakHasNoDriftAndStaysInBounds() {
        var a = makeLabLikeWorld(), b = makeLabLikeWorld()
        let arena = a.arena
        for block in 0..<108 {
            run(&a, ticks: 1000)
            run(&b, ticks: 1000)
            let p = a.tanks[0].positionSubunits
            #expect(p.x >= 0 && p.y >= 0
                    && p.x + 2048 <= arena.widthSubunits
                    && p.y + 2048 <= arena.heightSubunits,
                    "out of bounds at block \(block): \(p)")
            #expect(a.tanks[0].movementAccumulator < MovementRuleset.accumulatorUnitsPerSubunit)
            #expect(WorldInvariants.violations(in: a).isEmpty,
                    "invariants at block \(block): \(WorldInvariants.violations(in: a))")
            #expect(a.checksum() == b.checksum(), "drift at block \(block)")
        }
        #expect(a.tick == 108_000)
    }
}
