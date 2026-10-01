import Foundation
import Testing
@testable import GameCore

/// GAME_RULES §4.3–§4.4, §8: equipment traversal profiles (water needs
/// AmphiTank; AntiSkid grips ice), the water-exit rule and ice inertia.
private let cell = SpatialUnits.subunitsPerCell

private func makeWorld(_ build: (inout TerrainGrid) -> Void = { _ in }) -> WorldState {
    var terrain = TerrainGrid(arena: .universal)
    let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
    for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
    for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
    build(&terrain)
    var world = WorldState(terrain: terrain, seed: 9)
    world.addPlayer(PlayerState(playerID: .one))
    return world
}

@discardableResult
private func spawnPlayer(_ world: inout WorldState, cellX: Int, cellY: Int, facing: Direction, equipment: String? = nil) -> Int {
    let id = world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                             positionSubunits: Vec2i(x: cellX * cell, y: cellY * cell), facing: facing)
    world.withTank(entityID: id) { $0.equipmentID = equipment; $0.spawnProtectionTicks = 0 }
    return id
}

private func hold(_ world: inout WorldState, _ direction: Direction?, ticks: Int, ruleset: MovementRuleset = .provisional) {
    for _ in 0..<ticks {
        Simulation.step(&world, commands: [PlayerCommand(playerID: .one, targetTick: world.tick, moveDirection: direction)],
                        ruleset: ruleset)
    }
}

@Suite struct TraversalProfileTests {
    @Test func profilesFollowEquipmentAndWaterBlocksOnlyTheOthers() {
        #expect(TraversalProfile(equipmentID: "amphi_tank") == .amphibious)
        #expect(TraversalProfile(equipmentID: "anti_skid") == .traction)
        #expect(TraversalProfile(equipmentID: "unknown") == .normal && TraversalProfile(equipmentID: nil) == .normal)
        let water = TerrainCell(kind: .water), ice = TerrainCell(kind: .ice)
        #expect(water.surfaceBlocksTank(profile: .amphibious) == false)
        #expect(water.surfaceBlocksTank(profile: .normal) && water.surfaceBlocksTank(profile: .traction))
        #expect(!ice.surfaceBlocksTank(profile: .normal))
        let grid = makeWorld { t in for y in 8...12 { for x in 20...24 { t[x, y] = TerrainCell(kind: .water) } } }.terrain
        #expect(grid.blocksTank(minX: 21 * cell, minY: 9 * cell, maxX: 23 * cell, maxY: 11 * cell))
        #expect(!grid.blocksTank(minX: 21 * cell, minY: 9 * cell, maxX: 23 * cell, maxY: 11 * cell, profile: .amphibious))
    }

    @Test func onlyAnAmphibiousTankCrossesThePool() {
        func drive(equipment: String?) -> Int {
            var world = makeWorld { t in for y in 5...20 { for x in 20...24 { t[x, y] = TerrainCell(kind: .water) } } }
            spawnPlayer(&world, cellX: 15, cellY: 10, facing: .right, equipment: equipment)
            hold(&world, .right, ticks: 600)
            return world.tanks[0].positionSubunits.x
        }
        let inset = MovementRuleset.provisional.collisionInsetSubunits
        #expect(drive(equipment: nil) == 18 * cell + inset)          // flush against the water's edge (collision box)
        #expect(drive(equipment: "anti_skid") == 18 * cell + inset)
        #expect(drive(equipment: "amphi_tank") > 25 * cell)  // across and beyond
    }

    /// §4.4: a tank that lost AmphiTank at the shore may only move in a way
    /// that shrinks its water overlap; once dry the water blocks it again.
    @Test func aTankLeavingWaterMayOnlyReduceItsOverlap() {
        var world = makeWorld { t in for y in 5...20 { for x in 20...24 { t[x, y] = TerrainCell(kind: .water) } } }
        let id = spawnPlayer(&world, cellX: 24, cellY: 10, facing: .right)
        world.withTank(entityID: id) { $0.leavingWater = true }
        let start = world.tanks[0].positionSubunits
        hold(&world, .up, ticks: 30) // along the shore: the overlap would not shrink
        #expect(world.tanks[0].positionSubunits.y == start.y)
        hold(&world, .left, ticks: 30) // deeper: refused
        #expect(world.tanks[0].positionSubunits.x == start.x)
        hold(&world, .right, ticks: 60) // out
        #expect(world.tanks[0].leavingWater == false)
        hold(&world, .left, ticks: 120) // and the water blocks it again (collision box)
        #expect(world.tanks[0].positionSubunits.x == 25 * cell - MovementRuleset.provisional.collisionInsetSubunits)
    }

    /// §4.4: with no move that reduces the overlap, the tank is placed on
    /// the nearest legal half-cell lane with at least 60 ticks' protection.
    @Test func aTankTrappedInWaterIsPlacedOnTheNearestLand() {
        var world = makeWorld { t in for y in 5...20 { for x in 20...24 { t[x, y] = TerrainCell(kind: .water) } } }
        let id = spawnPlayer(&world, cellX: 21, cellY: 10, facing: .right)
        world.withTank(entityID: id) { $0.leavingWater = true }
        hold(&world, nil, ticks: 1)
        #expect(world.tanks[0].leavingWater == false)
        #expect(world.tanks[0].positionSubunits.y == 10 * cell)
        #expect(world.tanks[0].positionSubunits.x == 18432) // left shore: collision box just clear of x = 20 480
        #expect(world.tanks[0].spawnProtectionTicks >= 59)
    }

    @Test func losingAmphiByPickupStartsTheWaterExit() {
        var world = makeWorld { t in for y in 5...20 { for x in 20...24 { t[x, y] = TerrainCell(kind: .water) } } }
        spawnPlayer(&world, cellX: 24, cellY: 10, facing: .right, equipment: "amphi_tank")
        var events: [DomainEvent] = []
        #expect(world.spawnStagePickup("anti_skid", atCell: Vec2i(x: 26, y: 10), events: &events))
        hold(&world, .right, ticks: 1) // touches the pickup while still over water
        #expect(world.tanks[0].equipmentID == "anti_skid" && world.tanks[0].leavingWater)
    }

    @Test func navigationRoutesAmphibiousEnemiesThroughWater() {
        // A wall of water splits the arena; only an amphibious field crosses it.
        let world = makeWorld { t in for y in 1...25 { t[28, y] = TerrainCell(kind: .water); t[29, y] = TerrainCell(kind: .water) } }
        let goals = [Vec2i(x: 40, y: 10)]
        let normal = Navigation.distanceField(world, goals: goals, context: Navigation.Context(profile: .normal))
        let amphibious = Navigation.distanceField(world, goals: goals, context: Navigation.Context(profile: .amphibious))
        let start = 10 * world.arena.cellsWide + 10
        #expect(normal[start] == Navigation.unreachable)
        #expect(amphibious[start] < Navigation.unreachable)
        #expect(Navigation.isPassable(world, anchor: Vec2i(x: 28, y: 10), context: Navigation.Context(profile: .amphibious)))
        #expect(!Navigation.isPassable(world, anchor: Vec2i(x: 28, y: 10), context: Navigation.Context(profile: .normal)))
    }
}

@Suite struct IceInertiaTests {
    private func iceWorld(equipment: String? = nil, facing: Direction = .right) -> WorldState {
        var world = makeWorld { t in for y in 5...15 { for x in 10...30 { t[x, y] = TerrainCell(kind: .ice) } } }
        spawnPlayer(&world, cellX: 12, cellY: 10, facing: facing, equipment: equipment)
        return world
    }

    @Test func releasingOnIceSlidesTheDistanceThenStops() {
        var world = iceWorld()
        hold(&world, .right, ticks: 60)
        let released = world.tanks[0].positionSubunits.x
        #expect(world.tanks[0].slideDirection == .right && world.tanks[0].slideMomentumSubunits == 0)
        hold(&world, nil, ticks: 1)
        #expect(world.tanks[0].slideMomentumSubunits > 0 && world.tanks[0].slideDirection == .right)
        hold(&world, nil, ticks: 200)
        let stopped = world.tanks[0].positionSubunits.x
        #expect(stopped - released == MovementRuleset.provisional.iceSlideDistanceSubunits)
        #expect(world.tanks[0].slideMomentumSubunits == 0 && world.tanks[0].slideDirection == nil)
        hold(&world, nil, ticks: 60)
        #expect(world.tanks[0].positionSubunits.x == stopped) // at rest
    }

    @Test func antiSkidAndPlainGroundDoNotSlide() {
        var gripping = iceWorld(equipment: "anti_skid")
        hold(&gripping, .right, ticks: 60)
        let x = gripping.tanks[0].positionSubunits.x
        hold(&gripping, nil, ticks: 60)
        #expect(gripping.tanks[0].positionSubunits.x == x && gripping.tanks[0].slideDirection == nil)
        var ground = makeWorld()
        spawnPlayer(&ground, cellX: 12, cellY: 10, facing: .right)
        hold(&ground, .right, ticks: 60)
        let gx = ground.tanks[0].positionSubunits.x
        hold(&ground, nil, ticks: 60)
        #expect(ground.tanks[0].positionSubunits.x == gx)
        var disabled = MovementRuleset.provisional
        disabled.iceSlideDistanceSubunits = 0
        var off = iceWorld()
        hold(&off, .right, ticks: 60, ruleset: disabled)
        let ox = off.tanks[0].positionSubunits.x
        hold(&off, nil, ticks: 60, ruleset: disabled)
        #expect(off.tanks[0].positionSubunits.x == ox)
    }

    @Test func slideKeepsTheSpeedItStartedWith() {
        var world = iceWorld()
        hold(&world, .right, ticks: 60)
        hold(&world, nil, ticks: 1)
        let increment = world.tanks[0].slideIncrement
        world.withTank(entityID: world.tanks[0].entityID) { $0.speedLevel = 3 } // Speed Up mid-slide
        let before = world.tanks[0].positionSubunits.x
        hold(&world, nil, ticks: 1)
        #expect(world.tanks[0].slideIncrement == increment)
        #expect(world.tanks[0].positionSubunits.x - before <= increment / MovementRuleset.accumulatorUnitsPerSubunit + 1)
    }

    @Test func changingDirectionOnIceTurnsButKeepsSlidingUntilSpent() {
        var world = iceWorld()
        hold(&world, .right, ticks: 60)
        let turned = world.tanks[0].positionSubunits
        hold(&world, .down, ticks: 1)
        #expect(world.tanks[0].facing == .down && world.tanks[0].slideDirection == .right)
        #expect(world.tanks[0].positionSubunits.y == turned.y && world.tanks[0].positionSubunits.x > turned.x)
        hold(&world, .down, ticks: 120)
        // Slid the full distance to the right, then drove down.
        #expect(world.tanks[0].positionSubunits.x - turned.x == MovementRuleset.provisional.iceSlideDistanceSubunits)
        #expect(world.tanks[0].positionSubunits.y > turned.y)
        // Pressing the slide direction itself cancels the slide and drives on.
        var driving = iceWorld()
        hold(&driving, .right, ticks: 60)
        hold(&driving, nil, ticks: 1)
        #expect(driving.tanks[0].slideMomentumSubunits > 0)
        hold(&driving, .right, ticks: 1)
        #expect(driving.tanks[0].slideMomentumSubunits == 0 && driving.tanks[0].slideDirection == .right)
    }

    @Test func aSlideStopsFlushAgainstAWallAndLeavingIceEndsIt() {
        var world = makeWorld { t in
            for y in 5...15 { for x in 10...30 { t[x, y] = TerrainCell(kind: .ice) } }
            for y in 5...15 { t[16, y] = TerrainCell(kind: .steel) }
        }
        spawnPlayer(&world, cellX: 12, cellY: 10, facing: .right)
        hold(&world, .right, ticks: 30)
        hold(&world, nil, ticks: 200)
        #expect(world.tanks[0].positionSubunits.x == 14 * cell + MovementRuleset.provisional.collisionInsetSubunits) // flush against the steel
        #expect(world.tanks[0].slideMomentumSubunits == 0)
        // §4.3: the slide ends the tick the centre leaves the ice.
        var edge = makeWorld { t in for y in 5...15 { for x in 10...13 { t[x, y] = TerrainCell(kind: .ice) } } }
        spawnPlayer(&edge, cellX: 11, cellY: 10, facing: .right)
        // Roll until the centre is within one slide of the edge (x = 14 336), still on ice.
        while edge.tanks[0].positionSubunits.x + 1024 < 14_336 - 1_400 { hold(&edge, .right, ticks: 1) }
        let released = edge.tanks[0].positionSubunits.x
        hold(&edge, nil, ticks: 100)
        let slid = edge.tanks[0].positionSubunits.x - released
        #expect(slid > 0 && slid < MovementRuleset.provisional.iceSlideDistanceSubunits)
        #expect((edge.tanks[0].positionSubunits.x + 1024) / cell == 14) // stopped just past the edge
        #expect(edge.tanks[0].slideMomentumSubunits == 0 && edge.tanks[0].slideDirection == nil)
    }

    @Test func slidesAreDeterministicAndSurviveSerialization() throws {
        var a = iceWorld(), b = iceWorld()
        hold(&a, .right, ticks: 45); hold(&b, .right, ticks: 45)
        hold(&a, nil, ticks: 3); hold(&b, nil, ticks: 3)
        #expect(a.tanks[0].slideMomentumSubunits > 0)
        let data = try JSONEncoder().encode(a)
        var restored = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(restored == a && restored.checksum() == a.checksum())
        hold(&restored, nil, ticks: 100); hold(&b, nil, ticks: 100)
        #expect(restored.checksum() == b.checksum())
        var rules = MovementRuleset.provisional
        rules.iceSlideDistanceSubunits = 9999
        #expect(rules.validationIssues().contains { $0.contains("ice_slide") })

    }
}
