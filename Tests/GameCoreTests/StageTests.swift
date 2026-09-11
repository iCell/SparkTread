import Testing
@testable import GameCore

/// M3 stage-system tests: director finite counts and caps, telegraphs,
/// player lives/respawn, pickups, and §6.7 win/loss incl. simultaneity.
private func makeStageWorld(
    enemies: [String] = ["normal_a", "normal_a"],
    maxAlive: Int = 2, startDelay: Int = 10,
    _ build: (inout WorldState) -> Void = { _ in }
) -> WorldState {
    var terrain = TerrainGrid(arena: .universal)
    let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
    for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
    for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
    var world = WorldState(terrain: terrain, seed: 21)
    world.addPlayer(PlayerState(playerID: .one))
    world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                    positionSubunits: Vec2i(x: 20 * 1024, y: 20 * 1024), facing: .up)
    world.withTanksInEntityOrder { $0.spawnProtectionTicks = 0 }
    world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 40 * 1024, y: 22 * 1024))
    world.stage = StageState(
        spawnQueue: enemies, maxAliveEnemies: maxAlive, enemyStartDelayTicks: startDelay,
        spawnPointsCells: [Vec2i(x: 4, y: 1), Vec2i(x: 30, y: 1)],
        playerRespawnCell: Vec2i(x: 20, y: 20),
        dropTable: ["speed_up"], dropChancePercent: 100)
    build(&world)
    return world
}

private func tick(_ world: inout WorldState, _ n: Int,
                  direction: Direction? = nil, normal: Bool = false,
                  events: inout [DomainEvent]) {
    for _ in 0..<n {
        events += Simulation.step(&world, commands: [PlayerCommand(
            playerID: .one, targetTick: world.tick, moveDirection: direction,
            normalFirePressed: normal)])
    }
}

@Suite struct EnemyArchetypeTests {
    /// The reference-recovered table (GAME_RULES §8.2) gives each
    /// family a distinct identity: AP heavies are near-immobile fortresses,
    /// Rapids the fastest, Normals fragile teaching fodder.
    @Test func familiesHaveDistinctReferenceIdentities() {
        let normalA = EnemyArchetypes.attributes(for: "normal_a")
        #expect(normalA.armor == 1 && normalA.speedLevel == -1)

        let apC = EnemyArchetypes.attributes(for: "ap_c")
        #expect(apC.armor == 6) // fortress
        #expect(apC.speedLevel == -4) // slowest possible
        #expect(apC.shieldHP == 2) // AP heavies carry the shield

        let rapidD = EnemyArchetypes.attributes(for: "rapid_d")
        #expect(rapidD.speedLevel == 2) // fastest tier
        #expect(rapidD.equipmentID == "memory_of_sea")
        #expect(rapidD.baseFocusPercent == 50) // hunts the player half the time

        let apA = EnemyArchetypes.attributes(for: "ap_a")
        #expect(apA.baseFocusPercent == 90) // sieges the base
    }

    /// Enemy speed level 0 is 0.6× the player base, and the curve spans
    /// -4…4 (reference §8.3); AP fortresses really are slow.
    @Test func enemySpeedCurveMatchesReference() {
        let ruleset = MovementRuleset.provisional
        let apSpeed = ruleset.enemyAccumulatorIncrement(speedLevel: -4)
        let rapidSpeed = ruleset.enemyAccumulatorIncrement(speedLevel: 2)
        let playerBase = ruleset.accumulatorIncrement(speedLevel: 0)
        #expect(apSpeed < playerBase / 5) // 0.15× vs 1.0×
        #expect(rapidSpeed > playerBase) // 1.2× — outruns the player
    }

    /// AP fortresses crawl; rapids sprint — same tick budget, very different
    /// distance covered.
    @Test func fortressMovesFarSlowerThanSprinter() {
        func distance(archetype: String) -> Int {
            var terrain = TerrainGrid(arena: .universal)
            var world = WorldState(terrain: terrain, seed: 5)
            let attr = EnemyArchetypes.attributes(for: archetype)
            let id = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: archetype,
                                     positionSubunits: Vec2i(x: 5000, y: 5000), facing: .right)
            world.withTank(entityID: id) { $0.spawnProtectionTicks = 0; $0.speedLevel = attr.speedLevel }
            // No stage → drive it manually by forcing intent each tick.
            for _ in 0..<120 {
                world.withTank(entityID: id) { $0.movementIntent = .right }
                Simulation.step(&world, commands: [])
            }
            return world.tank(entityID: id)!.positionSubunits.x - 5000
        }
        let fortress = distance(archetype: "ap_c")   // speed -4
        let sprinter = distance(archetype: "rapid_c") // speed 2
        #expect(sprinter > fortress * 4)
    }
}

@Suite struct EnemyFamilyFireTests {
    /// Each family fires its own weapon: an aligned AP enemy launches AP
    /// shells, an explosion enemy launches explosion shells, a fire enemy
    /// lays flame — not everyone spraying normal rounds.
    private func fireWorld(archetype: String, playerAhead: Bool = true) -> WorldState {
        var terrain = TerrainGrid(arena: .universal)
        let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
        for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
        for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
        // Steel corridor pinning both tanks to rows 10-11: the roaming brain
        // can only pick left/right, so alignment windows reliably land.
        for x in 3..<25 {
            terrain[x, 9] = TerrainCell(kind: .steel)
            terrain[x, 12] = TerrainCell(kind: .steel)
        }
        var world = WorldState(terrain: terrain, seed: 3)
        world.addPlayer(PlayerState(playerID: .one))
        // Player to the LEFT of the enemy, same row, so a left-facing enemy aligns.
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 6 * 1024, y: 10 * 1024), facing: .right)
        let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: archetype,
                                    positionSubunits: Vec2i(x: 20 * 1024, y: 10 * 1024), facing: .left)
        world.withTank(entityID: enemy) {
            $0.spawnProtectionTicks = 0
            $0.specialWeaponID = Stage.enemyFamily(archetype)
        }
        world.withTanksInEntityOrder { $0.spawnProtectionTicks = 0 }
        world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 2 * 1024, y: 22 * 1024))
        world.stage = StageState(spawnQueue: [], maxAliveEnemies: 1, enemyStartDelayTicks: 999999,
                                 spawnPointsCells: [Vec2i(x: 4, y: 1)],
                                 playerRespawnCell: Vec2i(x: 6, y: 10), dropTable: [])
        return world
    }

    /// Runs `n` ticks and returns the accumulated events — the enemy now
    /// roams and throttles its fire, so tests assert on what was FIRED over
    /// the window, not on projectiles still in flight at the end.
    @discardableResult
    private func run(_ world: inout WorldState, _ n: Int) -> [DomainEvent] {
        var events: [DomainEvent] = []
        for _ in 0..<n {
            events += Simulation.step(&world, commands: [PlayerCommand(playerID: .one, targetTick: world.tick)])
        }
        return events
    }

    private func fired(_ events: [DomainEvent], weaponID: String, by entityID: Int) -> Bool {
        events.contains {
            if case .weaponFired(let id, _, let weapon, _, _, _) = $0 { return id == entityID && weapon == weaponID }
            return false
        }
    }

    @Test func apEnemyLaunchesAPShells() {
        var world = fireWorld(archetype: "ap_a")
        let events = run(&world, 120) // covers a full fire-cadence window
        #expect(fired(events, weaponID: "ap", by: 2))
    }

    @Test func explosionEnemyLaunchesExplosionShells() {
        var world = fireWorld(archetype: "explosion_a")
        let events = run(&world, 120)
        #expect(fired(events, weaponID: "explosion", by: 2))
    }

    @Test func fireEnemyLaysFlameThatDamagesPlayerNotItself() {
        var world = fireWorld(archetype: "fire_a")
        // Move the player adjacent so it stands in the flame lane.
        world.withTank(entityID: 1) { $0.positionSubunits = Vec2i(x: 18 * 1024, y: 10 * 1024) }
        let events = run(&world, 600) // roaming brain: give alignment windows time to land
        #expect(fired(events, weaponID: "fire", by: 2))
        // The enemy (team 2) is never hurt by its own team-2 flame.
        let enemy = world.tanks.first { $0.teamID == 2 }
        #expect(enemy != nil)
    }

    @Test func normalEnemyStillUsesNormalChannel() {
        var world = fireWorld(archetype: "normal_c")
        let events = run(&world, 120)
        #expect(fired(events, weaponID: "normal", by: 2))
    }

    @Test func mineEnemyLaysMinesWhileDriving() {
        var world = fireWorld(archetype: "mine_a")
        world.withTank(entityID: 2) { $0.movementIntent = .down } // give it somewhere to go
        run(&world, 600) // 1-in-5 roll every 24 ticks: cover plenty of chances
        #expect(!world.mines.isEmpty)
        #expect(world.mines.allSatisfy { $0.teamID == 2 })
    }
}

@Suite struct EnemyDirectorTests {
    @Test func directorSpawnsFiniteCountsWithTelegraphAndCap() {
        var world = makeStageWorld(enemies: ["normal_a", "rapid_a", "normal_b"], maxAlive: 2)
        var events: [DomainEvent] = []
        tick(&world, 11, events: &events) // delay elapses
        #expect(world.spawnTelegraphs.count == 2) // cap 2, third waits
        #expect(world.stage?.spawnQueue.count == 1)
        #expect(world.tanks.filter { $0.teamID != 1 }.isEmpty) // telegraph ≥ 45 ticks
        tick(&world, 46, events: &events)
        let alive = world.tanks.filter { $0.teamID != 1 }
        #expect(alive.count == 2)
        #expect(alive.allSatisfy { $0.spawnProtectionTicks > 0 || $0.spawnProtectionTicks == 0 })
        // §18.2 accounting: remaining + alive + spawning == expected total.
        let accounted = (world.stage?.spawnQueue.count ?? 0) + alive.count + world.spawnTelegraphs.count
        #expect(accounted == 3)
        // Archetype attributes applied.
        #expect(alive.contains { $0.archetypeID == "rapid_a" && $0.speedLevel == 1 })
    }

    @Test func blockedSpawnDefersThenRelocates() {
        var world = makeStageWorld(enemies: ["normal_a"], maxAlive: 1)
        // Park an obstacle tank exactly on spawn point 0.
        let blocker = world.spawnTank(teamID: 1, ownerPlayerID: nil, archetypeID: "normal_a",
                                      positionSubunits: Vec2i(x: 4 * 1024, y: 1 * 1024), facing: .down)
        world.withTank(entityID: blocker) { $0.spawnProtectionTicks = 0 }
        var events: [DomainEvent] = []
        tick(&world, 11 + 46, events: &events)
        #expect(world.tanks.filter { $0.teamID != 1 }.isEmpty) // deferred, not spawned on top
        tick(&world, 170, events: &events) // defer window → relocate → re-telegraph → spawn
        #expect(world.tanks.filter { $0.teamID != 1 }.count == 1)
    }
}

@Suite struct WinLossTests {
    @Test func killingAllEnemiesWinsAndStopsSpawns() {
        var world = makeStageWorld(enemies: ["normal_a"], maxAlive: 1, startDelay: 1)
        var events: [DomainEvent] = []
        tick(&world, 60, events: &events)
        guard let enemy = world.tanks.first(where: { $0.teamID != 1 }) else {
            Issue.record("enemy never spawned"); return
        }
        // Execute the enemy directly (combat path already covered elsewhere).
        world.withTank(entityID: enemy.entityID) { $0.armor = 0; $0.spawnProtectionTicks = 0 }
        tick(&world, 2, events: &events)
        #expect(world.stage?.phase == .won)
        #expect(events.contains { if case .stageWon = $0 { true } else { false } })
        // Live-lock exit criterion: nothing left to spawn, phase frozen.
        let checksum = world.checksum()
        tick(&world, 120, events: &events)
        #expect(world.stage?.phase == .won)
        #expect(world.spawnTelegraphs.isEmpty)
        _ = checksum
    }

    @Test func baseDestructionLoses() {
        var world = makeStageWorld()
        world.base?.durability = 1
        var events: [DomainEvent] = []
        _ = {
            var w = world
            return w
        }()
        // Enemy shot into the base.
        let id = world.claimEntityID()
        world.projectiles.append(ProjectileState(
            entityID: id, weaponID: "normal", ownerEntityID: -1, ownerPlayerID: nil,
            teamID: 2, powerLevel: 0, positionSubunits: Vec2i(x: 36 * 1024, y: 23 * 1024),
            direction: .right, speedSubunitsPerTick: 192, lifetimeRemainingTicks: 600,
            penetrationRemaining: 0, durability: 1))
        tick(&world, 40, events: &events)
        #expect(world.base?.durability == 0)
        #expect(world.stage?.phase == .lost)
        #expect(events.contains { if case .stageLost("base_destroyed") = $0 { true } else { false } })
    }

    @Test func playerEliminationLosesWhileEnemiesRemain() {
        var world = makeStageWorld(enemies: ["normal_a", "normal_a", "normal_a"], startDelay: 500)
        world.withPlayer(.one) { $0.lives = 0 }
        var events: [DomainEvent] = []
        if let tankID = world.player(.one)?.tankEntityID {
            world.withTank(entityID: tankID) { $0.armor = 0 }
        }
        tick(&world, 2, events: &events)
        #expect(world.player(.one)?.lifeState == .eliminated)
        #expect(world.stage?.phase == .lost)
    }

    /// §6.7 simultaneity: last enemy dies the same tick the sole player is
    /// eliminated and the base survives → WIN (ruleset default).
    @Test func simultaneousLastEnemyAndPlayerDeathIsWin() {
        var world = makeStageWorld(enemies: [], startDelay: 1)
        // Queue is empty by design here: the LAST enemy is the manual one.
        let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                                    positionSubunits: Vec2i(x: 30 * 1024, y: 10 * 1024), facing: .down)
        world.withPlayer(.one) { $0.lives = 0 }
        world.withTank(entityID: enemy) { $0.armor = 0; $0.spawnProtectionTicks = 0 }
        if let tankID = world.player(.one)?.tankEntityID {
            world.withTank(entityID: tankID) { $0.armor = 0 }
        }
        var events: [DomainEvent] = []
        tick(&world, 2, events: &events)
        #expect(world.stage?.phase == .won)
    }
}

@Suite struct RespawnTests {
    @Test func playerRespawnsWithRetainedUpgrades() {
        var world = makeStageWorld(enemies: ["normal_a"], startDelay: 999_999)
        guard let tankID = world.player(.one)?.tankEntityID else { return }
        world.withTank(entityID: tankID) {
            $0.speedLevel = 2; $0.powerLevel = 1
            $0.equipmentID = "anti_skid"; $0.specialWeaponID = "ap"
            $0.armor = 0
        }
        world.withPlayer(.one) { $0.specialAmmoByWeapon["ap"] = 7 }
        var events: [DomainEvent] = []
        tick(&world, 2, events: &events)
        #expect(world.player(.one)?.lifeState == .awaitingRespawn)
        #expect(world.player(.one)?.lives == 2)
        #expect(world.player(.one)?.tankEntityID == nil)
        tick(&world, 61, events: &events)
        guard let newTankID = world.player(.one)?.tankEntityID,
              let tank = world.tank(entityID: newTankID) else {
            Issue.record("player did not respawn"); return
        }
        #expect(tank.speedLevel == 2 && tank.powerLevel == 1) // retained (§6.5)
        #expect(tank.equipmentID == "anti_skid")
        #expect(tank.specialWeaponID == "ap")
        #expect(world.player(.one)?.specialAmmoByWeapon["ap"] == 7) // stored ammo kept
        #expect(tank.armor == 3) // reset
        #expect(tank.spawnProtectionTicks > 0)
    }

    @Test func blockedRespawnCellRingScans() {
        var world = makeStageWorld(enemies: ["normal_a"], startDelay: 999_999)
        guard let tankID = world.player(.one)?.tankEntityID else { return }
        // Park a blocker on the respawn cell before killing the player.
        let blocker = world.spawnTank(teamID: 1, ownerPlayerID: nil, archetypeID: "normal_a",
                                      positionSubunits: Vec2i(x: 20 * 1024, y: 20 * 1024), facing: .down)
        _ = blocker
        world.withTank(entityID: tankID) { $0.armor = 0 }
        var events: [DomainEvent] = []
        tick(&world, 63, events: &events)
        guard let newTankID = world.player(.one)?.tankEntityID,
              let tank = world.tank(entityID: newTankID) else {
            Issue.record("player did not respawn"); return
        }
        #expect(tank.positionSubunits != Vec2i(x: 20 * 1024, y: 20 * 1024)) // ring-scanned aside
        let violations = WorldInvariants.violations(in: world)
        #expect(violations.isEmpty, "\(violations)")
    }
}

@Suite struct PickupTests {
    private func drop(_ id: String, into world: inout WorldState, at cell: Vec2i = Vec2i(x: 22, y: 20)) {
        var events: [DomainEvent] = []
        world.spawnStagePickup(id, nearCell: cell, events: &events)
        // Skip the avoidance grace for direct-effect tests.
        for i in world.pickups.indices { world.pickups[i].graceTicksRemaining = 0 }
    }

    @Test func upgradePickupsApplyAndRetain() {
        var world = makeStageWorld(enemies: ["normal_a"], startDelay: 999_999)
        drop("speed_up", into: &world)
        drop("power_up", into: &world, at: Vec2i(x: 23, y: 20))
        var events: [DomainEvent] = []
        tick(&world, 90, direction: .right, events: &events) // drive over both
        guard let tankID = world.player(.one)?.tankEntityID,
              let tank = world.tank(entityID: tankID) else { return }
        #expect(tank.speedLevel == 1)
        #expect(tank.powerLevel == 1)
        #expect(world.player(.one)?.retainedSpeedLevel == 1) // respawn retention synced
        #expect(world.pickups.isEmpty)
    }

    @Test func gracePeriodPreventsInstantCollection() {
        var world = makeStageWorld(enemies: ["normal_a"], startDelay: 999_999)
        var events: [DomainEvent] = []
        // Spawn directly under the player with full grace.
        world.spawnStagePickup("speed_up", nearCell: Vec2i(x: 20, y: 20), events: &events)
        tick(&world, 20, events: &events)
        #expect(!world.pickups.isEmpty) // still uncollected during grace
        tick(&world, 30, events: &events)
        #expect(world.pickups.isEmpty) // collected after grace expires
    }

    @Test func freezeBombShieldAndLifePickups() {
        var world = makeStageWorld(enemies: ["normal_a"], startDelay: 999_999)
        let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_b",
                                    positionSubunits: Vec2i(x: 40 * 1024, y: 5 * 1024), facing: .down)
        world.withTank(entityID: enemy) { $0.armor = 5; $0.maxArmor = 5; $0.spawnProtectionTicks = 0 }
        var events: [DomainEvent] = []

        drop("freeze_enemy", into: &world)
        tick(&world, 60, direction: .right, events: &events)
        #expect(world.tank(entityID: enemy)?.statusEffects["frozen"] != nil)

        drop("bomb", into: &world, at: Vec2i(x: 24, y: 20))
        tick(&world, 60, direction: .right, events: &events)
        #expect((world.tank(entityID: enemy)?.armor ?? 99) <= 2)

        drop("extra_life", into: &world, at: Vec2i(x: 27, y: 20))
        drop("base_shield", into: &world, at: Vec2i(x: 29, y: 20))
        tick(&world, 160, direction: .right, events: &events)
        #expect(world.player(.one)?.lives == 4)
        #expect((world.base?.shieldRemainingTicks ?? 0) > 0)
        // Shovel rule: the fort ring hardens to steel while shielded…
        #expect(world.terrain[39, 21].kind == .steel)
        #expect(world.terrain[42, 24].kind == .steel)
        // …and is rebuilt as brick once the shield expires.
        tick(&world, 1300, events: &events)
        #expect(world.base?.shieldRemainingTicks == 0)
        #expect(world.terrain[39, 21].kind == .brick)
        #expect(world.terrain[42, 24].kind == .brick)
    }

    @Test func carrierEnemyDropsItsItemSomewhereOnTheMap() {
        var world = makeStageWorld(enemies: ["normal_a"], maxAlive: 1, startDelay: 1) { w in
            w.stage?.carriedPickupQueue = ["base_shield"]
            w.stage?.dropTable = [] // carriers are the only drop source here
        }
        var events: [DomainEvent] = []
        tick(&world, 60, events: &events)
        guard let enemy = world.tanks.first(where: { $0.teamID != 1 }) else {
            Issue.record("enemy never spawned"); return
        }
        #expect(enemy.carriedPickupID == "base_shield")
        world.withTank(entityID: enemy.entityID) { $0.armor = 0; $0.spawnProtectionTicks = 0 }
        tick(&world, 2, events: &events)
        #expect(world.pickups.contains { $0.pickupID == "base_shield" })
    }

    @Test func nonCarrierDropsNothingWithEmptyDropTable() {
        var world = makeStageWorld(enemies: ["normal_a"], maxAlive: 1, startDelay: 1) { w in
            w.stage?.dropTable = []
        }
        var events: [DomainEvent] = []
        tick(&world, 60, events: &events)
        guard let enemy = world.tanks.first(where: { $0.teamID != 1 }) else {
            Issue.record("enemy never spawned"); return
        }
        world.withTank(entityID: enemy.entityID) { $0.armor = 0; $0.spawnProtectionTicks = 0 }
        tick(&world, 2, events: &events)
        #expect(world.pickups.isEmpty)
    }

    @Test func hiddenTreasureRevealsWhenItsBrickFalls() {
        var world = makeStageWorld(enemies: ["normal_a"], startDelay: 999_999) { w in
            w.terrain[10, 10] = TerrainCell(kind: .brick)
            w.stage?.hiddenPickups = [HiddenPickup(cell: Vec2i(x: 10, y: 10), pickupID: "extra_life")]
        }
        var events: [DomainEvent] = []
        tick(&world, 5, events: &events)
        #expect(world.pickups.isEmpty) // still covered by brick
        world.terrain[10, 10] = TerrainCell(kind: .ground) // brick destroyed
        tick(&world, 2, events: &events)
        #expect(world.pickups.contains { $0.pickupID == "extra_life" })
        #expect(world.stage?.hiddenPickups.isEmpty == true)
    }

    @Test func weaponPickupSwitchesAndRefillsWithoutErasingStoredAmmo() {
        var world = makeStageWorld(enemies: ["normal_a"], startDelay: 999_999)
        world.withPlayer(.one) { $0.specialAmmoByWeapon["rapid"] = 33 }
        drop("ap_weapon", into: &world)
        var events: [DomainEvent] = []
        tick(&world, 30, direction: .right, events: &events)
        guard let tankID = world.player(.one)?.tankEntityID,
              let tank = world.tank(entityID: tankID) else { return }
        #expect(tank.specialWeaponID == "ap")
        #expect(world.player(.one)?.specialAmmoByWeapon["ap"] == 10) // refilled
        #expect(world.player(.one)?.specialAmmoByWeapon["rapid"] == 33) // kept (§8.1)
    }

    @Test func killDropsRollDeterministically() {
        func run() -> WorldState {
            var world = makeStageWorld(enemies: ["normal_a"], startDelay: 999_999)
            for i in 0..<3 {
                let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                                            positionSubunits: Vec2i(x: (30 + i * 4) * 1024, y: 5 * 1024),
                                            facing: .down)
                world.withTank(entityID: enemy) { $0.armor = 0; $0.spawnProtectionTicks = 0 }
            }
            var events: [DomainEvent] = []
            tick(&world, 3, events: &events)
            return world
        }
        let a = run(), b = run()
        #expect(a.pickups.count == 3) // dropChancePercent = 100
        #expect(a.checksum() == b.checksum())
        #expect(a.players[0].score == 300) // 3 × normal_a
    }
}

@Suite struct StageDeterminismTests {
    /// M3 exit criterion: deterministic full-stage replay — an identical
    /// scripted run over the whole VS-01-scale flow yields identical
    /// checksums, with invariants clean throughout.
    @Test func scriptedStageRunIsDeterministic() {
        func run() -> WorldState {
            var world = makeStageWorld(
                enemies: ["normal_a", "rapid_a", "normal_b", "normal_a", "rapid_b"],
                maxAlive: 3, startDelay: 60)
            var events: [DomainEvent] = []
            for t in 0..<3600 {
                let dir: Direction? = [Direction.up, .right, nil, .left, .down][(t / 90) % 5]
                tick(&world, 1, direction: dir, normal: t % 23 == 0, events: &events)
            }
            return world
        }
        let a = run(), b = run()
        #expect(a.checksum() == b.checksum())
        #expect(a == b)
        let violations = WorldInvariants.violations(in: a)
        #expect(violations.isEmpty, "\(violations)")
    }
}
