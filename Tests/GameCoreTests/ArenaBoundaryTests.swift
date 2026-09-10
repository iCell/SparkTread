import Testing
@testable import GameCore

/// R15-03: the arena boundary applies to the NOMINAL footprint. On an open
/// edge (no solid border) a tank driven outward stops flush with the
/// boundary instead of poking the collision inset past it and failing the
/// world invariants a tick later.
private let cell = SpatialUnits.subunitsPerCell
private let footprint = SpatialUnits.standardTankFootprintSubunits

private func openWorld(playerAt position: Vec2i, facing: Direction) -> WorldState {
    var world = WorldState(terrain: TerrainGrid(arena: .universal), seed: 3) // no border at all
    world.addPlayer(PlayerState(playerID: .one))
    world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                    positionSubunits: position, facing: facing)
    return world
}

private func hold(_ world: inout WorldState, _ direction: Direction?, ticks: Int) {
    for _ in 0..<ticks {
        Simulation.step(&world, commands: [PlayerCommand(
            playerID: .one, targetTick: world.tick, moveDirection: direction)])
    }
}

private func player(_ world: WorldState) -> TankState {
    world.tanks.first { $0.ownerPlayerID == .one }!
}

@Suite struct ArenaBoundaryTests {
    @Test(arguments: [Direction.left, .up, .right, .down])
    func aTankDrivenOutwardStopsFlushWithTheOpenEdge(direction: Direction) {
        let width = ArenaSpecification.universal.widthSubunits
        let height = ArenaSpecification.universal.heightSubunits
        let start: Vec2i = switch direction {
        case .left: Vec2i(x: 0, y: 4 * cell)
        case .up: Vec2i(x: 4 * cell, y: 0)
        case .right: Vec2i(x: width - footprint, y: 4 * cell)
        case .down: Vec2i(x: 4 * cell, y: height - footprint)
        }
        var world = openWorld(playerAt: start, facing: direction)
        #expect(WorldInvariants.violations(in: world).isEmpty)
        hold(&world, direction, ticks: 180) // prolonged outward input
        let p = player(world).positionSubunits
        #expect(p == start, "moved to \(p)")
        #expect(WorldInvariants.violations(in: world).isEmpty)
    }

    @Test func approachingTheEdgeFromInsideStopsExactlyOnIt() {
        var world = openWorld(playerAt: Vec2i(x: 3 * cell, y: 4 * cell), facing: .left)
        hold(&world, .left, ticks: 240)
        #expect(player(world).positionSubunits.x == 0)
        #expect(WorldInvariants.violations(in: world).isEmpty)
        // A turn along the edge keeps the footprint inside too.
        hold(&world, .up, ticks: 240)
        let p = player(world).positionSubunits
        #expect(p.x == 0 && p.y == 0)
        #expect(WorldInvariants.violations(in: world).isEmpty)
    }

    @Test func turnAssistanceNeverNudgesPastTheBoundary() {
        // Off-lane by a few subunits next to the right edge; the assist
        // window may snap toward the edge but never through it.
        let width = ArenaSpecification.universal.widthSubunits
        var world = openWorld(playerAt: Vec2i(x: width - footprint - 40, y: 4 * cell + 24), facing: .right)
        hold(&world, .right, ticks: 30)
        hold(&world, .down, ticks: 60)
        hold(&world, .right, ticks: 60)
        let p = player(world).positionSubunits
        #expect(p.x <= width - footprint && p.x >= 0)
        #expect(WorldInvariants.violations(in: world).isEmpty)
    }
}
