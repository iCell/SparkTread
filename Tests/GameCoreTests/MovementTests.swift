import Testing
@testable import GameCore

/// Small custom worlds for precise movement geometry. Cell = 1024 subunits;
/// tank footprint 2048² with 64-subunit collision inset (box 1920²).
private func makeWorld(_ build: (inout TerrainGrid) -> Void = { _ in }) -> WorldState {
    var terrain = TerrainGrid(arena: .universal)
    let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
    for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
    for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
    build(&terrain)
    var world = WorldState(terrain: terrain, seed: 7)
    world.addPlayer(PlayerState(playerID: .one))
    return world
}

private func hold(_ world: inout WorldState, _ direction: Direction?, ticks: Int,
                  ruleset: MovementRuleset = .provisional) {
    for _ in 0..<ticks {
        Simulation.step(&world, commands: [PlayerCommand(
            playerID: .one, targetTick: world.tick, moveDirection: direction)], ruleset: ruleset)
    }
}

@Suite struct MovementAccumulatorTests {
    @Test func level0Moves48SubunitsPerTickExactly() {
        var world = makeWorld()
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3072, y: 3072), facing: .right)
        hold(&world, .right, ticks: 1)
        #expect(world.tanks[0].positionSubunits.x == 3072 + 48) // 2880/60
        hold(&world, .right, ticks: 59)
        #expect(world.tanks[0].positionSubunits.x == 3072 + 2880)
    }

    @Test func fractionalMultiplierAccumulatesWithoutDrift() {
        var world = makeWorld()
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3072, y: 3072), facing: .right)
        world.withTank(entityID: 1) { $0.speedLevel = 1 } // ×1.260 → 60.48/tick
        hold(&world, .right, ticks: 100)
        // 100 × 2880×1260 = 362,880,000; ÷60,000 = 6,048 subunits exactly.
        #expect(world.tanks[0].positionSubunits.x == 3072 + 6048)
        #expect(world.tanks[0].movementAccumulator == 0)
    }

    @Test func noMovementWithoutHeldDirection() {
        var world = makeWorld()
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3072, y: 3072), facing: .right)
        hold(&world, nil, ticks: 30)
        #expect(world.tanks[0].positionSubunits == Vec2i(x: 3072, y: 3072))
    }
}

@Suite struct CollisionTests {
    @Test func tankStopsFlushAgainstWallAndBounds() {
        var world = makeWorld { terrain in
            for y in 1...25 { terrain[9, y] = TerrainCell(kind: .brick) }
        }
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3072, y: 3072), facing: .right)
        hold(&world, .right, ticks: 200)
        // Wall face at 9×1024 = 9216; box maxX = pos+2048−64 ⇒ pos = 7232.
        #expect(world.tanks[0].positionSubunits.x == 7232)

        hold(&world, .up, ticks: 200)
        // Top border face at 1024; box minY = pos+64 ⇒ pos = 960.
        #expect(world.tanks[0].positionSubunits.y == 960)
    }

    @Test func tankNeverEntersSolidOrLeavesBoundsUnderRandomScript() {
        var world = makeWorld { terrain in
            for y in 5...20 { terrain[20, y] = TerrainCell(kind: .brick) }
            for x in 12...30 { terrain[x, 12] = TerrainCell(kind: .steel) }
            for y in 15...19 { for x in 34...40 { terrain[x, y] = TerrainCell(kind: .water) } }
        }
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 2048, y: 2048), facing: .down)
        var rng = SplitMix64(seed: 99)
        for _ in 0..<5000 {
            let dir = Direction(rawValue: rng.next(upperBound: 4))!
            hold(&world, rng.next(upperBound: 5) == 0 ? nil : dir, ticks: 1)
            let p = world.tanks[0].positionSubunits
            let box = (minX: p.x + 64, minY: p.y + 64, maxX: p.x + 1984, maxY: p.y + 1984)
            #expect(!world.terrain.blocksTank(minX: box.minX, minY: box.minY,
                                             maxX: box.maxX, maxY: box.maxY),
                    "tank inside solid at \(p) tick \(world.tick)")
        }
    }

    @Test func damagedQuadrantsBlockOnlyRemainingGeometry() {
        var world = makeWorld { terrain in
            // Brick at cell (9,3) with only the RIGHT quadrants remaining.
            terrain[9, 3] = TerrainCell(kind: .brick, quadrantMask: 0b1010)
            terrain[9, 4] = TerrainCell(kind: .brick, quadrantMask: 0b1010)
        }
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3072, y: 3072), facing: .right)
        hold(&world, .right, ticks: 200)
        // Remaining right quadrants start at 9×1024+512 = 9728 ⇒ pos = 7744.
        #expect(world.tanks[0].positionSubunits.x == 7744)
    }
}

@Suite struct TurningTests {
    /// Wall column at cell x=5 with a 2-cell opening at rows 11–12.
    private func corridorWorld() -> WorldState {
        makeWorld { terrain in
            for y in 1...25 where !(11...12).contains(y) {
                terrain[5, y] = TerrainCell(kind: .brick)
            }
        }
    }

    @Test func reversalAlwaysTurns() {
        var world = makeWorld()
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3072, y: 3072), facing: .right)
        hold(&world, .left, ticks: 1)
        #expect(world.tanks[0].facing == .left)
    }

    @Test func deadEndStillAllowsFacingTheWall() {
        var world = corridorWorld()
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3072, y: 3072), facing: .right)
        hold(&world, .right, ticks: 100) // wall face 5×1024 = 5120 ⇒ stops at 3136
        #expect(world.tanks[0].positionSubunits.x == 3136)
        hold(&world, .up, ticks: 100) // turning up lane-snaps x back to 3072, rolls to border
        #expect(world.tanks[0].positionSubunits == Vec2i(x: 3072, y: 960))
        hold(&world, .right, ticks: 3) // right blocked AND up blocked ⇒ face right in place,
        #expect(world.tanks[0].facing == .right) // then roll through the inset slack to flush
        #expect(world.tanks[0].positionSubunits.x == 3136)
    }

    @Test func alignedPerpendicularTurnThroughOpening() {
        var world = corridorWorld()
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3072, y: 11264), facing: .down) // aligned with rows 11–12
        hold(&world, .right, ticks: 1)
        #expect(world.tanks[0].facing == .right)
        hold(&world, .right, ticks: 120)
        #expect(world.tanks[0].positionSubunits.x > 5 * 1024) // passed through the opening
        #expect(world.tanks[0].positionSubunits.y == 11264)
    }

    @Test func assistSnapsWithinWindow() {
        var world = corridorWorld()
        // 200 subunits above alignment; within the 256-subunit assist window
        // of the full-cell corridor lane at y = 11264.
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3072, y: 11264 - 200), facing: .down)
        hold(&world, .right, ticks: 1)
        #expect(world.tanks[0].facing == .right)
        #expect(world.tanks[0].positionSubunits.y == 11264) // snapped onto the corridor
    }

    @Test func bufferedTapExecutesWhenAlignmentArrives() {
        var world = corridorWorld()
        // 600 subunits above alignment: outside the assist window, inside the
        // 10-tick × 48-subunit buffered travel distance.
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3072, y: 11264 - 600), facing: .down)
        hold(&world, .right, ticks: 1)   // tap right — cannot turn yet
        #expect(world.tanks[0].facing == .down)
        #expect(world.tanks[0].bufferedDirection == .right)
        // Full release: the pending buffer keeps the tank rolling to the
        // junction and the turn fires when alignment arrives.
        hold(&world, nil, ticks: 9)
        #expect(world.tanks[0].facing == .right)
        #expect(world.tanks[0].positionSubunits.y == 11264)
        #expect(world.tanks[0].bufferedDirection == nil)
    }

    /// With no junction within buffered travel, a perpendicular press turns
    /// in place immediately (owner-reported: a tank beside an obstacle must
    /// still be able to face it, e.g. to shoot the wall).
    @Test func farFromJunctionPerpendicularPressTurnsInPlace() {
        var world = corridorWorld()
        // 2,000 subunits above the opening: no junction within reach.
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3072, y: 11264 - 2000), facing: .down)
        hold(&world, .right, ticks: 1)
        #expect(world.tanks[0].facing == .right) // faces the wall immediately
        #expect(world.tanks[0].bufferedDirection == nil)
    }

    /// Stationary beside a wall: pressing toward it turns the tank so the
    /// wall can be shot; movement stays blocked.
    @Test func stationaryTankCanFaceAdjacentWall() {
        var world = corridorWorld()
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3136, y: 3072), facing: .up) // flush right of wall face 5120? x=3136: box max 5120 flush
        hold(&world, .right, ticks: 3)
        #expect(world.tanks[0].facing == .right)
        #expect(world.tanks[0].positionSubunits.x == 3136) // wedged, not moved
    }
}
