import Testing
@testable import GameCore

/// §8.5 collision-matrix coverage. Geometry base: cell = 1024, tank
/// footprint 2048 (box inset 64), projectile half-extent 96. Player is
/// team 1 at cells (3,3); the base belongs to team 1.
private func makeCombatWorld(_ build: (inout WorldState) -> Void = { _ in }) -> WorldState {
    var terrain = TerrainGrid(arena: .universal)
    let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
    for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
    for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
    var world = WorldState(terrain: terrain, seed: 11)
    world.addPlayer(PlayerState(playerID: .one))
    world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                    positionSubunits: Vec2i(x: 3072, y: 3072), facing: .right)
    world.withTanksInEntityOrder { $0.spawnProtectionTicks = 0 }
    build(&world)
    return world
}

private func tickAll(_ world: inout WorldState, _ n: Int,
                     direction: Direction? = nil, normal: Bool = false, special: Bool = false,
                     events: inout [DomainEvent]) {
    for _ in 0..<n {
        events += Simulation.step(&world, commands: [PlayerCommand(
            playerID: .one, targetTick: world.tick, moveDirection: direction,
            normalFirePressed: normal, specialFirePressed: special)])
    }
}

private func spawnEnemy(_ world: inout WorldState, cellX: Int, cellY: Int,
                        archetype: String = "normal_a") -> Int {
    let id = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: archetype,
                             positionSubunits: Vec2i(x: cellX * 1024, y: cellY * 1024), facing: .left)
    world.withTank(entityID: id) { $0.spawnProtectionTicks = 0 }
    return id
}

/// Directly inject a projectile (for enemy-sourced shots in matrix tests).
private func injectProjectile(_ world: inout WorldState, weaponID: String, team: Int,
                              at position: Vec2i, direction: Direction, power: Int = 0) -> Int {
    let weapons = WeaponRuleset.provisional
    let weapon = weapons.weapon(weaponID)!
    let id = world.claimEntityID()
    world.projectiles.append(ProjectileState(
        entityID: id, weaponID: weaponID, ownerEntityID: -1, ownerPlayerID: nil,
        teamID: team, powerLevel: power, positionSubunits: position, direction: direction,
        speedSubunitsPerTick: weapon.level(weapon.initialSpeedSubunitsPerTick, power),
        lifetimeRemainingTicks: weapon.level(weapon.lifetimeTicks, power),
        penetrationRemaining: weapon.level(weapon.penetrationCount, power),
        durability: weapon.level(weapon.projectileDurability, power)))
    world.projectiles.sort { $0.entityID < $1.entityID }
    return id
}

private func giveSpecial(_ world: inout WorldState, _ weaponID: String, ammo: Int = 50, power: Int = 0) {
    if let tankID = world.player(.one)?.tankEntityID {
        world.withTank(entityID: tankID) { $0.specialWeaponID = weaponID; $0.powerLevel = power }
    }
    world.withPlayer(.one) { $0.specialAmmoByWeapon[weaponID] = ammo }
}

@Suite struct ProjectileMatrixTests {
    @Test func projectileVsEnemyTankDamagesAndDespawns() {
        var world = makeCombatWorld()
        let enemy = spawnEnemy(&world, cellX: 9, cellY: 3)
        var events: [DomainEvent] = []
        tickAll(&world, 1, normal: true, events: &events)
        tickAll(&world, 30, events: &events)
        #expect(world.tank(entityID: enemy)?.armor == 2) // 3 − 1
        #expect(world.projectiles.isEmpty)
        #expect(events.contains { if case .tankDamaged(enemy, 1, "normal") = $0 { true } else { false } })
        // Active count returned: the player can fire again.
        #expect(world.tanks[0].activeProjectileCounts["normal", default: 0] == 0)
    }

    @Test func projectileVsAlliedTankPassesThrough() {
        var world = makeCombatWorld()
        // Allied tank (team 1) directly in the firing line.
        let ally = world.spawnTank(teamID: 1, ownerPlayerID: nil, archetypeID: "normal_a",
                                   positionSubunits: Vec2i(x: 9216, y: 3072), facing: .left)
        world.withTank(entityID: ally) { $0.spawnProtectionTicks = 0 }
        var events: [DomainEvent] = []
        tickAll(&world, 1, normal: true, events: &events)
        tickAll(&world, 25, events: &events)
        #expect(world.tank(entityID: ally)?.armor == 3) // untouched (D-010)
        #expect(!world.projectiles.isEmpty) // still flying past the ally
    }

    @Test func projectileVsSpawnProtectedTankDeflects() {
        var world = makeCombatWorld()
        let enemy = spawnEnemy(&world, cellX: 9, cellY: 3)
        world.withTank(entityID: enemy) { $0.spawnProtectionTicks = 600 }
        var events: [DomainEvent] = []
        tickAll(&world, 1, normal: true, events: &events)
        tickAll(&world, 30, events: &events)
        #expect(world.tank(entityID: enemy)?.armor == 3) // no damage
        #expect(world.projectiles.isEmpty) // deflected/destroyed
    }

    @Test func projectileVsBrickDestroysQuadrantsSameTick() {
        var world = makeCombatWorld { w in
            w.terrain[9, 3] = TerrainCell(kind: .brick)
            w.terrain[9, 4] = TerrainCell(kind: .brick)
        }
        var events: [DomainEvent] = []
        tickAll(&world, 1, normal: true, events: &events)
        tickAll(&world, 30, events: &events)
        // Normal (brick damage 1) removes the entry-layer quadrants the
        // projectile box spans; collision geometry updated the same tick.
        #expect(events.contains { if case .terrainChanged = $0 { true } else { false } })
        let cell = world.terrain[9, 3]
        #expect(cell.kind == .brick && cell.quadrantMask != 0b1111)
        #expect(world.projectiles.isEmpty)
    }

    /// Regression (owner-reported): fragments beside the drill line must not
    /// linger — a shot carves a cell-wide strip, and a second aligned shot
    /// removes the back layer, leaving clean ground.
    @Test func twoAlignedShotsClearBrickCompletely() {
        var world = makeCombatWorld { w in
            w.terrain[9, 3] = TerrainCell(kind: .brick)
            w.terrain[9, 4] = TerrainCell(kind: .brick)
        }
        var events: [DomainEvent] = []
        tickAll(&world, 1, normal: true, events: &events)
        tickAll(&world, 34, events: &events) // impact + cooldown
        // First shot: front layer gone across the full cell width.
        #expect(world.terrain[9, 3].quadrantMask == 0b1010)
        #expect(world.terrain[9, 4].quadrantMask == 0b1010)
        tickAll(&world, 1, normal: true, events: &events)
        tickAll(&world, 34, events: &events)
        // Second shot: fragments fully removed, cells revert to ground.
        #expect(world.terrain[9, 3].kind == .ground)
        #expect(world.terrain[9, 4].kind == .ground)
    }

    @Test func normalCannotHurtSteelButAPCan() {
        var worldA = makeCombatWorld { w in w.terrain[9, 3] = TerrainCell(kind: .steel); w.terrain[9, 4] = TerrainCell(kind: .steel) }
        var events: [DomainEvent] = []
        tickAll(&worldA, 1, normal: true, events: &events)
        tickAll(&worldA, 30, events: &events)
        #expect(worldA.terrain[9, 3].quadrantMask == 0b1111) // steel untouched
        #expect(worldA.projectiles.isEmpty) // projectile destroyed

        var worldB = makeCombatWorld { w in w.terrain[9, 3] = TerrainCell(kind: .steel); w.terrain[9, 4] = TerrainCell(kind: .steel) }
        giveSpecial(&worldB, "ap", power: 1) // steel damage 1 at power 1
        events.removeAll()
        tickAll(&worldB, 1, special: true, events: &events)
        tickAll(&worldB, 40, events: &events)
        #expect(worldB.terrain[9, 3].quadrantMask != 0b1111 || worldB.terrain[9, 4].quadrantMask != 0b1111)
    }

    @Test func projectileVsProjectileDurabilityRules() {
        // Equal durability: both destroyed.
        var world = makeCombatWorld()
        _ = injectProjectile(&world, weaponID: "normal", team: 2,
                             at: Vec2i(x: 9216, y: 4096), direction: .left)
        var events: [DomainEvent] = []
        tickAll(&world, 1, normal: true, events: &events)
        tickAll(&world, 15, events: &events)
        #expect(world.projectiles.isEmpty)

        // AP (durability 2) survives a normal (durability 1).
        var world2 = makeCombatWorld()
        giveSpecial(&world2, "ap")
        _ = injectProjectile(&world2, weaponID: "normal", team: 2,
                             at: Vec2i(x: 9216, y: 4096), direction: .left)
        events.removeAll()
        tickAll(&world2, 1, special: true, events: &events)
        tickAll(&world2, 20, events: &events)
        #expect(world2.projectiles.count == 1)
        #expect(world2.projectiles[0].weaponID == "ap")
    }

    @Test func projectileVsBoundaryDespawns() {
        var world = makeCombatWorld { w in
            // Clear the border so the shot reaches the true arena edge.
            for y in 0..<27 { w.terrain[55, y] = TerrainCell(kind: .ground) }
        }
        var events: [DomainEvent] = []
        tickAll(&world, 1, normal: true, events: &events)
        tickAll(&world, 400, events: &events)
        #expect(world.projectiles.isEmpty)
        #expect(events.contains { if case .projectileDestroyed = $0 { true } else { false } })
    }

    @Test func projectileVsWaterIceFoliagePassesOver() {
        var world = makeCombatWorld { w in
            w.terrain[6, 3] = TerrainCell(kind: .water)
            w.terrain[7, 3] = TerrainCell(kind: .ice)
            w.terrain[8, 3] = TerrainCell(kind: .foliage)
            w.terrain[6, 4] = TerrainCell(kind: .water)
            w.terrain[7, 4] = TerrainCell(kind: .ice)
            w.terrain[8, 4] = TerrainCell(kind: .foliage)
        }
        let enemy = spawnEnemy(&world, cellX: 10, cellY: 3)
        var events: [DomainEvent] = []
        tickAll(&world, 1, normal: true, events: &events)
        tickAll(&world, 40, events: &events)
        #expect(world.tank(entityID: enemy)?.armor == 2) // hit through all three
    }
}

@Suite struct BaseMatrixTests {
    @Test func enemyProjectileDamagesBase() {
        var world = makeCombatWorld { w in
            w.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 9 * 1024, y: 3 * 1024))
        }
        _ = injectProjectile(&world, weaponID: "normal", team: 2,
                             at: Vec2i(x: 13 * 1024, y: 4096), direction: .left)
        var events: [DomainEvent] = []
        tickAll(&world, 20, events: &events)
        #expect(world.base?.durability == 99)
        #expect(events.contains { if case .baseDamaged(1, 99) = $0 { true } else { false } })
    }

    @Test func alliedBaseDamageGatedByDifficultyFlag() {
        // Standard/Veteran (flag on): the player's own shot hurts the base.
        var world = makeCombatWorld { w in
            w.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 9 * 1024, y: 3 * 1024))
        }
        var events: [DomainEvent] = []
        tickAll(&world, 1, normal: true, events: &events)
        tickAll(&world, 30, events: &events)
        #expect(world.base?.durability == 99)

        // Casual (flag off): the shot stops at the base without damage.
        var casualWeapons = WeaponRuleset.provisional
        casualWeapons.alliedBaseDamage = false
        var world2 = makeCombatWorld { w in
            w.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 9 * 1024, y: 3 * 1024))
        }
        for _ in 0..<31 {
            Simulation.step(&world2, commands: [PlayerCommand(
                playerID: .one, targetTick: world2.tick, moveDirection: nil,
                normalFirePressed: world2.tick == 0)], weapons: casualWeapons)
        }
        #expect(world2.base?.durability == 100)
        #expect(world2.projectiles.isEmpty) // still physically stopped
    }

    @Test func baseShieldDeflects() {
        var world = makeCombatWorld { w in
            w.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 9 * 1024, y: 3 * 1024),
                               shieldRemainingTicks: 600)
        }
        _ = injectProjectile(&world, weaponID: "normal", team: 2,
                             at: Vec2i(x: 13 * 1024, y: 4096), direction: .left)
        var events: [DomainEvent] = []
        tickAll(&world, 20, events: &events)
        #expect(world.base?.durability == 100)
        #expect(world.projectiles.isEmpty)
    }
}

@Suite struct MineMatrixTests {
    private func placeMine(_ world: inout WorldState, power: Int = 0) -> Int? {
        giveSpecial(&world, "mine", power: power)
        var events: [DomainEvent] = []
        tickAll(&world, 1, special: true, events: &events)
        for event in events { if case .minePlaced(let id, _, _) = event { return id } }
        return nil
    }

    @Test func rearDeployPlacesArmedMineBehindTank() {
        var world = makeCombatWorld() // facing right at (3072,3072)
        let id = placeMine(&world)
        #expect(id != nil)
        #expect(world.mines.count == 1)
        let mine = world.mines[0]
        #expect(mine.positionSubunits.x < 3072) // behind the right-facing tank
        #expect(mine.phase == .arming)
        var events: [DomainEvent] = []
        tickAll(&world, 50, events: &events)
        #expect(world.mines[0].phase == .armed)
    }

    @Test func mineStackingIsIllegal() {
        var world = makeCombatWorld()
        _ = placeMine(&world)
        var events: [DomainEvent] = []
        tickAll(&world, 35, events: &events) // cooldown over, tank unmoved
        events.removeAll()
        tickAll(&world, 1, special: true, events: &events)
        #expect(world.mines.count == 1) // second placement refused
        #expect(events.contains { if case .dryFire = $0 { true } else { false } })
    }

    @Test func enemyTankTriggersMineAndTakesBlast() {
        var world = makeCombatWorld()
        _ = placeMine(&world)
        var events: [DomainEvent] = []
        tickAll(&world, 60, events: &events) // arm
        let minePos = world.mines[0].positionSubunits
        // Drop an enemy right on top of the armed mine.
        let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                                    positionSubunits: Vec2i(x: minePos.x - 1024, y: minePos.y - 1024),
                                    facing: .down)
        world.withTank(entityID: enemy) { $0.spawnProtectionTicks = 0 }
        events.removeAll()
        tickAll(&world, 2, events: &events)
        #expect(world.mines.isEmpty)
        #expect(events.contains { if case .mineTriggered = $0 { true } else { false } })
        #expect((world.tank(entityID: enemy)?.armor ?? 0) < 3) // took mine damage
    }

    @Test func antiSkidCrossesLowMinesButNotLevel3() {
        var world = makeCombatWorld()
        _ = placeMine(&world) // level 0
        var events: [DomainEvent] = []
        tickAll(&world, 60, events: &events)
        let minePos = world.mines[0].positionSubunits
        let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                                    positionSubunits: Vec2i(x: minePos.x - 1024, y: minePos.y - 1024),
                                    facing: .down)
        world.withTank(entityID: enemy) { $0.spawnProtectionTicks = 0; $0.equipmentID = "anti_skid" }
        tickAll(&world, 5, events: &events)
        #expect(world.mines.count == 1) // level 0: safely crossed (§8.6)

        // Level-3 mine ignores that immunity.
        var world3 = makeCombatWorld()
        _ = placeMine(&world3, power: 3)
        events.removeAll()
        tickAll(&world3, 60, events: &events)
        let mine3Pos = world3.mines[0].positionSubunits
        let enemy3 = world3.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                                      positionSubunits: Vec2i(x: mine3Pos.x - 1024, y: mine3Pos.y - 1024),
                                      facing: .down)
        world3.withTank(entityID: enemy3) { $0.spawnProtectionTicks = 0; $0.equipmentID = "anti_skid" }
        tickAll(&world3, 2, events: &events)
        #expect(world3.mines.isEmpty) // triggered despite AntiSkid
    }

    @Test func shieldOfMoonRemovesLevelZeroMines() {
        var world = makeCombatWorld()
        _ = placeMine(&world)
        var events: [DomainEvent] = []
        tickAll(&world, 60, events: &events)
        let minePos = world.mines[0].positionSubunits
        let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                                    positionSubunits: Vec2i(x: minePos.x - 1024, y: minePos.y - 1024),
                                    facing: .down)
        world.withTank(entityID: enemy) { $0.spawnProtectionTicks = 0; $0.equipmentID = "shield_of_moon" }
        events.removeAll()
        tickAll(&world, 2, events: &events)
        #expect(world.mines.isEmpty) // removed without detonation
        #expect(!events.contains { if case .mineTriggered = $0 { true } else { false } })
        #expect(world.tank(entityID: enemy)?.armor == 3)
    }

    @Test func minePlacementOnWaterRequiresAmphi() {
        var world = makeCombatWorld { w in
            for x in 1...2 { for y in 2...4 { w.terrain[x, y] = TerrainCell(kind: .water) } }
        }
        giveSpecial(&world, "mine")
        var events: [DomainEvent] = []
        tickAll(&world, 1, special: true, events: &events) // rear cell is water
        #expect(world.mines.isEmpty)
        #expect(events.contains { if case .dryFire = $0 { true } else { false } })

        world.withTank(entityID: 1) { $0.equipmentID = "amphi_tank" }
        events.removeAll()
        tickAll(&world, 35, events: &events)
        tickAll(&world, 1, special: true, events: &events)
        #expect(world.mines.count == 1 && world.mines[0].onWater) // §8.6
    }

    @Test func plainProjectileDisarmsMine() {
        var world = makeCombatWorld()
        _ = placeMine(&world)
        var events: [DomainEvent] = []
        tickAll(&world, 60, events: &events)
        let minePos = world.mines[0].positionSubunits
        // Approach from below so the shot cannot clip the player tank first.
        _ = injectProjectile(&world, weaponID: "normal", team: 2,
                             at: Vec2i(x: minePos.x, y: minePos.y + 3000), direction: .up)
        events.removeAll()
        tickAll(&world, 30, events: &events)
        #expect(world.mines.isEmpty)
        #expect(!events.contains { if case .mineTriggered = $0 { true } else { false } }) // no blast
    }
}

@Suite struct ExplosionAndFireTests {
    @Test func explosionDamagesAreaAndChainsMinesBreadthFirst() {
        var world = makeCombatWorld { w in
            w.terrain[11, 3] = TerrainCell(kind: .brick)
            w.terrain[11, 4] = TerrainCell(kind: .brick)
        }
        giveSpecial(&world, "explosion")
        // Two level-0 mines: the projectile detonates on the first; the
        // second is only inside the FIRST mine's blast; the brick is only
        // inside the SECOND mine's blast — proving wave-by-wave chaining.
        for x in [10_240, 11_000] {
            let id = world.claimEntityID()
            world.mines.append(MineState(
                entityID: id, level: 0, ownerEntityID: -1, ownerPlayerID: nil, teamID: 2,
                positionSubunits: Vec2i(x: x, y: 4096), phase: .armed,
                phaseTicksRemaining: 0, triggerRadiusSubunits: 0, onWater: false))
        }
        var events: [DomainEvent] = []
        tickAll(&world, 1, special: true, events: &events)
        tickAll(&world, 60, events: &events)
        #expect(world.mines.isEmpty) // both chained
        let explosions = events.filter { if case .explosion = $0 { true } else { false } }
        #expect(explosions.count >= 3) // projectile + two mine waves
        #expect(world.terrain[11, 3].kind != .brick || world.terrain[11, 3].quadrantMask != 0b1111)
    }

    @Test func chainDetonationRespectsWaveCap() {
        var world = makeCombatWorld()
        giveSpecial(&world, "explosion")
        // A long daisy chain: each mine only within the previous blast radius.
        for i in 0..<12 {
            let id = world.claimEntityID()
            world.mines.append(MineState(
                entityID: id, level: 0, ownerEntityID: -1, ownerPlayerID: nil, teamID: 2,
                positionSubunits: Vec2i(x: 8192 + i * 1000, y: 4096), phase: .armed,
                phaseTicksRemaining: 0, triggerRadiusSubunits: 0, onWater: false))
        }
        var events: [DomainEvent] = []
        tickAll(&world, 1, special: true, events: &events)
        tickAll(&world, 60, events: &events)
        // Wave cap 8: the tail of a 12-mine chain must survive.
        #expect(!world.mines.isEmpty)
    }

    @Test func fireHazardRespectsTeamFilterAndInterval() {
        var world = makeCombatWorld()
        giveSpecial(&world, "fire")
        // Enemy standing on the first flame cell in front of the player.
        let enemy = spawnEnemy(&world, cellX: 5, cellY: 3)
        var events: [DomainEvent] = []
        tickAll(&world, 1, special: true, events: &events)
        #expect(!world.fireHazards.isEmpty)
        tickAll(&world, 40, events: &events)
        let enemyArmor = world.tank(entityID: enemy)?.armor ?? 0
        #expect(enemyArmor < 3) // enemy burned
        // Damage cadence: at most every 30 ticks, so ≤ 2 hits in ~41 ticks.
        #expect(enemyArmor >= 1)
        #expect(world.tanks[0].armor == 3) // player-team fire never burns the player (§8.7)
    }

    @Test func fireSpreadStopsAtWallsAndWater() {
        var world = makeCombatWorld { w in
            w.terrain[6, 3] = TerrainCell(kind: .brick)
            w.terrain[6, 4] = TerrainCell(kind: .brick)
        }
        giveSpecial(&world, "fire")
        var events: [DomainEvent] = []
        tickAll(&world, 1, special: true, events: &events)
        // Wall at cell 6 blocks the second and third patch.
        #expect(world.fireHazards.count == 1)
    }

    @Test func dryFireOnEmptyAmmo() {
        var world = makeCombatWorld()
        giveSpecial(&world, "rapid", ammo: 0)
        var events: [DomainEvent] = []
        tickAll(&world, 1, special: true, events: &events)
        #expect(events.contains { if case .dryFire(_, "rapid") = $0 { true } else { false } })
        #expect(world.projectiles.isEmpty)
    }

    @Test func invincibleTankDeflectsExplosionAndProjectiles() {
        var world = makeCombatWorld()
        let enemy = spawnEnemy(&world, cellX: 9, cellY: 3)
        world.withTank(entityID: enemy) { $0.statusEffects["invincible"] = 600 }
        giveSpecial(&world, "explosion")
        var events: [DomainEvent] = []
        tickAll(&world, 1, special: true, events: &events)
        tickAll(&world, 60, events: &events)
        #expect(world.tank(entityID: enemy)?.armor == 3)
    }
}

@Suite struct TunnelingTests {
    /// Required (§7.4): the fastest configured weapon versus a single
    /// quadrant. AP at power 3 reaches 960 subunits/tick — nearly twice the
    /// 512-subunit quadrant. Discrete sampling would tunnel; sweeps must not.
    @Test func fastestWeaponCannotTunnelThroughSingleQuadrant() {
        var world = makeCombatWorld { w in
            // One lone quadrant (top-left) at cell (20,4): y 4096..4608.
            w.terrain[20, 4] = TerrainCell(kind: .brick, quadrantMask: 0b0001)
        }
        giveSpecial(&world, "ap", power: 3)
        world.withTank(entityID: 1) { $0.positionSubunits = Vec2i(x: 3072, y: 3072 + 200) }
        var events: [DomainEvent] = []
        tickAll(&world, 1, special: true, events: &events)
        tickAll(&world, 60, events: &events)
        // The quadrant was hit (destroyed), not skipped.
        #expect(world.terrain[20, 4].quadrantMask == 0 || world.terrain[20, 4].kind == .ground)
        #expect(events.contains { if case .terrainChanged(20, 4, _) = $0 { true } else { false } })
    }

    /// Required (§7.4): crossing projectiles interact even when they would
    /// pass each other between discrete positions in a single tick.
    @Test func crossingProjectilesCollideMidFlight() {
        var world = makeCombatWorld()
        // Two fast opposing shots 400 subunits apart, closing at 640/tick:
        // they swap sides within one tick.
        _ = injectProjectile(&world, weaponID: "rapid", team: 2,
                             at: Vec2i(x: 10_000, y: 4096), direction: .left)
        _ = injectProjectile(&world, weaponID: "rapid", team: 1,
                             at: Vec2i(x: 9600, y: 4096), direction: .right)
        var events: [DomainEvent] = []
        tickAll(&world, 3, events: &events)
        #expect(world.projectiles.isEmpty) // equal durability: both destroyed
    }

    /// Required (§7.4): a mine trigger radius cannot be stepped over.
    @Test func mineTriggerRadiusCatchesFastTank() {
        var world = makeCombatWorld()
        let id = world.claimEntityID()
        world.mines.append(MineState(
            entityID: id, level: 0, ownerEntityID: -1, ownerPlayerID: nil, teamID: 2,
            positionSubunits: Vec2i(x: 8192, y: 4096), phase: .armed,
            phaseTicksRemaining: 0, triggerRadiusSubunits: 768, onWater: false))
        world.withTank(entityID: 1) { $0.speedLevel = 3 } // 96 subunits/tick
        var events: [DomainEvent] = []
        tickAll(&world, 60, direction: .right, events: &events)
        #expect(world.mines.isEmpty)
        #expect(events.contains { if case .mineTriggered = $0 { true } else { false } })
    }
}

@Suite struct CombatDeterminismTests {
    @Test func combatScriptIsDeterministicAndInvariantClean() {
        func run() -> WorldState {
            var world = makeCombatWorld { w in
                for y in 2...6 { w.terrain[12, y] = TerrainCell(kind: .brick) }
                w.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 20 * 1024, y: 10 * 1024))
            }
            _ = spawnEnemy(&world, cellX: 9, cellY: 3)
            _ = spawnEnemy(&world, cellX: 16, cellY: 12)
            giveSpecial(&world, "explosion", ammo: 20)
            var events: [DomainEvent] = []
            for tick in 0..<600 {
                let dir: Direction? = [Direction.right, .down, nil, .up][(tick / 60) % 4]
                tickAll(&world, 1, direction: dir,
                        normal: tick % 17 == 0, special: tick % 55 == 0, events: &events)
            }
            return world
        }
        let a = run(), b = run()
        #expect(a.checksum() == b.checksum())
        #expect(a == b)
        #expect(WorldInvariants.violations(in: a).isEmpty, "\(WorldInvariants.violations(in: a))")
    }
}
