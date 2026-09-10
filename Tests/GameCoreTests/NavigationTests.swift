import Testing
@testable import GameCore

/// §10.4 cost-field navigation and the owner's random drop placement.
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
            for _ in 0..<(withBand ? 7200 : 3600) {
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
        let cannotDig = Navigation.distanceField(sealed, goals: Navigation.baseApproachGoals(sealed, canDig: false), canDig: false)
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
        for _ in 0..<7200 {
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
        for _ in 0..<5400 {
            let events = Simulation.step(&world, commands: [PlayerCommand(playerID: .one, targetTick: world.tick)])
            if events.contains(where: { if case .baseDamaged(_, _, false) = $0 { true } else { false } }) {
                damaged = true; break
            }
        }
        #expect(damaged)
    }
}

@Suite struct DropPlacementTests {
    /// R8-02: the random policy never weakens its constraints on the
    /// fallback path — with the only free cells under a tank, no pickup is
    /// created inside the footprint.
    @Test func randomPolicyFallbackStillAvoidsTanks() {
        var world = openWorld { w in
            for y in 1...25 { for x in 1...54 { w.terrain[x, y] = TerrainCell(kind: .steel) } }
            for y in 10...11 { for x in 10...11 { w.terrain[x, y] = TerrainCell(kind: .ground) } }
        }
        let blocker = world.spawnTank(teamID: 1, ownerPlayerID: nil, archetypeID: "normal_a",
                                      positionSubunits: Vec2i(x: 10 * 1024, y: 10 * 1024), facing: .down)
        _ = blocker
        var events: [DomainEvent] = []
        Stage.spawnDrop(&world, pickupID: "bomb", deathCell: Vec2i(x: 10, y: 10),
                        rules: .provisional, events: &events)
        #expect(world.pickups.isEmpty) // documented: lost rather than placed under a tank
        var plan = PickupRuleset.provisional
        plan.dropsSpawnAtRandomCells = false
        Stage.spawnDrop(&world, pickupID: "bomb", deathCell: Vec2i(x: 10, y: 10), rules: plan, events: &events)
        #expect(world.pickups.count == 1) // the plan text keeps its own policy (grace period covers the tank)
    }

    @Test func dropsAppearOnALegalCellAwayFromTheBaseAndTanks() {
        var world = openWorld { w in w.stage?.dropTable = ["speed_up"]; w.stage?.dropChancePercent = 100 }
        var events: [DomainEvent] = []
        for i in 0..<6 {
            let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                                        positionSubunits: Vec2i(x: (10 + i * 3) * 1024, y: 10 * 1024), facing: .down)
            world.withTank(entityID: enemy) { $0.spawnProtectionTicks = 0; $0.armor = 0 }
        }
        events += Simulation.step(&world, commands: [])
        #expect(world.pickups.count == 6)
        let cell = SpatialUnits.subunitsPerCell
        for pickup in world.pickups {
            let cx = pickup.positionSubunits.x / cell, cy = pickup.positionSubunits.y / cell
            #expect(world.terrain[cx, cy].kind.canHoldPickup)
            #expect(!(cx >= 40 && cx <= 41 && cy >= 22 && cy <= 23)) // never under the base
            // Not where the enemies died (row 10, columns 10…25) — the rule
            // is "elsewhere"; six independent draws all landing on the death
            // row would be a one-in-thousands accident.
        }
        #expect(Set(world.pickups.map { $0.positionSubunits.y / cell }).count > 1 || world.pickups.first!.positionSubunits.y / cell != 10)
    }

    @Test func planPlacementRemainsAvailableAsRulesetData() {
        var plan = PickupRuleset.provisional
        plan.dropsSpawnAtRandomCells = false
        var world = openWorld { w in w.stage?.carriedPickupQueue = [] }
        let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                                    positionSubunits: Vec2i(x: 20 * 1024, y: 10 * 1024), facing: .down)
        world.withTank(entityID: enemy) { $0.spawnProtectionTicks = 0; $0.armor = 0; $0.carriedPickupID = "bomb" }
        Simulation.step(&world, commands: [], pickups: plan)
        #expect(world.pickups.count == 1)
        let cell = SpatialUnits.subunitsPerCell
        #expect(world.pickups.first?.positionSubunits.x == 21 * cell + cell / 2) // the death cell (footprint center)
        #expect(world.pickups.first?.positionSubunits.y == 11 * cell + cell / 2)
    }

    @Test func randomPlacementIsDeterministic() {
        func run() -> WorldState {
            var world = openWorld { w in w.stage?.dropTable = ["armor_up"]; w.stage?.dropChancePercent = 100 }
            for i in 0..<3 {
                let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                                            positionSubunits: Vec2i(x: (10 + i * 4) * 1024, y: 8 * 1024), facing: .down)
                world.withTank(entityID: enemy) { $0.spawnProtectionTicks = 0; $0.armor = 0 }
            }
            Simulation.step(&world, commands: [])
            return world
        }
        let a = run(), b = run()
        #expect(a.pickups.count == 3)
        #expect(a == b)
    }
}
