import Foundation
import Testing
@testable import GameCore

/// Joint-review regressions (2026-09-09): contact ordering, penetration
/// bookkeeping, protection policy, flame/base rules, active-count exactness,
/// fort-ring occupancy, and pickup rules. Geometry base: cell = 1024, tank
/// footprint 2048, projectile half-extent 96; the player (team 1) starts at
/// cell (3,3) facing right.
private func makeWorld(_ build: (inout WorldState) -> Void = { _ in }) -> WorldState {
    var terrain = TerrainGrid(arena: .universal)
    let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
    for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
    for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
    var world = WorldState(terrain: terrain, seed: 5)
    world.addPlayer(PlayerState(playerID: .one))
    world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                    positionSubunits: Vec2i(x: 3072, y: 3072), facing: .right)
    world.withTanksInEntityOrder { $0.spawnProtectionTicks = 0 }
    build(&world)
    return world
}

private func step(_ world: inout WorldState, _ n: Int,
                  direction: Direction? = nil, normal: Bool = false, special: Bool = false,
                  weapons: WeaponRuleset = .provisional, pickups: PickupRuleset = .provisional,
                  events: inout [DomainEvent]) {
    for _ in 0..<n {
        events += Simulation.step(&world, commands: [PlayerCommand(
            playerID: .one, targetTick: world.tick, moveDirection: direction,
            normalFirePressed: normal, specialFirePressed: special)],
            weapons: weapons, pickups: pickups)
    }
}

private func giveSpecial(_ world: inout WorldState, _ weaponID: String, ammo: Int = 50, power: Int = 0) {
    if let tankID = world.player(.one)?.tankEntityID {
        world.withTank(entityID: tankID) { $0.specialWeaponID = weaponID; $0.powerLevel = power }
    }
    world.withPlayer(.one) { $0.specialAmmoByWeapon[weaponID] = ammo }
}

@discardableResult
private func spawnEnemy(_ world: inout WorldState, cellX: Int, cellY: Int,
                        facing: Direction = .left, archetype: String = "normal_a") -> Int {
    let id = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: archetype,
                             positionSubunits: Vec2i(x: cellX * 1024, y: cellY * 1024), facing: facing)
    world.withTank(entityID: id) { $0.spawnProtectionTicks = 0 }
    return id
}

private func drop(_ id: String, into world: inout WorldState, at cell: Vec2i) {
    var events: [DomainEvent] = []
    world.spawnStagePickup(id, nearCell: cell, events: &events)
    for i in world.pickups.indices { world.pickups[i].graceTicksRemaining = 0 }
}

private func inject(_ world: inout WorldState, weaponID: String, team: Int, power: Int = 0,
                    at position: Vec2i, direction: Direction, speed: Int? = nil) {
    let weapon = WeaponRuleset.provisional.weapon(weaponID)!
    let id = world.claimEntityID()
    world.projectiles.append(ProjectileState(
        entityID: id, weaponID: weaponID, ownerEntityID: -1, ownerPlayerID: nil,
        teamID: team, powerLevel: power, positionSubunits: position, direction: direction,
        speedSubunitsPerTick: speed ?? weapon.level(weapon.initialSpeedSubunitsPerTick, power),
        lifetimeRemainingTicks: weapon.level(weapon.lifetimeTicks, power),
        penetrationRemaining: weapon.level(weapon.penetrationCount, power),
        durability: weapon.level(weapon.projectileDurability, power)))
    world.projectiles.sort { $0.entityID < $1.entityID }
}

private func playerTank(_ world: WorldState) -> TankState? {
    world.player(.one)?.tankEntityID.flatMap { world.tank(entityID: $0) }
}

@Suite struct ActiveCountContractTests {
    /// A1: enemy flame patches release their slot on the EMITTER, so a fire
    /// enemy is not permanently silenced after two volleys.
    @Test func enemyFlameEmitterRegainsCapacityAfterPatchesExpire() {
        var world = makeWorld()
        let enemy = spawnEnemy(&world, cellX: 20, cellY: 10, facing: .right, archetype: "fire_a")
        world.withTank(entityID: enemy) { $0.specialWeaponID = "fire" }
        var events: [DomainEvent] = []
        func volley() {
            Combat.run(&world, firePressed: [:], aiFire: [enemy: (normal: false, special: true)],
                       movement: .provisional, weapons: .provisional, events: &events)
        }
        volley()
        #expect(world.fireHazards.count == 6)
        #expect(world.tank(entityID: enemy)?.activeProjectileCounts["fire"] == 6)
        step(&world, 50, events: &events) // cooldown clears, patches still burning
        volley()
        #expect(world.tank(entityID: enemy)?.activeProjectileCounts["fire"] == 12) // at the cap
        step(&world, 50, events: &events)
        volley()
        #expect(world.fireHazards.count == 12) // refused: cap would be exceeded (PI-05)
        step(&world, 260, events: &events) // every patch burns out
        #expect(world.fireHazards.isEmpty)
        #expect(world.tank(entityID: enemy)?.activeProjectileCounts["fire"] == nil)
        volley()
        #expect(world.fireHazards.count == 6) // capacity regained
        #expect(WorldInvariants.violations(in: world).isEmpty, "\(WorldInvariants.violations(in: world))")
    }

    /// PI-05: a projectile that expires by lifetime releases its slot like
    /// an impact does.
    @Test func lifetimeExpiryReleasesTheActiveSlot() {
        var world = makeWorld()
        var events: [DomainEvent] = []
        step(&world, 1, normal: true, events: &events)
        #expect(playerTank(world)?.activeProjectileCounts["normal"] == 1)
        world.projectiles[0].lifetimeRemainingTicks = 1
        events.removeAll()
        step(&world, 1, events: &events)
        #expect(world.projectiles.isEmpty)
        #expect(playerTank(world)?.activeProjectileCounts["normal"] == nil)
        #expect(events.contains { if case .projectileDestroyed(_, _, _, .expired) = $0 { true } else { false } })
        #expect(WorldInvariants.violations(in: world).isEmpty)
    }

    /// PI-05: a flame volley is admitted whole or refused — the per-patch
    /// count never exceeds the cap.
    @Test func flameVolleyIsRefusedWhenItWouldExceedTheCap() {
        var world = makeWorld()
        giveSpecial(&world, "fire")
        if let id = world.player(.one)?.tankEntityID {
            world.withTank(entityID: id) { $0.activeProjectileCounts["fire"] = 8 } // 8 + 6 > 12
        }
        var events: [DomainEvent] = []
        step(&world, 1, special: true, events: &events)
        #expect(world.fireHazards.isEmpty)
        #expect(events.contains { if case .dryFire = $0 { true } else { false } })
        #expect(playerTank(world)?.activeProjectileCounts["fire"] == 8)
    }

    /// A2: every dry-fire path applies the channel cooldown, so a held
    /// special button against an illegal placement dry-fires at cadence,
    /// not sixty times a second.
    @Test func heldSpecialWithIllegalMinePlacementDryFiresOnlyAtCooldownCadence() {
        var world = makeWorld { $0.terrain[2, 4] = TerrainCell(kind: .brick) } // the rear cell
        giveSpecial(&world, "mine")
        var events: [DomainEvent] = []
        step(&world, 60, special: true, events: &events)
        let dryFires = events.filter { if case .dryFire = $0 { true } else { false } }.count
        #expect(dryFires == 2) // ticks 0 and 30 (mine cooldown 30)
        #expect(world.mines.isEmpty)
        #expect(world.player(.one)?.specialAmmoByWeapon["mine"] == 50) // nothing spent
    }
}

@Suite struct ContactOrderContractTests {
    /// PI-02: a penetrating shell damages each distinct tank once and keeps
    /// the rest of its travel for the tick.
    @Test func penetratingShellHitsEachTankOnceAndKeepsTravelling() {
        var world = makeWorld { w in
            for y in 0..<27 { w.terrain[55, y] = TerrainCell(kind: .ground) } // open right edge
        }
        let enemy = spawnEnemy(&world, cellX: 9, cellY: 3)
        world.withTank(entityID: enemy) { $0.armor = 6; $0.maxArmor = 6 }
        giveSpecial(&world, "ap", power: 1) // penetration 2, tank damage 2
        var events: [DomainEvent] = []
        step(&world, 1, special: true, events: &events)
        var farthestX = 0
        for _ in 0..<200 {
            step(&world, 1, events: &events)
            if let p = world.projectiles.first { farthestX = max(farthestX, p.positionSubunits.x) }
        }
        #expect(world.tank(entityID: enemy)?.armor == 4) // exactly one hit
        let hits = events.filter { if case .tankDamaged(enemy, _, _, _, _) = $0 { true } else { false } }
        #expect(hits.count == 1)
        #expect(events.contains { if case .projectileHit(_, "ap", _, .tank) = $0 { true } else { false } })
        #expect(farthestX > 9 * 1024 + 2048) // flew on past the tank
        #expect(world.projectiles.isEmpty)
        #expect(events.contains { if case .projectileDestroyed(_, "ap", _, .boundary) = $0 { true } else { false } })
    }

    /// PI-03: two shots whose swept boxes overlap but which pass the
    /// crossing at different times of the tick do not cancel.
    @Test func crossingShotsThatPassAtDifferentTimesDoNotCancel() {
        var world = makeWorld()
        // A crosses x=24400 during τ∈(0.18,0.80); B only reaches A's row
        // after τ≈0.82 — swept AABBs overlap, moving boxes never do.
        inject(&world, weaponID: "ap", team: 1, power: 3,
               at: Vec2i(x: 24100, y: 4096), direction: .right, speed: 600)
        inject(&world, weaponID: "ap", team: 2, power: 3,
               at: Vec2i(x: 24400, y: 3400), direction: .down, speed: 600)
        var events: [DomainEvent] = []
        step(&world, 1, events: &events)
        #expect(world.projectiles.count == 2)
        #expect(!events.contains { if case .projectileDestroyed = $0 { true } else { false } })
    }

    /// PI-03: an interception earlier in the tick prevents the intercepted
    /// shell's later base impact in the same tick (global time order).
    @Test func interceptedShellCannotHitTheBaseLaterInTheSameTick() {
        var world = makeWorld {
            $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 20 * 1024, y: 10 * 1024))
        }
        // Enemy shell reaches the base edge at τ≈0.9; the player's shell
        // crosses it at τ≈0.32.
        inject(&world, weaponID: "normal", team: 2, at: Vec2i(x: 20211, y: 11264), direction: .right)
        inject(&world, weaponID: "normal", team: 1, at: Vec2i(x: 20211, y: 11010), direction: .down)
        var events: [DomainEvent] = []
        step(&world, 1, events: &events)
        #expect(world.base?.durability == 3)
        #expect(world.projectiles.isEmpty)
        #expect(events.filter { if case .projectileDestroyed(_, _, _, .projectile) = $0 { true } else { false } }.count == 2)
    }

    /// True head-on contact still cancels (regression guard for the new
    /// time-of-impact model).
    @Test func headOnShotsStillCancel() {
        var world = makeWorld()
        inject(&world, weaponID: "normal", team: 2, at: Vec2i(x: 30_000, y: 8192), direction: .left)
        inject(&world, weaponID: "normal", team: 1, at: Vec2i(x: 29_000, y: 8192), direction: .right)
        var events: [DomainEvent] = []
        step(&world, 5, events: &events)
        #expect(world.projectiles.isEmpty)
    }
}

@Suite struct ProtectionAndFlameContractTests {
    /// PI-01: invincibility and spawn protection deflect flames and the bomb
    /// exactly like projectiles and blasts.
    @Test func protectionDeflectsFlamesAndTheBomb() {
        var world = makeWorld()
        let burning = spawnEnemy(&world, cellX: 5, cellY: 3)
        world.withTank(entityID: burning) { $0.statusEffects["invincible"] = 600 }
        giveSpecial(&world, "fire")
        var events: [DomainEvent] = []
        step(&world, 1, special: true, events: &events)
        #expect(world.fireHazards.count == 6)
        step(&world, 40, events: &events)
        #expect(world.tank(entityID: burning)?.armor == 3) // untouched by flame

        let spawning = spawnEnemy(&world, cellX: 20, cellY: 10)
        world.withTank(entityID: spawning) { $0.spawnProtectionTicks = 60 }
        let exposed = spawnEnemy(&world, cellX: 30, cellY: 10)
        drop("bomb", into: &world, at: Vec2i(x: 3, y: 3))
        step(&world, 2, events: &events)
        #expect(world.tank(entityID: spawning)?.armor == 3)
        #expect(world.tank(entityID: burning)?.armor == 3)
        #expect(world.tank(entityID: exposed) == nil) // 3 damage killed it
    }

    /// PI-04: flame patches on the base structure burn it once per
    /// fire-damage interval across overlapping patches, through the
    /// ADR-0005 allied flag and the shield.
    @Test func flamesOnTheBaseBurnItOncePerInterval() {
        var world = makeWorld {
            $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 7 * 1024, y: 3 * 1024))
        }
        let enemy = spawnEnemy(&world, cellX: 10, cellY: 3, facing: .left, archetype: "fire_a")
        world.withTank(entityID: enemy) { $0.specialWeaponID = "fire" }
        var events: [DomainEvent] = []
        Combat.run(&world, firePressed: [:], aiFire: [enemy: (normal: false, special: true)],
                   movement: .provisional, weapons: .provisional, events: &events)
        #expect(world.fireHazards.count == 4) // free column + one contact patch per row
        #expect(world.base?.durability == 2) // one burn for two overlapping patches
        step(&world, 29, events: &events)
        #expect(world.base?.durability == 2) // cadence: not yet
        step(&world, 1, events: &events)
        #expect(world.base?.durability == 1)
        #expect(events.contains { if case .baseDamaged(1, 1, false) = $0 { true } else { false } })

        // Allied flame under the Casual flag: stopped by the rule.
        var casual = WeaponRuleset.provisional
        casual.alliedBaseDamage = false
        var world2 = makeWorld {
            $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 5 * 1024, y: 3 * 1024))
        }
        giveSpecial(&world2, "fire")
        events.removeAll()
        step(&world2, 40, special: true, weapons: casual, events: &events)
        #expect(world2.base?.durability == 3)
        // …and under Standard it is the player's own fault, flagged allied.
        var world3 = makeWorld {
            $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 5 * 1024, y: 3 * 1024))
        }
        giveSpecial(&world3, "fire")
        events.removeAll()
        step(&world3, 2, special: true, events: &events)
        #expect(world3.base?.durability == 2)
        #expect(events.contains { if case .baseDamaged(1, 2, true) = $0 { true } else { false } })
    }
}

@Suite struct FortRingContractTests {
    /// A3: hardening never entombs a tank; expiry restores what activation
    /// recorded (steel stays steel), skipping cells that are occupied then.
    @Test func shieldHardeningSkipsOccupiedCellsAndExpiryRestoresRecordedKinds() {
        var world = makeWorld { w in
            w.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 9 * 1024, y: 3 * 1024))
            w.terrain[11, 2] = TerrainCell(kind: .steel) // authored steel corner
            // Park the player over ring cells (8,3) and (8,4).
            if let id = w.player(.one)?.tankEntityID {
                w.withTank(entityID: id) { $0.positionSubunits = Vec2i(x: 7 * 1024, y: 3 * 1024) }
            }
        }
        #expect(Stage.baseFortRingCells(world).count == 12)
        // The ADR-0010 mapping (default since decision B): recorded steel returns as steel.
        var rules = PickupRuleset.provisional
        rules.fortRingRestoresRecordedKinds = true
        drop("base_shield", into: &world, at: Vec2i(x: 7, y: 3))
        var events: [DomainEvent] = []
        step(&world, 1, pickups: rules, events: &events)
        #expect((world.base?.shieldRemainingTicks ?? 0) > 0)
        #expect(world.terrain[9, 2].kind == .steel)
        #expect(world.terrain[10, 5].kind == .steel)
        #expect(world.terrain[11, 2].kind == .steel)
        #expect(world.terrain[8, 3].kind == .ground) // occupied: skipped
        #expect(world.terrain[8, 4].kind == .ground)
        #expect(world.base?.fortRingRestore.count == 12)
        // The player is not entombed.
        let before = playerTank(world)!.positionSubunits.x
        step(&world, 10, direction: .left, pickups: rules, events: &events)
        #expect(playerTank(world)!.positionSubunits.x < before)

        world.base?.shieldRemainingTicks = 1
        step(&world, 1, pickups: rules, events: &events)
        #expect(world.base?.shieldRemainingTicks == 0)
        #expect(world.terrain[11, 2].kind == .steel) // recorded steel restored as steel
        #expect(world.terrain[9, 2].kind == .brick) // recorded ground rebuilt as brick
        #expect(world.terrain[10, 5].kind == .brick)
        #expect(world.terrain[8, 3].kind == .ground) // still occupied: skipped, no retry
        #expect(world.base?.fortRingRestore.isEmpty == true)
        #expect(events.contains { if case .baseShieldChanged(false) = $0 { true } else { false } })
    }

    /// A3: a refresh while shielded keeps the original record.
    @Test func shieldRefreshKeepsTheActivationRecord() {
        var world = makeWorld {
            $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 20 * 1024, y: 10 * 1024))
        }
        drop("base_shield", into: &world, at: Vec2i(x: 3, y: 3))
        var events: [DomainEvent] = []
        step(&world, 1, events: &events)
        let record = world.base?.fortRingRestore
        #expect(record?.allSatisfy { $0 == .ground } == true)
        drop("base_shield", into: &world, at: Vec2i(x: 3, y: 3))
        step(&world, 1, events: &events)
        #expect(world.base?.fortRingRestore == record) // not re-recorded as steel
    }
}

@Suite struct HiddenTreasureContractTests {
    private func stageWorld(_ build: (inout WorldState) -> Void) -> WorldState {
        makeWorld { w in
            w.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 9 * 1024, y: 3 * 1024))
            w.stage = StageState(spawnQueue: ["normal_a"], maxAliveEnemies: 1,
                                 enemyStartDelayTicks: 999_999,
                                 spawnPointsCells: [Vec2i(x: 40, y: 1)],
                                 playerRespawnCell: Vec2i(x: 3, y: 3), dropTable: [])
            build(&w)
        }
    }

    /// A4: a covering brick that hardens to steel keeps the treasure hidden;
    /// only a cell that stopped blocking reveals it.
    @Test func hiddenTreasureStaysHiddenWhenItsBrickHardensToSteel() {
        var world = stageWorld { w in
            w.terrain[9, 2] = TerrainCell(kind: .brick)
            w.stage?.hiddenPickups = [HiddenPickup(cell: Vec2i(x: 9, y: 2), pickupID: "speed_up")]
        }
        drop("base_shield", into: &world, at: Vec2i(x: 3, y: 3))
        var events: [DomainEvent] = []
        step(&world, 3, events: &events)
        #expect(world.terrain[9, 2].kind == .steel)
        #expect(world.stage?.hiddenPickups.count == 1)
        #expect(!world.pickups.contains { $0.pickupID == "speed_up" })
        world.terrain[9, 2] = TerrainCell(kind: .ground)
        step(&world, 1, events: &events)
        #expect(world.pickups.contains { $0.pickupID == "speed_up" })
        #expect(world.stage?.hiddenPickups.isEmpty == true)
    }

    /// A4: the record is consumed only when the pickup was actually placed.
    @Test func unplaceableTreasureIsRetriedLater() {
        var world = stageWorld { w in
            for x in 16...24 { for y in 6...14 { w.terrain[x, y] = TerrainCell(kind: .steel) } }
            w.terrain[20, 10] = TerrainCell(kind: .brick)
            w.stage?.hiddenPickups = [HiddenPickup(cell: Vec2i(x: 20, y: 10), pickupID: "extra_life")]
        }
        var events: [DomainEvent] = []
        world.terrain[20, 10] = TerrainCell(kind: .ground)
        // Another pickup already sits on the only free cell in range.
        let blocker = world.claimEntityID()
        world.pickups.append(PickupState(entityID: blocker, pickupID: "speed_up",
                                         positionSubunits: Vec2i(x: 20 * 1024 + 512, y: 10 * 1024 + 512)))
        step(&world, 2, events: &events)
        #expect(!world.pickups.contains { $0.pickupID == "extra_life" })
        #expect(world.stage?.hiddenPickups.count == 1) // retained
        world.pickups.removeAll { $0.entityID == blocker }
        step(&world, 1, events: &events)
        #expect(world.pickups.contains { $0.pickupID == "extra_life" })
        #expect(world.stage?.hiddenPickups.isEmpty == true)
    }
}

@Suite struct PickupRuleContractTests {
    /// PI-11: MAX armor/ammo fills the current special weapon to its cap;
    /// the crate adds one refill.
    @Test func maxArmorAmmoFillsTheCapWhileTheCrateRefillsOnce() {
        var world = makeWorld()
        world.withPlayer(.one) { $0.specialAmmoByWeapon["rapid"] = 5 }
        drop("max_armor_ammo", into: &world, at: Vec2i(x: 3, y: 3))
        var events: [DomainEvent] = []
        step(&world, 1, events: &events)
        #expect(playerTank(world)?.armor == 8)
        #expect(world.player(.one)?.specialAmmoByWeapon["rapid"] == 250)
        world.withPlayer(.one) { $0.specialAmmoByWeapon["rapid"] = 5 }
        drop("ammo_crate", into: &world, at: Vec2i(x: 3, y: 3))
        step(&world, 1, events: &events)
        #expect(world.player(.one)?.specialAmmoByWeapon["rapid"] == 55)
    }

    /// B3: score pickups award their value exactly once.
    @Test func scorePickupsAwardTheirValue() {
        var world = makeWorld()
        drop("score_500", into: &world, at: Vec2i(x: 3, y: 3))
        var events: [DomainEvent] = []
        step(&world, 2, events: &events)
        #expect(world.player(.one)?.score == 500)
        #expect(events.filter { if case .scoreChanged(500) = $0 { true } else { false } }.count == 1)
        #expect(world.pickups.isEmpty)
    }

    /// B2: invincibility timing is ruleset data; the provisional default is
    /// the M3 behaviour, the reference rule is available without code.
    @Test func invincibilityRuleIsRulesetData() {
        let provisional = PickupRuleset.provisional
        #expect(provisional.invincibilityTicks(afterPickupWith: 0) == 600)
        #expect(provisional.invincibilityTicks(afterPickupWith: 300) == 600)
        let reference = PickupRuleset.referenceInvincibility
        #expect(reference.invincibilityTicks(afterPickupWith: 0) == 1500)
        #expect(reference.invincibilityTicks(afterPickupWith: 750) == 1500)
        #expect(reference.invincibilityTicks(afterPickupWith: 751) == 1501)

        var world = makeWorld()
        drop("invincibility", into: &world, at: Vec2i(x: 3, y: 3))
        var events: [DomainEvent] = []
        step(&world, 1, pickups: reference, events: &events)
        #expect(playerTank(world)?.statusEffects["invincible"] == 1500)
    }
}

@Suite struct ReviewRefinementTests {
    /// Round-2 refinement: a cached contact whose target died earlier in the
    /// tick is stale, not a hit — a second shell passes the corpse.
    @Test func shellDoesNotDieOnATankKilledEarlierInTheSameTick() {
        var world = makeWorld { w in
            for y in 0..<27 { w.terrain[55, y] = TerrainCell(kind: .ground) }
        }
        let enemy = spawnEnemy(&world, cellX: 12, cellY: 3)
        world.withTank(entityID: enemy) { $0.armor = 1; $0.maxArmor = 1 }
        // Two team-1 shells in file; both would reach the tank this tick.
        inject(&world, weaponID: "normal", team: 1, at: Vec2i(x: 12 * 1024 - 150, y: 4096), direction: .right)
        inject(&world, weaponID: "normal", team: 1, at: Vec2i(x: 12 * 1024 - 250, y: 4096), direction: .right)
        var events: [DomainEvent] = []
        step(&world, 1, events: &events)
        #expect(world.tank(entityID: enemy) == nil)
        #expect(world.projectiles.count == 1) // the second shell flew on
        #expect(world.projectiles.first!.positionSubunits.x > 12 * 1024 - 250)
        #expect(events.filter { if case .tankDamaged = $0 { true } else { false } }.count == 1)
    }

    /// Round-2 refinement: the recorded owner rule rebuilds every unoccupied
    /// ring cell as brick; preserving recorded steel/water is the proposed
    /// ADR-0010 mapping and stays opt-in ruleset data.
    @Test func fortRingRestorationMappingIsRulesetData() {
        func run(_ rules: PickupRuleset) -> WorldState {
            var world = makeWorld { w in
                w.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 20 * 1024, y: 10 * 1024))
                w.terrain[19, 9] = TerrainCell(kind: .steel)
                w.terrain[22, 12] = TerrainCell(kind: .water)
            }
            drop("base_shield", into: &world, at: Vec2i(x: 3, y: 3))
            var events: [DomainEvent] = []
            step(&world, 1, pickups: rules, events: &events)
            #expect(world.terrain[19, 9].kind == .steel)
            #expect(world.terrain[22, 12].kind == .steel) // water hardened too
            world.base?.shieldRemainingTicks = 1
            step(&world, 1, pickups: rules, events: &events)
            return world
        }
        // Default (owner decision B, ADR-0010 accepted 2026-09-10): recorded
        // steel and water come back as themselves; other cells become brick.
        let recorded = run(.provisional)
        #expect(PickupRuleset.provisional.fortRingRestoresRecordedKinds)
        #expect(recorded.terrain[19, 9].kind == .steel)
        #expect(recorded.terrain[22, 12].kind == .water)
        #expect(recorded.terrain[20, 9].kind == .brick)
        // The unconditional-brick mapping stays available as data.
        var brickOnly = PickupRuleset.provisional
        brickOnly.fortRingRestoresRecordedKinds = false
        let unconditional = run(brickOnly)
        #expect(unconditional.terrain[19, 9].kind == .brick)
        #expect(unconditional.terrain[22, 12].kind == .brick)
    }

    /// Round-2 refinement: a deflected flame contact (shield up) consumes no
    /// burn cadence — the base burns the tick the shield drops.
    @Test func shieldedBaseContactConsumesNoBurnCadence() {
        var world = makeWorld {
            $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 7 * 1024, y: 3 * 1024),
                                shieldRemainingTicks: 20)
        }
        let enemy = spawnEnemy(&world, cellX: 10, cellY: 3, facing: .left, archetype: "fire_a")
        world.withTank(entityID: enemy) { $0.specialWeaponID = "fire" }
        var events: [DomainEvent] = []
        Combat.run(&world, firePressed: [:], aiFire: [enemy: (normal: false, special: true)],
                   movement: .provisional, weapons: .provisional, events: &events)
        #expect(world.base?.durability == 3)
        #expect(world.base?.burnCooldownTicks == 0)
        step(&world, 20, events: &events) // shield expires on the last of these
        #expect(world.base?.shieldRemainingTicks == 0)
        step(&world, 1, events: &events)
        #expect(world.base?.durability == 2)
    }

    /// Round-2 refinement: flames reach the base from above as well.
    @Test func flamesFiredDownwardReachTheBase() {
        var world = makeWorld {
            $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 20 * 1024, y: 10 * 1024))
        }
        let enemy = spawnEnemy(&world, cellX: 20, cellY: 6, facing: .down, archetype: "fire_a")
        world.withTank(entityID: enemy) { $0.specialWeaponID = "fire" }
        var events: [DomainEvent] = []
        Combat.run(&world, firePressed: [:], aiFire: [enemy: (normal: false, special: true)],
                   movement: .provisional, weapons: .provisional, events: &events)
        #expect(world.base?.durability == 2)
    }

    /// Ruleset bounds are validated as content (§15.3).
    @Test func pickupRulesetValidatesItsBounds() {
        #expect(PickupRuleset.provisional.validationIssues().isEmpty)
        #expect(PickupRuleset.referenceInvincibility.validationIssues().isEmpty)
        var broken = PickupRuleset.provisional
        broken.pickupGraceTicks = 5000
        broken.freezeTicks = 0
        #expect(broken.validationIssues().count == 2)
    }
}

@Suite struct RoundThreeRegressionTests {
    /// R3-01: a mirrored shot meets a wall at the same distance in all four
    /// directions — the entered quadrant is sampled, not the one left.
    @Test func wallContactIsSymmetricInAllFourDirections() {
        struct Case { let from: Vec2i; let direction: Direction; let wallCell: (Int, Int); let expected: Int }
        // Steel cell (8,10): x 8192…9216, y 10240…11264. Half-extent 96.
        let cases: [Case] = [
            Case(from: Vec2i(x: 9316, y: 10496), direction: .left, wallCell: (8, 10), expected: 9312),  // edge 9216 + 96
            Case(from: Vec2i(x: 8092, y: 10496), direction: .right, wallCell: (8, 10), expected: 8096), // edge 8192 - 96
            Case(from: Vec2i(x: 8448, y: 11364), direction: .up, wallCell: (8, 10), expected: 11360),   // edge 11264 + 96
            Case(from: Vec2i(x: 8448, y: 10140), direction: .down, wallCell: (8, 10), expected: 10144), // edge 10240 - 96
        ]
        for c in cases {
            var world = makeWorld { $0.terrain[c.wallCell.0, c.wallCell.1] = TerrainCell(kind: .steel) }
            inject(&world, weaponID: "normal", team: 2, at: c.from, direction: c.direction)
            var events: [DomainEvent] = []
            step(&world, 1, events: &events)
            #expect(world.projectiles.isEmpty, "\(c.direction) survived")
            let end = events.compactMap { event -> Vec2i? in
                if case .projectileDestroyed(_, _, let position, .steel) = event { return position }
                return nil
            }.first
            let axis = c.direction == .left || c.direction == .right ? end?.x : end?.y
            #expect(axis == c.expected, "\(c.direction): \(String(describing: end))")
        }
    }

    /// R3-01: a lone remaining quadrant is met from the negative side too.
    @Test func singleQuadrantIsMetFromTheLeft() {
        var world = makeWorld { $0.terrain[20, 4] = TerrainCell(kind: .brick, quadrantMask: 0b0010) } // top-right quadrant
        // Quadrant x 20992…21504, y 4096…4608. Shot leftward along y=4300.
        inject(&world, weaponID: "normal", team: 2, at: Vec2i(x: 21700, y: 4300), direction: .left)
        var events: [DomainEvent] = []
        step(&world, 2, events: &events)
        #expect(world.terrain[20, 4].quadrantMask != 0b0010 || world.terrain[20, 4].kind == .ground)
        #expect(events.contains { if case .projectileDestroyed(_, _, _, .brick) = $0 { true } else { false } })
    }

    /// R3-01: a wall contact earlier in the tick wins over a later
    /// interception — for a leftward shell as for a rightward one.
    @Test func wallContactPrecedesALaterInterceptionForNegativeDirections() {
        var world = makeWorld { $0.terrain[8, 10] = TerrainCell(kind: .steel) }
        // Leftward enemy shell meets the steel after 4 subunits; a player
        // shell would cross its path later in the tick.
        inject(&world, weaponID: "normal", team: 2, at: Vec2i(x: 9316, y: 10496), direction: .left)
        inject(&world, weaponID: "normal", team: 1, at: Vec2i(x: 9400, y: 10496 + 400), direction: .up)
        var events: [DomainEvent] = []
        step(&world, 1, events: &events)
        #expect(events.contains { if case .projectileDestroyed(_, _, _, .steel) = $0 { true } else { false } })
        #expect(world.projectiles.count == 1) // the interceptor flew on
    }

    /// R3-02: projectile-versus-mine geometry uses the ruleset's hardware
    /// extent like every other mine query.
    @Test func mineContactUsesTheConfiguredHardwareExtent() {
        var small = WeaponRuleset.provisional
        small.mineHalfExtentSubunits = 128
        var world = makeWorld()
        let id = world.claimEntityID()
        world.mines.append(MineState(entityID: id, level: 0, ownerEntityID: -1, ownerPlayerID: nil,
                                     teamID: 2, positionSubunits: Vec2i(x: 20480, y: 10240),
                                     phase: .armed, phaseTicksRemaining: 0, triggerRadiusSubunits: 0,
                                     onWater: false))
        // Cross-axis separation 300 > 128 + 96: a miss with the small extent,
        // a hit with the default 256.
        inject(&world, weaponID: "normal", team: 1, at: Vec2i(x: 20100, y: 10540), direction: .right)
        var events: [DomainEvent] = []
        var miss = world
        step(&miss, 2, weapons: small, events: &events)
        #expect(miss.mines.count == 1 && miss.projectiles.count == 1)
        var hit = world
        step(&hit, 2, events: &events)
        #expect(hit.mines.isEmpty)
    }

    /// R3-03: hardening rebuilds damaged steel ring cells whole.
    @Test func hardeningRebuildsDamagedSteelCells() {
        var world = makeWorld { w in
            w.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 20 * 1024, y: 10 * 1024))
            w.terrain[19, 9] = TerrainCell(kind: .steel, quadrantMask: 0b0001)
        }
        drop("base_shield", into: &world, at: Vec2i(x: 3, y: 3))
        var events: [DomainEvent] = []
        step(&world, 1, events: &events)
        #expect(world.terrain[19, 9] == TerrainCell(kind: .steel))
        #expect(events.contains { if case .terrainChanged(19, 9, 0b1111) = $0 { true } else { false } })
    }

    /// R3-05: a base already at zero takes no further damage, emits no
    /// event, and consumes no burn cadence — the killing blow is the last
    /// word, whichever team fires next.
    @Test func destroyedBaseTakesNoFurtherDamage() {
        var world = makeWorld {
            $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 20 * 1024, y: 10 * 1024), durability: 1)
        }
        // Enemy shell kills the base early in the tick; the player's shell
        // arrives later in the same tick.
        inject(&world, weaponID: "normal", team: 2, at: Vec2i(x: 20480 - 96 - 20, y: 11264), direction: .right)
        inject(&world, weaponID: "normal", team: 1, at: Vec2i(x: 20480 - 96 - 150, y: 11000), direction: .right)
        var events: [DomainEvent] = []
        step(&world, 1, events: &events)
        let hits = events.filter { if case .baseDamaged = $0 { true } else { false } }
        #expect(hits.count == 1)
        #expect(events.contains { if case .baseDamaged(1, 0, false) = $0 { true } else { false } })
        #expect(world.base?.burnCooldownTicks == 0)
    }

    /// Open-1: the base admits one contact patch per column; flames never
    /// pass through to the far side.
    @Test func flamesStopAtTheBaseAfterTheContactPatch() {
        var world = makeWorld {
            $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 20 * 1024, y: 10 * 1024))
        }
        // Flush against the base's left edge, facing right: cells 20,21 are
        // the base; only 20 receives a patch, 21 and 22 do not.
        let enemy = spawnEnemy(&world, cellX: 18, cellY: 10, facing: .right, archetype: "fire_a")
        world.withTank(entityID: enemy) { $0.specialWeaponID = "fire" }
        var events: [DomainEvent] = []
        Combat.run(&world, firePressed: [:], aiFire: [enemy: (normal: false, special: true)],
                   movement: .provisional, weapons: .provisional, events: &events)
        let columns = Set(world.fireHazards.map { $0.positionSubunits.x / 1024 })
        #expect(columns == [20])
        #expect(world.base?.durability == 2)
        // A target behind the base is untouched.
        let behind = spawnEnemy(&world, cellX: 22, cellY: 10)
        world.withTank(entityID: behind) { $0.teamID = 1 }
        step(&world, 40, events: &events)
        #expect(world.tank(entityID: behind)?.armor == 3)
    }

    /// Open-1: firing upward and flush from every side still burns the base.
    @Test func flamesReachTheBaseFromEveryDirection() {
        for (cell, facing) in [((20, 12), Direction.up), ((20, 6), .down), ((16, 10), .right), ((22, 10), .left)] {
            var world = makeWorld {
                $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 20 * 1024, y: 10 * 1024))
            }
            let enemy = spawnEnemy(&world, cellX: cell.0, cellY: cell.1, facing: facing, archetype: "fire_a")
            world.withTank(entityID: enemy) { $0.specialWeaponID = "fire" }
            var events: [DomainEvent] = []
            Combat.run(&world, firePressed: [:], aiFire: [enemy: (normal: false, special: true)],
                       movement: .provisional, weapons: .provisional, events: &events)
            #expect(world.base?.durability == 2, "facing \(facing)")
        }
    }

    /// Whole-volley admission with real owned patches: a rejected volley
    /// leaves ammo, entity IDs, hazards and counts untouched.
    @Test func rejectedVolleyMutatesNothingButCooldown() {
        var world = makeWorld()
        giveSpecial(&world, "fire", ammo: 30)
        var events: [DomainEvent] = []
        step(&world, 1, special: true, events: &events)
        step(&world, 50, events: &events) // cooldown clears; 6 patches alive
        #expect(world.fireHazards.count == 6)
        // Bring the count to 8 with two more real patches of the same volley
        // shape: fire again would exceed 12 (8 + 6), so refuse.
        world.withTank(entityID: 1) { $0.activeProjectileCounts["fire"] = 8 }
        for i in 0..<2 {
            let id = world.claimEntityID()
            world.fireHazards.append(FireHazardState(entityID: id, ownerEntityID: 1, ownerPlayerID: .one,
                                                     teamID: 1, filter: .enemyOnly,
                                                     positionSubunits: Vec2i(x: (30 + i) * 1024 + 512, y: 10 * 1024 + 512),
                                                     lifetimeRemainingTicks: 200, damagePerTouch: 1))
        }
        #expect(WorldInvariants.violations(in: world).isEmpty)
        let ammoBefore = world.player(.one)?.specialAmmoByWeapon["fire"]
        let nextIDBefore = world.nextEntityID
        events.removeAll()
        step(&world, 1, special: true, events: &events)
        #expect(events.contains { if case .dryFire = $0 { true } else { false } })
        #expect(world.player(.one)?.specialAmmoByWeapon["fire"] == ammoBefore)
        #expect(world.nextEntityID == nextIDBefore + 0)
        #expect(world.fireHazards.count == 8)
        #expect(playerTank(world)?.activeProjectileCounts["fire"] == 8)
    }

    /// R3-04: extreme configuration values are rejected at the boundary and
    /// timer arithmetic never overflows.
    @Test func extremeRulesAreRejectedAndTimersSaturate() {
        var extreme = PickupRuleset.provisional
        extreme.armorUpAmount = Int.max
        extreme.baseShieldExtendTicks = Int.max
        extreme.invincibilityFloorTicks = 1
        extreme.invincibilityRefreshBelowTicks = 100
        let issues = extreme.validationIssues()
        #expect(issues.contains { $0.contains("armor_up_amount") })
        #expect(issues.contains { $0.contains("base_shield_extend_ticks") })
        #expect(issues.contains { $0.contains("floor must be at least") })
        // Saturation guards the arithmetic even for an unvalidated value.
        #expect(extreme.baseShieldTicks(afterPickupWith: 10) == Int.max)
        // A longer running timer is never shortened (documented).
        #expect(PickupRuleset.provisional.invincibilityTicks(afterPickupWith: 600) == 600)
        #expect(PickupRuleset.provisional.invincibilityTicks(afterPickupWith: 601) == 601)
    }

    /// Populated-state round trip (ADR-0003): AP still inside a penetrated
    /// tank, a shield about to restore the ring, flames whose emitter dies
    /// — serialize, restore, continue, and match the uninterrupted run.
    @Test func populatedWorldSurvivesSerializeRestoreResume() throws {
        func build() -> WorldState {
            var world = makeWorld { w in
                w.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 20 * 1024, y: 10 * 1024))
                for y in 0..<27 { w.terrain[55, y] = TerrainCell(kind: .ground) }
            }
            let tough = spawnEnemy(&world, cellX: 9, cellY: 3)
            world.withTank(entityID: tough) { $0.armor = 6; $0.maxArmor = 6 }
            let flamer = spawnEnemy(&world, cellX: 30, cellY: 10, facing: .left, archetype: "fire_a")
            world.withTank(entityID: flamer) { $0.specialWeaponID = "fire"; $0.armor = 1; $0.maxArmor = 1 }
            giveSpecial(&world, "ap", power: 1)
            drop("base_shield", into: &world, at: Vec2i(x: 3, y: 3))
            var events: [DomainEvent] = []
            Combat.run(&world, firePressed: [:], aiFire: [flamer: (normal: false, special: true)],
                       movement: .provisional, weapons: .provisional, events: &events)
            step(&world, 1, special: true, events: &events) // AP away, shield collected
            step(&world, 24, events: &events) // AP has penetrated and sits inside the tough tank
            world.withTank(entityID: flamer) { $0.armor = 0 } // emitter dies with flames alive
            world.base?.shieldRemainingTicks = 30 // restoration imminent
            return world
        }
        var interrupted = build()
        #expect(interrupted.projectiles.first?.hitTankIDs.isEmpty == false)
        let data = try JSONEncoder().encode(interrupted)
        var restored = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(restored == interrupted)
        var uninterrupted = build()
        var events: [DomainEvent] = []
        step(&interrupted, 1, events: &events)
        step(&restored, 300, events: &events)
        step(&uninterrupted, 300, events: &events)
        #expect(restored.checksum() == uninterrupted.checksum())
        #expect(restored == uninterrupted)
        #expect(WorldInvariants.violations(in: restored).isEmpty, "\(WorldInvariants.violations(in: restored))")
        #expect(restored.base?.fortRingRestore.isEmpty == true) // restoration ran
    }
}
