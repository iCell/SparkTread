import Foundation
import Testing
@testable import GameCore

/// GAME_RULES R5 §9–§13: pickups, rescue items, Flag On Guard, spawning,
/// statistics and snapshot resume.
private func stageWorld(queue: [String] = ["normal_a"], spawnPoints: [Vec2i] = [Vec2i(x: 50, y: 1)],
                        maxAlive: Int = 4, delay: Int = 999_999, _ build: (inout WorldState) -> Void = { _ in }) -> WorldState {
    R5.world { w in
        w.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 40 * 1024, y: 22 * 1024))
        w.stage = StageState(spawnQueue: queue, maxAliveEnemies: maxAlive, enemyStartDelayTicks: delay,
                             spawnPointsCells: spawnPoints, playerRespawnCell: Vec2i(x: 3, y: 3), dropTable: [])
        build(&w)
    }
}

@Suite("R5 pickups")
struct R5PickupTests {
    @Test func pickupsAreTwoByTwoAndNeedRealOverlap() {
        var world = stageWorld()
        var events: [DomainEvent] = []
        #expect(world.spawnStagePickup("score_500", atCell: Vec2i(x: 5, y: 4), events: &events))
        #expect(world.spawnStagePickup("score_200", atCell: Vec2i(x: 5, y: 2), events: &events))
        #expect(!world.spawnStagePickup("score_1000", atCell: Vec2i(x: 6, y: 3), events: &events)) // overlaps both
        R5.step(&world, 3)
        #expect(world.pickups.count == 2) // edge contact at x = 5120 is not overlap
        let collected = R5.step(&world, 1, direction: .right)
        let deltas = collected.compactMap { if case .scoreChanged(let d) = $0 { d } else { nil } }
        #expect(deltas == [500, 200]) // same tick: ascending pickup entity id
        #expect(world.pickups.isEmpty && world.player(.one)?.score == 700)
    }

    @Test func hiddenPickupsRevealOnlyWhenAllSixteenQuadrantsAreClear() {
        var world = stageWorld {
            $0.terrain[10, 10] = TerrainCell(kind: .whiteBrick)
            $0.terrain[11, 11] = TerrainCell(kind: .brick, quadrantMask: 0b0001)
            $0.stage?.hiddenPickups = [HiddenPickup(cell: Vec2i(x: 10, y: 10), pickupID: "extra_life", critical: true)]
        }
        world.terrain[10, 10].crackMask = 0b1111 // cracked everywhere: still standing
        R5.step(&world)
        #expect(world.pickups.isEmpty)
        world.terrain[10, 10] = TerrainCell(kind: .ground)
        R5.step(&world)
        #expect(world.pickups.isEmpty) // one quadrant of (11, 11) still covers it
        world.terrain[11, 11] = TerrainCell(kind: .ground)
        R5.step(&world)
        #expect(world.pickups.map(\.pickupID) == ["extra_life"] && world.pickups[0].critical)
        R5.step(&world, 2000)
        #expect(world.pickups.count == 1) // critical pickups never expire
    }

    @Test func ordinaryPickupsExpireAfterThirtySeconds() {
        var world = stageWorld()
        var events: [DomainEvent] = []
        #expect(world.spawnStagePickup("score_200", atCell: Vec2i(x: 20, y: 10), events: &events))
        R5.step(&world, 1799)
        #expect(world.pickups.count == 1)
        R5.step(&world, 1)
        #expect(world.pickups.isEmpty)
    }

    /// §10.4: Bomb clears active enemies whatever their shield, spares
    /// spawn-protected and invincible ones, pays the kills, not the combo.
    @Test func bombClearsShieldedEnemiesAndSparesProtectedOnes() {
        var world = stageWorld()
        let heavy = R5.enemy(&world, cellX: 30, cellY: 5, archetype: "ap_d", armor: 6, shield: 3)
        let spawning = R5.enemy(&world, cellX: 30, cellY: 10)
        world.withTank(entityID: spawning) { $0.spawnProtectionTicks = 45 }
        let invincible = R5.enemy(&world, cellX: 30, cellY: 15)
        world.withTank(entityID: invincible) { $0.statusEffects["invincible"] = 100 }
        var events: [DomainEvent] = []
        #expect(world.spawnStagePickup("bomb", atCell: Vec2i(x: 5, y: 3), events: &events))
        R5.step(&world, 1, direction: .right)
        #expect(world.tank(entityID: heavy) == nil)
        #expect(world.tank(entityID: spawning) != nil && world.tank(entityID: invincible) != nil)
        #expect(world.player(.one)?.score == 550)
        #expect(world.player(.one)?.maxCombos == 0 && world.player(.one)?.lastComboKillTick == nil)
    }

    /// §10.4: Hold covers enemies still in spawn protection; repeats take the
    /// longer timer; frozen tanks still take damage.
    @Test func holdFreezesProtectedEnemiesAndDoesNotStack() {
        var world = stageWorld()
        let fresh = R5.enemy(&world, cellX: 8, cellY: 3, armor: 5)
        world.withTank(entityID: fresh) { $0.spawnProtectionTicks = 40 }
        var events: [DomainEvent] = []
        let playerID = R5.player(world)!.entityID
        #expect(world.spawnStagePickup("freeze_enemy", atCell: Vec2i(x: 3, y: 5), events: &events))
        R5.step(&world, 1, direction: .down)
        #expect(world.tank(entityID: fresh)?.statusEffects["frozen"] == 480)
        R5.step(&world, 100)
        #expect(world.tank(entityID: fresh)?.statusEffects["frozen"] == 380)
        world.withTank(entityID: playerID) { $0.positionSubunits = Vec2i(x: 3072, y: 3072); $0.facing = .down }
        #expect(world.spawnStagePickup("freeze_enemy", atCell: Vec2i(x: 3, y: 5), events: &events))
        R5.step(&world, 1, direction: .down)
        #expect(world.tank(entityID: fresh)?.statusEffects["frozen"] == 480) // the longer timer, not 380 + 480
        world.withTank(entityID: playerID) { $0.positionSubunits = Vec2i(x: 3072, y: 3072); $0.facing = .right }
        R5.step(&world, R5.settle, normal: true)
        #expect(world.tank(entityID: fresh)?.armor == 4) // frozen tanks still take damage
    }
}

@Suite("R5.14 crumble and whole-brick fort")
struct R5CrumbleAndFortRepairTests {
    /// A wall cell left with one quadrant falls with the hit: two normal
    /// rounds against a one-cell-thick wall take the pair of cells to the
    /// ground with nothing standing, and a cell that starts with two
    /// quadrants is gone after one quadrant is hit.
    @Test func aLoneQuadrantCrumbles() {
        var world = R5.world { R5.column(&$0, x: 10, .brick, ys: 2...5) }
        world.terrain[10, 3] = TerrainCell(kind: .brick, quadrantMask: 0b0011)   // top half only
        world.terrain[10, 4] = TerrainCell(kind: .brick, quadrantMask: 0b0011)
        R5.step(&world, normal: true); R5.step(&world, R5.settle)
        // The round takes the quadrants nearest the gun; what would have
        // been a lone quarter in each cell crumbles with them.
        #expect(world.terrain[10, 3].kind == .ground && world.terrain[10, 4].kind == .ground)
    }

    /// A shield taken over a shot-up fort hands back whole brick — the
    /// authored kind, full quadrants, no cracks — once it expires.
    @Test func theFortComesBackWholeAfterTheShield() {
        var world = stageWorld {
            $0.terrain[30, 10] = TerrainCell(kind: .brick, quadrantMask: 0b0011, crackMask: 0)
            $0.terrain[31, 10] = TerrainCell(kind: .ground)          // shot away entirely
            $0.terrain[32, 10] = TerrainCell(kind: .whiteBrick, quadrantMask: 0b1110, crackMask: 0b0010)
            $0.stage?.fortTemplate = [Vec2i(x: 30, y: 10), Vec2i(x: 31, y: 10), Vec2i(x: 32, y: 10)]
            $0.stage?.fortTemplateKinds = [.brick, .brick, .whiteBrick]
        }
        var events: [DomainEvent] = []
        Stage.activateFort(&world, events: &events)
        world.base?.shieldRemainingTicks = 1
        R5.step(&world, 2)
        #expect(world.terrain[30, 10] == TerrainCell(kind: .brick))
        #expect(world.terrain[31, 10] == TerrainCell(kind: .brick))      // rebuilt from the template's kind
        #expect(world.terrain[32, 10] == TerrainCell(kind: .whiteBrick))  // uncracked, whole
    }
}

@Suite("R5 Flag On Guard")
struct R5FortTests {
    private func fortWorld() -> WorldState {
        stageWorld {
            $0.terrain[30, 10] = TerrainCell(kind: .whiteBrick, crackMask: 0b0001)
            $0.terrain[31, 10] = TerrainCell(kind: .ground)
            $0.terrain[32, 10] = TerrainCell(kind: .water)
            $0.terrain[33, 10] = TerrainCell(kind: .whiteSteel)
            $0.stage?.fortTemplate = [Vec2i(x: 30, y: 10), Vec2i(x: 31, y: 10), Vec2i(x: 32, y: 10), Vec2i(x: 33, y: 10)]
        }
    }

    private func shield(_ world: inout WorldState) {
        var events: [DomainEvent] = []
        Stage.activateFort(&world, events: &events)
        let remaining = world.base!.shieldRemainingTicks
        world.base?.shieldRemainingTicks = PickupRuleset.provisional.baseShieldTicks(afterPickupWith: remaining)
    }

    /// R5.14: brick in the template comes back WHOLE — the cracked white
    /// brick is uncracked after the shield; steel, water and white steel
    /// still restore as they stood.
    @Test func hardeningRecordsTheOriginalsAndExpiryRestoresBrickWhole() {
        var world = fortWorld()
        shield(&world)
        #expect(world.terrain[30, 10] == TerrainCell(kind: .steel))
        #expect(world.terrain[31, 10] == TerrainCell(kind: .steel))
        #expect(world.terrain[32, 10].kind == .steel && world.terrain[32, 10].surface == .ground)
        #expect(world.terrain[33, 10].kind == .whiteSteel) // never downgraded
        // Temporary steel broken during the shield stays broken until the next pickup.
        world.terrain[31, 10] = TerrainCell(kind: .ground)
        R5.step(&world, 5)
        #expect(world.terrain[31, 10].kind == .ground)
        world.base?.shieldRemainingTicks = 1
        R5.step(&world, 2)
        #expect(world.terrain[30, 10] == TerrainCell(kind: .whiteBrick)) // whole, uncracked (R5.14)
        #expect(world.terrain[31, 10] == TerrainCell(kind: .ground))
        #expect(world.terrain[32, 10] == TerrainCell(kind: .water))
        #expect(world.base?.fortRecord.isEmpty == true)
    }

    @Test func occupiedCellsWaitBothWays() {
        var world = fortWorld()
        let parked = R5.enemy(&world, cellX: 31, cellY: 11)
        world.withTank(entityID: parked) { $0.positionSubunits.y -= 400 } // over the lower half of (31, 10)
        shield(&world)
        #expect(world.terrain[31, 10].quadrantMask == 0b0011) // top quadrants only
        world.withTank(entityID: parked) { $0.positionSubunits.y += 400 }
        R5.step(&world)
        #expect(world.terrain[31, 10].quadrantMask == 0b1111) // retried while shielded
        // Restoring water under a tank waits until the tank has gone.
        world.terrain[32, 10] = TerrainCell(kind: .ground)
        world.withTank(entityID: parked) { $0.positionSubunits = Vec2i(x: 32 * 1024, y: 10 * 1024) }
        world.base?.shieldRemainingTicks = 1
        R5.step(&world, 2)
        #expect(world.terrain[32, 10].kind == .ground && world.base?.fortRecord.isEmpty == false)
        world.withTank(entityID: parked) { $0.positionSubunits = Vec2i(x: 36 * 1024, y: 10 * 1024) }
        R5.step(&world)
        #expect(world.terrain[32, 10] == TerrainCell(kind: .water) && world.base?.fortRecord.isEmpty == true)
    }

    @Test func aRepickDuringRestorationKeepsTheFirstRecord() {
        var world = fortWorld()
        shield(&world)
        world.terrain[32, 10] = TerrainCell(kind: .ground)
        let parked = R5.enemy(&world, cellX: 32, cellY: 10)
        world.base?.shieldRemainingTicks = 1
        R5.step(&world, 2)
        #expect(world.base?.fortRecord.isEmpty == false)
        shield(&world) // restoration pending: same cycle, same originals
        #expect(world.base?.fortRecord.first { $0.cell == Vec2i(x: 32, y: 10) }?.original == TerrainCell(kind: .water))
        world.removeTankForTraining(entityID: parked)
        world.base?.shieldRemainingTicks = 1
        R5.step(&world, 2)
        #expect(world.terrain[32, 10] == TerrainCell(kind: .water) && world.terrain[30, 10].kind == .whiteBrick)
    }
}

@Suite("R5 spawning and statistics")
struct R5SpawnStatsTests {
    /// §9.3: the first wave starts together at distinct points; later spawn
    /// processes start at most one per 30 ticks; new enemies hold fire 45 ticks.
    @Test func spawnCadenceAndSpawnProtection() {
        var world = stageWorld(queue: Array(repeating: "normal_a", count: 6),
                               spawnPoints: [Vec2i(x: 4, y: 1), Vec2i(x: 20, y: 1), Vec2i(x: 36, y: 1)],
                               maxAlive: 4, delay: 0)
        R5.step(&world)
        #expect(world.spawnTelegraphs.count == 3 && Set(world.spawnTelegraphs.map(\.spawnPointIndex)).count == 3)
        R5.step(&world, 44)
        #expect(world.tanks.filter { $0.teamID == 2 }.isEmpty && world.spawnTelegraphs.count == 3)
        var fired = 0
        for _ in 0..<45 {
            let events = R5.step(&world)
            fired += events.filter { if case .weaponFired(_, nil, _, _, _, _) = $0 { true } else { false } }.count
        }
        #expect(world.tanks.filter { $0.teamID == 2 }.count == 3)
        #expect(world.spawnTelegraphs.count == 1) // the fourth, one process only
        #expect(fired == 0) // 45 ticks of spawn protection: no enemy shots
    }

    /// §9.3: a spawn reservation keeps tanks from entering, but a tank that
    /// already stands in one drives out.
    @Test func aTankInsideASpawnReservationDrivesOutButNoneEnters() throws {
        var inside = R5.world()
        let start = try #require(R5.player(inside)).positionSubunits
        inside.spawnTelegraphs.append(SpawnTelegraph(entityID: inside.claimEntityID(), archetypeID: "normal_a",
                                                     spawnPointIndex: 0, positionSubunits: start, ticksRemaining: 45))
        R5.step(&inside, 60, direction: .right)
        #expect(try #require(R5.player(inside)).positionSubunits.x > start.x + R5.cell)

        var outside = R5.world()
        let ahead = Vec2i(x: 7 * R5.cell, y: 3 * R5.cell)
        outside.spawnTelegraphs.append(SpawnTelegraph(entityID: outside.claimEntityID(), archetypeID: "normal_a",
                                                      spawnPointIndex: 0, positionSubunits: ahead, ticksRemaining: 45))
        R5.step(&outside, 240, direction: .right)
        let front = try #require(R5.player(outside)).positionSubunits.x + SpatialUnits.standardTankFootprintSubunits
            - MovementRuleset.provisional.collisionInsetSubunits
        #expect(front <= ahead.x)
    }

    /// The owner's report (2026-09-15): with one spawn point, the next
    /// process starts on the point a slow tank just spawned at. The tank
    /// must leave so the process can finish; before the fix both waited
    /// forever and the stage never ended.
    @Test func aSlowEnemyOnItsSpawnPointDoesNotDeadlockTheNextSpawn() {
        var world = stageWorld(queue: ["ap_a", "normal_a"], spawnPoints: [Vec2i(x: 27, y: 1)], maxAlive: 2, delay: 0) {
            $0.withTanksInEntityOrder { if $0.ownerPlayerID != nil { $0.statusEffects["invincible"] = 100_000 } }
        }
        var spawned = 0
        for _ in 0..<1800 where spawned < 2 {
            spawned += R5.step(&world).filter { if case .tankSpawned(_, nil, _, _) = $0 { true } else { false } }.count
        }
        #expect(spawned == 2 && world.spawnTelegraphs.isEmpty)
    }

    /// §13: MaxHits counts consecutive shells that hurt an enemy; a shell
    /// that only meets a wall resets the streak.
    @Test func maxHitsTracksConsecutiveDamagingShells() {
        var world = stageWorld { R5.column(&$0, x: 12, .brick, ys: 1...2) }
        let target = R5.enemy(&world, cellX: 8, cellY: 3, armor: 8)
        world.withTank(entityID: target) { $0.statusEffects["frozen"] = 10_000 } // a still target that does not shoot back
        for _ in 0..<3 { R5.step(&world, normal: true); R5.step(&world, R5.settle) }
        #expect(world.player(.one)?.hitStreak == 3 && world.player(.one)?.maxHits == 3)
        world.withTank(entityID: R5.player(world)!.entityID) { $0.facing = .up }
        R5.step(&world, normal: true); R5.step(&world, R5.settle) // into the border
        #expect(world.player(.one)?.hitStreak == 0 && world.player(.one)?.maxHits == 3)
    }

    /// §13: MaxCombos counts qualifying kills at most 120 ticks apart.
    @Test func maxCombosChainsKillsWithinTheWindow() {
        var world = stageWorld()
        func kill(after ticks: Int) {
            R5.step(&world, ticks)
            let id = R5.enemy(&world, cellX: 30, cellY: 10)
            world.withTank(entityID: id) { $0.armor = 0; $0.killedBy = KillAttribution(playerID: .one) }
            R5.step(&world)
        }
        kill(after: 0); kill(after: 60); kill(after: 118)
        #expect(world.player(.one)?.comboStreak == 3 && world.player(.one)?.maxCombos == 3)
        kill(after: 200)
        #expect(world.player(.one)?.comboStreak == 1 && world.player(.one)?.maxCombos == 3)
        #expect(world.player(.one)?.score == 400)
    }

    @Test func theRosterIsTwentyTypesWithTwoEquipmentItemsAndTheResultsMapping() {
        #expect(EnemyArchetypes.allIDs.count == 20)
        let equipment = Set(EnemyArchetypes.allIDs.compactMap { EnemyArchetypes.attributes(for: $0).equipmentID })
        #expect(equipment == ["amphi_tank", "anti_skid"])
        let categories = EnemyArchetypes.allIDs.map { EnemyArchetypes.attributes(for: $0).rewardCategory }
        #expect(categories == [0, 0, 1, 1, 2, 2, 3, 3, 5, 5, 5, 5, 6, 6, 7, 7, 4, 4, 4, 4])
        #expect(WeaponRuleset.provisional.weapons.map(\.id) == ["normal", "rapid", "fire", "ap", "explosion"])
    }

    /// ADR-0003 under R5: a populated world (flames, a fort cycle, a queued
    /// drop, a tank leaving water) survives serialize → restore → resume.
    @Test func populatedWorldSurvivesSerializeRestoreResume() throws {
        func build() -> WorldState {
            var world = stageWorld(queue: ["normal_a", "rapid_a"], delay: 30) {
                $0.stage?.fortTemplate = [Vec2i(x: 39, y: 21), Vec2i(x: 42, y: 21)]
                for y in 12...14 { for x in 10...12 { $0.terrain[x, y] = TerrainCell(kind: .foliage) } }
                for y in 5...9 { $0.terrain[20, y] = TerrainCell(kind: .water) }
            }
            var events: [DomainEvent] = []
            Stage.activateFort(&world, events: &events)
            world.base?.shieldRemainingTicks = 50
            Fire.addFlame(&world, cell: Vec2i(x: 11, y: 13), color: .yellow, sourceKey: 1, ownerPlayerID: .one,
                          weapons: .provisional, events: &events)
            Stage.requestPickup(&world, pickupID: "power_up", critical: true)
            let swimmer = R5.enemy(&world, cellX: 19, cellY: 6)
            world.withTank(entityID: swimmer) { $0.leavingWater = true }
            R5.give(&world, "fire", ammo: 10)
            R5.step(&world, 10, special: true)
            return world
        }
        var interrupted = build()
        let data = try JSONEncoder().encode(interrupted)
        var restored = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(restored == interrupted)
        var uninterrupted = build()
        R5.step(&interrupted, 1)
        R5.step(&restored, 300)
        R5.step(&uninterrupted, 300)
        #expect(restored.checksum() == uninterrupted.checksum() && restored == uninterrupted)
        #expect(WorldInvariants.violations(in: restored).isEmpty, "\(WorldInvariants.violations(in: restored))")
    }
}
