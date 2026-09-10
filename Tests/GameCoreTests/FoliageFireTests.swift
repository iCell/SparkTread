import Foundation
import Testing
@testable import GameCore

/// ADR-0017 (owner rule): a flame on foliage spreads to the neighbouring
/// foliage after the spread delay and burns the foliage away when it
/// goes out.
private let cell = SpatialUnits.subunitsPerCell

private func makeWorld(foliage: [(Int, Int)]) -> WorldState {
    var terrain = TerrainGrid(arena: .universal)
    let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
    for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
    for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
    for (x, y) in foliage { terrain[x, y] = TerrainCell(kind: .foliage) }
    var world = WorldState(terrain: terrain, seed: 6)
    world.addPlayer(PlayerState(playerID: .one))
    return world
}

/// A flame patch placed directly (as the fire weapon does), with the spread
/// tick the weapon would give it.
private func placeFlame(_ world: inout WorldState, cellX: Int, cellY: Int, lifetime: Int = 120,
                        weapons: WeaponRuleset = .provisional) -> Int {
    let id = world.claimEntityID()
    world.fireHazards.append(FireHazardState(
        entityID: id, ownerEntityID: -1, ownerPlayerID: .one, teamID: 1, filter: .enemyOnly,
        positionSubunits: Vec2i(x: cellX * cell + cell / 2, y: cellY * cell + cell / 2),
        lifetimeRemainingTicks: lifetime, damagePerTouch: 1,
        spreadsAtTicks: Combat.foliageSpreadTick(world, cellX: cellX, cellY: cellY, lifetime: lifetime, weapons: weapons)))
    return id
}

private func tick(_ world: inout WorldState, _ n: Int, weapons: WeaponRuleset = .provisional) -> [DomainEvent] {
    var events: [DomainEvent] = []
    for _ in 0..<n { events += Simulation.step(&world, commands: [], weapons: weapons) }
    return events
}

private func flameCells(_ world: WorldState) -> Set<[Int]> {
    Set(world.fireHazards.map { [$0.positionSubunits.x / cell, $0.positionSubunits.y / cell] })
}

@Suite struct FoliageFireTests {
    @Test func aFlameOnFoliageSpreadsToItsFoliageNeighboursAfterTheDelayAndOnward() {
        // A plus of foliage around (10,10) plus a far cell that is not adjacent.
        var world = makeWorld(foliage: [(10, 10), (9, 10), (11, 10), (10, 9), (10, 11), (12, 10), (20, 20)])
        let delay = WeaponRuleset.provisional.foliageSpreadDelayTicks
        let root = placeFlame(&world, cellX: 10, cellY: 10, lifetime: 120)
        #expect(world.fireHazards[0].spreadsAtTicks == 120 - delay)
        _ = tick(&world, delay - 1)
        #expect(world.fireHazards.count == 1)
        _ = tick(&world, 1) // the spread tick
        #expect(flameCells(world) == [[10, 10], [9, 10], [11, 10], [10, 9], [10, 11]])
        #expect(world.fireHazards.first { $0.entityID == root }?.spreadsAtTicks == nil) // once
        let children = world.fireHazards.filter { $0.entityID != root }
        #expect(children.allSatisfy { $0.ownerEntityID == -1 && $0.ownerPlayerID == .one && $0.teamID == 1
            && $0.filter == .enemyOnly && $0.lifetimeRemainingTicks == 120 && $0.spreadsAtTicks == 120 - delay })
        #expect(WorldInvariants.violations(in: world).isEmpty)
        // The children spread on: (12,10) catches from (11,10); (20,20) never.
        _ = tick(&world, delay)
        #expect(flameCells(world).contains([12, 10]) && !flameCells(world).contains([20, 20]))
        #expect(world.fireHazards.count == 6) // no duplicates on already-burning cells
    }

    @Test func groundAndWaterNeighboursDoNotCatchAndBurnedFoliageBecomesGround() {
        var world = makeWorld(foliage: [(10, 10), (11, 10)])
        world.terrain[9, 10] = TerrainCell(kind: .water)
        _ = placeFlame(&world, cellX: 10, cellY: 10, lifetime: 60)
        let events = tick(&world, 61)
        // Only the foliage neighbour caught; the root went out and its cell is ground now.
        #expect(world.terrain[10, 10].kind == .ground && world.terrain[9, 10].kind == .water)
        #expect(events.contains(.terrainChanged(cellX: 10, cellY: 10, quadrantMask: 0)))
        #expect(flameCells(world) == [[11, 10]])
        _ = tick(&world, 60)
        #expect(world.terrain[11, 10].kind == .ground && world.fireHazards.isEmpty)
    }

    @Test func theRuleIsDataAndSurvivesSerialization() throws {
        var off = WeaponRuleset.provisional
        off.foliageSpreadDelayTicks = 0
        off.foliageBurnsAway = false
        var world = makeWorld(foliage: [(10, 10), (11, 10)])
        _ = placeFlame(&world, cellX: 10, cellY: 10, lifetime: 40, weapons: off)
        #expect(world.fireHazards[0].spreadsAtTicks == nil)
        _ = tick(&world, 41, weapons: off)
        #expect(world.fireHazards.isEmpty && world.terrain[10, 10].kind == .foliage && world.terrain[11, 10].kind == .foliage)
        var bad = WeaponRuleset.provisional
        bad.foliageSpreadDelayTicks = -1
        #expect(bad.validationIssues().contains { $0.contains("foliage_spread_delay") })
        // A flame with its spread pending round-trips and keeps burning identically.
        var a = makeWorld(foliage: [(10, 10), (11, 10), (10, 11)])
        _ = placeFlame(&a, cellX: 10, cellY: 10)
        _ = tick(&a, 5)
        var b = try JSONDecoder().decode(WorldState.self, from: JSONEncoder().encode(a))
        #expect(b == a && b.checksum() == a.checksum())
        _ = tick(&a, 200); _ = tick(&b, 200)
        #expect(a.checksum() == b.checksum() && a.terrain[11, 10].kind == .ground)
    }

    @Test func theFireWeaponIgnitesFoliageAndTheShooterIsNotChargedForTheSpread() {
        // Player just below a foliage patch, facing up: every patch of the
        // volley (three cells ahead, two columns) lands on foliage.
        var world = makeWorld(foliage: (8...14).flatMap { x in (4...9).map { y in (x, y) } })
        let player = world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                                     positionSubunits: Vec2i(x: 10 * cell, y: 10 * cell), facing: .up)
        world.withTank(entityID: player) { $0.specialWeaponID = "fire"; $0.spawnProtectionTicks = 0 }
        world.withPlayer(.one) { $0.specialAmmoByWeapon["fire"] = 50 }
        _ = Simulation.step(&world, commands: [PlayerCommand(playerID: .one, targetTick: world.tick, specialFirePressed: true)])
        let volley = world.fireHazards.count
        #expect(volley > 0 && world.fireHazards.allSatisfy { $0.spreadsAtTicks != nil })
        let charged = world.tank(entityID: player)?.activeProjectileCounts["fire"] ?? 0
        #expect(charged == volley)
        _ = tick(&world, WeaponRuleset.provisional.foliageSpreadDelayTicks + 1)
        #expect(world.fireHazards.count > volley)
        #expect((world.tank(entityID: player)?.activeProjectileCounts["fire"] ?? 0) == volley) // spread is free
    }
}
