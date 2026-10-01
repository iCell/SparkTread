import Testing
@testable import GameCore

/// GAME_RULES §9.2 cost-field navigation and §10.2 drop placement.
private func openWorld(_ build: (inout WorldState) -> Void = { _ in }) -> WorldState {
    var terrain = TerrainGrid(arena: .universal)
    let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
    for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
    for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
    var world = WorldState(terrain: terrain, seed: 9)
    // A player without a tank on the field: enemies have only the base to
    // go for, so these tests measure navigation, not target dithering, and
    // no idle tank can be shot dead (which would end the stage).
    world.addPlayer(PlayerState(playerID: .one))
    world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 40 * 1024, y: 22 * 1024))
    world.stage = StageState(spawnQueue: [], maxAliveEnemies: 4, enemyStartDelayTicks: 999_999,
                             spawnPointsCells: [Vec2i(x: 2, y: 1)],
                             playerRespawnCell: Vec2i(x: 3, y: 22), dropTable: [])
    build(&world)
    return world
}

private func run(_ world: inout WorldState, _ ticks: Int) {
    for _ in 0..<ticks {
        Simulation.step(&world, commands: [PlayerCommand(playerID: .one, targetTick: world.tick)])
    }
}

/// Chebyshev distance in cells between an enemy footprint and the base box.
private func cellsToBase(_ world: WorldState, _ tank: TankState) -> Int {
    guard let base = world.base else { return .max }
    let cell = SpatialUnits.subunitsPerCell
    let ax = tank.positionSubunits.x / cell, ay = tank.positionSubunits.y / cell
    let bx = base.topLeftSubunits.x / cell, by = base.topLeftSubunits.y / cell
    let dx = max(bx - (ax + 1), ax - (bx + 1), 0), dy = max(by - (ay + 1), ay - (by + 1), 0)
    return max(dx, dy)
}

@Suite struct NavigationFieldTests {
    @Test func fieldDescendsTowardTheBaseAndRoutesAroundSteel() {
        let world = openWorld { w in
            for y in 1...23 { w.terrain[30, y] = TerrainCell(kind: .steel) } // wall; a 2-cell gap at rows 24–25
        }
        let field = Navigation.distanceField(world, goals: Navigation.baseApproachGoals(world))
        let width = world.arena.cellsWide
        #expect(field[1 * width + 2] < Navigation.unreachable) // the spawn anchor reaches the base
        #expect(field[1 * width + 2] > field[24 * width + 31]) // past the gap is closer
        // Steel anchors are impassable; the base's own cells are not goals.
        #expect(field[10 * width + 30] == Navigation.unreachable)
        #expect(field[22 * width + 40] == Navigation.unreachable)
        let options = Navigation.descent(field: field, world: world, anchor: Vec2i(x: 2, y: 1), preferred: .down)
        #expect(!options.isEmpty)
    }

    @Test func brickIsPassableAtACostSoASealedBaseStillAttractsASiege() {
        let world = openWorld { w in
            for x in 1...54 { w.terrain[x, 18] = TerrainCell(kind: .brick) } // full brick band
        }
        let field = Navigation.distanceField(world, goals: Navigation.baseApproachGoals(world))
        let width = world.arena.cellsWide
        let above = field[10 * width + 40], below = field[20 * width + 40]
        #expect(above < Navigation.unreachable)
        #expect(above - below >= Navigation.brickCost) // digging is priced, not forbidden
    }

    /// The owner's report: enemies must actually come for the base. From the
    /// far corner of an open arena an enemy reaches the fort in under a
    /// minute, and through a brick band it digs its way there. The base is
    /// shielded here so the enemy cannot end the stage by shooting it from
    /// across the row — this test measures the APPROACH; the attack is
    /// asserted separately in `unobstructedEnemyAttacksTheBase`.
    @Test func enemyReachesTheBaseAcrossTheArenaAndThroughBrick() {
        for withBand in [false, true] {
            var world = openWorld { w in
                w.base?.shieldRemainingTicks = 999_999
                if withBand { for x in 1...54 { w.terrain[x, 18] = TerrainCell(kind: .brick) } }
            }
            let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                                        positionSubunits: Vec2i(x: 2 * 1024, y: 1 * 1024), facing: .down)
            world.withTank(entityID: enemy) { $0.spawnProtectionTicks = 0; $0.specialWeaponID = "normal" }
            var closest = Int.max
            for _ in 0..<(withBand ? 18_000 : 9_000) { // GAME_RULES R5.2 enemy speeds
                run(&world, 1)
                if let tank = world.tank(entityID: enemy) { closest = min(closest, cellsToBase(world, tank)) }
                if closest <= 1 { break }
            }
            #expect(closest <= 1, "band=\(withBand): closest \(closest) cells")
        }
    }
}

@Suite struct NavigationCostConventionTests {
    /// R8-01: a goal's own brick is priced — the cheap clear approach wins
    /// over digging into an expensive goal one step away.
    @Test func expensiveGoalDoesNotBeatACheapClearApproach() {
        let world = openWorld { w in
            w.terrain[12, 10] = TerrainCell(kind: .brick)
            w.terrain[12, 11] = TerrainCell(kind: .brick)
        }
        let clear = Vec2i(x: 8, y: 10), bricky = Vec2i(x: 11, y: 10)
        #expect(Navigation.entryCost(world, anchor: bricky) == 13)
        let field = Navigation.distanceField(world, goals: [clear, bricky])
        let width = world.arena.cellsWide
        #expect(field[10 * width + 10] == 2) // two clear steps, goal entry included
        let options = Navigation.descent(field: field, world: world, anchor: Vec2i(x: 10, y: 10), preferred: .left)
        #expect(options.first?.direction == .left)
        #expect(options.first?.distance == 2)
        #expect(options.contains { $0.direction == .right } == false) // 13 > 2: not optimal
        #expect(Navigation.isAtGoal(field: field, world: world, anchor: clear))
        #expect(Navigation.descent(field: field, world: world, anchor: clear, preferred: .up).isEmpty)
    }

    /// Flame cannot break brick: for the fire family brick is impassable, so
    /// a full brick band makes the base unreachable and a partial band is
    /// routed around.
    @Test func fireFamilyRoutesAroundBrickInsteadOfDigging() {
        let sealed = openWorld { w in for x in 1...54 { w.terrain[x, 18] = TerrainCell(kind: .brick) } }
        let width = sealed.arena.cellsWide
        let flame = Navigation.Context(dig: Navigation.DigAbility(brick: false, steel: false))
        let cannotDig = Navigation.distanceField(sealed, goals: Navigation.baseApproachGoals(sealed, context: flame), context: flame)
        #expect(cannotDig[10 * width + 40] == Navigation.unreachable)
        let canDig = Navigation.distanceField(sealed, goals: Navigation.baseApproachGoals(sealed))
        #expect(canDig[10 * width + 40] < Navigation.unreachable)

        var partial = openWorld { w in
            w.base?.shieldRemainingTicks = 999_999 // approach, not attack
            for x in 1...50 { w.terrain[x, 18] = TerrainCell(kind: .brick) }
        }
        let enemy = partial.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "fire_a",
                                      positionSubunits: Vec2i(x: 2 * 1024, y: 1 * 1024), facing: .down)
        partial.withTank(entityID: enemy) { $0.spawnProtectionTicks = 0; $0.specialWeaponID = "fire" }
        var closest = Int.max
        for _ in 0..<18_000 {
            run(&partial, 1)
            if let tank = partial.tank(entityID: enemy) { closest = min(closest, cellsToBase(partial, tank)) }
            if closest <= 1 { break }
        }
        #expect(closest <= 1)
        #expect(partial.terrain[25, 18].kind == .brick) // it went around, not through
    }

    /// Arrival is not attack: an unobstructed enemy must actually damage the
    /// base (enemy-origin baseDamaged), separately from proximity.
    @Test func unobstructedEnemyAttacksTheBase() {
        var world = openWorld()
        let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                                    positionSubunits: Vec2i(x: 2 * 1024, y: 1 * 1024), facing: .down)
        world.withTank(entityID: enemy) { $0.spawnProtectionTicks = 0; $0.specialWeaponID = "normal" }
        var damaged = false
        for _ in 0..<14_000 {
            let events = Simulation.step(&world, commands: [PlayerCommand(playerID: .one, targetTick: world.tick)])
            if events.contains(where: { if case .baseDamaged(_, _, false) = $0 { true } else { false } }) {
                damaged = true; break
            }
        }
        #expect(damaged)
    }
}

@Suite struct DropPlacementTests {
    private func withPlayer(_ build: (inout WorldState) -> Void = { _ in }) -> WorldState {
        var world = openWorld(build)
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3 * 1024, y: 20 * 1024), facing: .up)
        world.withTanksInEntityOrder { $0.spawnProtectionTicks = 0 }
        return world
    }

    private func kill(_ world: inout WorldState, at cell: Vec2i, carrying: String? = nil) {
        let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                                    positionSubunits: Vec2i(x: cell.x * 1024, y: cell.y * 1024), facing: .down)
        world.withTank(entityID: enemy) {
            $0.spawnProtectionTicks = 0; $0.armor = 0
            $0.carriedPickup = carrying.map { CarriedPickup(pickupID: $0) }
        }
    }

    /// §10.2: drops land on legal 2×2 interior areas away from the base and
    /// tanks, in the region the player can reach.
    @Test func dropsAppearOnLegalReachableAreas() {
        var world = withPlayer { w in
            w.stage?.dropTable = ["speed_up"]; w.stage?.dropChancePercent = 100
            // A white-steel wall seals the right half: unreachable for the player.
            for y in 1...25 { w.terrain[28, y] = TerrainCell(kind: .whiteSteel) }
        }
        for i in 0..<6 { kill(&world, at: Vec2i(x: 5 + i * 3, y: 8)) }
        Simulation.step(&world, commands: [])
        #expect(world.pickups.count == 6)
        for pickup in world.pickups {
            #expect(pickup.cell.x >= 1 && pickup.cell.y >= 1 && pickup.cell.x + 1 < 27 && pickup.cell.y + 1 <= 25)
            for dy in 0..<2 { for dx in 0..<2 { #expect(world.terrain[pickup.cell.x + dx, pickup.cell.y + dy].canHoldPickup) } }
        }
        for (i, a) in world.pickups.enumerated() {
            for b in world.pickups.dropFirst(i + 1) {
                #expect(abs(a.cell.x - b.cell.x) >= 2 || abs(a.cell.y - b.cell.y) >= 2) // never overlapping
            }
        }
    }

    /// §10.2: without a living player tank a guaranteed drop waits in the
    /// queue instead of being lost.
    @Test func guaranteedDropWaitsForThePlayer() {
        var world = openWorld { $0.stage?.spawnQueue = ["normal_a"] } // keeps the stage undecided
        kill(&world, at: Vec2i(x: 20, y: 10), carrying: "bomb")
        Simulation.step(&world, commands: [])
        #expect(world.pickups.isEmpty && world.stage?.pendingPickups.count == 1)
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3 * 1024, y: 20 * 1024), facing: .up)
        Simulation.step(&world, commands: [])
        #expect(world.pickups.count == 1 && world.stage?.pendingPickups.isEmpty == true)
    }

    @Test func randomPlacementIsDeterministic() {
        func run() -> WorldState {
            var world = withPlayer { w in w.stage?.dropTable = ["armor_up"]; w.stage?.dropChancePercent = 100 }
            for i in 0..<3 { kill(&world, at: Vec2i(x: 10 + i * 4, y: 8)) }
            Simulation.step(&world, commands: [])
            return world
        }
        let a = run(), b = run()
        #expect(a.pickups.count == 3)
        #expect(a == b)
    }
}
