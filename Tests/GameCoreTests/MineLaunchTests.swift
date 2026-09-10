import Foundation
import Testing
@testable import GameCore

/// ADR-0016 / plan §8.6: a surviving tank that triggers a mine is thrown
/// along its travel direction, is suspended from every interaction while
/// airborne, lands on the nearest legal cell and is slowed.
private let cell = SpatialUnits.subunitsPerCell

private func makeWorld() -> WorldState {
    var terrain = TerrainGrid(arena: .universal)
    let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
    for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
    for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
    var world = WorldState(terrain: terrain, seed: 4)
    world.addPlayer(PlayerState(playerID: .one))
    return world
}

/// A player tank driving right into an ARMED enemy mine of `level` two cells ahead.
private func armedMineAhead(level: Int, equipment: String? = nil, armor: Int = 8) -> (WorldState, Int, Int) {
    var world = makeWorld()
    let player = world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                                 positionSubunits: Vec2i(x: 10 * cell, y: 10 * cell), facing: .right)
    world.withTank(entityID: player) { $0.equipmentID = equipment; $0.armor = armor; $0.maxArmor = 8; $0.spawnProtectionTicks = 0 }
    let mineID = world.claimEntityID()
    let weapon = WeaponRuleset.provisional.weapon("mine")!
    world.mines.append(MineState(entityID: mineID, level: level, ownerEntityID: -1, ownerPlayerID: nil, teamID: 2,
                                 positionSubunits: Vec2i(x: 14 * cell, y: 11 * cell),
                                 phase: .armed, phaseTicksRemaining: 0,
                                 triggerRadiusSubunits: weapon.level(weapon.mineTriggerRadiusSubunits, level), onWater: false))
    return (world, player, mineID)
}

private func drive(_ world: inout WorldState, _ direction: Direction?, ticks: Int,
                   weapons: WeaponRuleset = .provisional) -> [DomainEvent] {
    var events: [DomainEvent] = []
    for _ in 0..<ticks {
        events += Simulation.step(&world, commands: [PlayerCommand(playerID: .one, targetTick: world.tick, moveDirection: direction)],
                                  weapons: weapons)
    }
    return events
}

/// Drives right until the player is launched (or `limit` ticks pass);
/// returns the launch's from/to when it happened.
private func driveUntilLaunched(_ world: inout WorldState, weapons: WeaponRuleset = .provisional,
                                limit: Int = 120) -> (from: Vec2i, to: Vec2i)? {
    for _ in 0..<limit {
        for event in drive(&world, .right, ticks: 1, weapons: weapons) {
            if case .tankLaunched(_, .one, let from, let to) = event { return (from, to) }
        }
    }
    return nil
}

@Suite struct MineLaunchTests {
    @Test func aSurvivingTankIsThrownAlongItsTravelAndLandsSlowed() throws {
        var (world, player, _) = armedMineAhead(level: 2)
        let launch = try #require(driveUntilLaunched(&world))
        let rules = WeaponRuleset.provisional
        #expect(launch.to.x - launch.from.x == rules.mineLaunchDistanceSubunits[2] && launch.to.y == launch.from.y)
        let tank = try #require(world.tank(entityID: player))
        #expect(tank.armor == 8 - rules.weapon("mine")!.level(rules.weapon("mine")!.tankDamage, 2))
        #expect(tank.statusEffects["airborne"] == rules.mineAirborneTicks[2])
        #expect(tank.landingSubunits == launch.to && tank.movementIntent == nil)
        #expect(WorldInvariants.violations(in: world).isEmpty)
        // Airborne: input does nothing, the tank neither moves nor fires.
        let before = tank.positionSubunits
        let flying = drive(&world, .down, ticks: 5)
        #expect(world.tank(entityID: player)?.positionSubunits == before)
        #expect(!flying.contains { if case .weaponFired(player, _, _, _, _, _) = $0 { true } else { false } })
        let rest = drive(&world, nil, ticks: rules.mineAirborneTicks[2])
        // Lands on the nearest legal CELL to the nominal point (ring scan, §8.6).
        let snapped = Vec2i(x: (launch.to.x + cell / 2) / cell * cell, y: (launch.to.y + cell / 2) / cell * cell)
        #expect(rest.contains { if case .tankLanded(player, .one, snapped) = $0 { true } else { false } })
        let landed = try #require(world.tank(entityID: player))
        #expect(landed.positionSubunits == snapped && landed.landingSubunits == nil && landed.statusEffects["airborne"] == nil)
        #expect(abs(landed.positionSubunits.x - launch.to.x) < cell)
        #expect(landed.statusEffects["slowed"] != nil)
        // Slowed: half speed for the level's ticks, then full speed.
        let slowStart = landed.positionSubunits.x
        _ = drive(&world, .right, ticks: 30)
        let slowTravel = world.tank(entityID: player)!.positionSubunits.x - slowStart
        _ = drive(&world, .right, ticks: rules.mineSlowTicks[2])
        let fullStart = world.tank(entityID: player)!.positionSubunits.x
        _ = drive(&world, .right, ticks: 30)
        let fullTravel = world.tank(entityID: player)!.positionSubunits.x - fullStart
        #expect(world.tank(entityID: player)?.statusEffects["slowed"] == nil)
        #expect(slowTravel * 2 <= fullTravel + 2 && slowTravel < fullTravel)
    }

    @Test func airborneTanksAreUntargetableAndDoNotBlock() throws {
        var (world, player, _) = armedMineAhead(level: 3)
        #expect(driveUntilLaunched(&world) != nil)
        var tank = try #require(world.tank(entityID: player))
        #expect(tank.statusEffects["airborne"] != nil)
        // An enemy shot through the airborne tank's position passes.
        let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                                    positionSubunits: Vec2i(x: tank.positionSubunits.x + 6 * cell, y: tank.positionSubunits.y), facing: .left)
        world.withTank(entityID: enemy) { $0.spawnProtectionTicks = 0 }
        let shotID = world.claimEntityID()
        let normal = WeaponRuleset.provisional.weapon("normal")!
        world.projectiles.append(ProjectileState(entityID: shotID, weaponID: "normal", ownerEntityID: enemy, ownerPlayerID: nil,
                                                 teamID: 2, powerLevel: 0,
                                                 positionSubunits: Vec2i(x: tank.positionSubunits.x + 3 * cell, y: tank.positionSubunits.y + cell),
                                                 direction: .left, speedSubunitsPerTick: normal.level(normal.initialSpeedSubunitsPerTick, 0),
                                                 lifetimeRemainingTicks: 20, penetrationRemaining: 0, durability: 0, hitTankIDs: []))
        let armorBefore = tank.armor
        let events = drive(&world, nil, ticks: 3)
        #expect(!events.contains { if case .tankDamaged(player, _, _, _, _) = $0 { true } else { false } })
        #expect(world.tank(entityID: player)?.armor == armorBefore)
        // Another tank can drive through the airborne one's footprint.
        let field = Simulation.ObstacleField(world: world, excludingTank: enemy)
        tank = try #require(world.tank(entityID: player))
        #expect(!field.blocksTank(minX: tank.positionSubunits.x + 64, minY: tank.positionSubunits.y + 64,
                                  maxX: tank.positionSubunits.x + 1984, maxY: tank.positionSubunits.y + 1984))
    }

    @Test func landingFallsBackToTheNearestFreeCell() throws {
        var (world, player, _) = armedMineAhead(level: 1)
        // A steel wall where the tank would land: it lands short of it, at the nearest free cell.
        for y in 8...13 { world.terrain[15, y] = TerrainCell(kind: .steel) }
        #expect(driveUntilLaunched(&world) != nil)
        let tank = try #require(world.tank(entityID: player))
        #expect(tank.statusEffects["airborne"] != nil)
        _ = drive(&world, nil, ticks: WeaponRuleset.provisional.mineAirborneTicks[1] + 1)
        let landed = try #require(world.tank(entityID: player))
        #expect(landed.landingSubunits == nil)
        #expect(!world.terrain.blocksTank(minX: landed.positionSubunits.x + 64, minY: landed.positionSubunits.y + 64,
                                         maxX: landed.positionSubunits.x + 1984, maxY: landed.positionSubunits.y + 1984))
        #expect(WorldInvariants.violations(in: world).isEmpty)
    }

    @Test func exemptionsAndTheDisableSwitch() {
        // Memory of Sea: damaged, never launched.
        var (sea, seaPlayer, _) = armedMineAhead(level: 2, equipment: "memory_of_sea")
        let seaEvents = drive(&sea, .right, ticks: 60)
        #expect(seaEvents.contains { if case .mineTriggered = $0 { true } else { false } })
        #expect(!seaEvents.contains { if case .tankLaunched = $0 { true } else { false } })
        #expect(sea.tank(entityID: seaPlayer)?.statusEffects["airborne"] == nil)
        // Level 0: no launch.
        var (zero, _, _) = armedMineAhead(level: 0)
        #expect(!drive(&zero, .right, ticks: 60).contains { if case .tankLaunched = $0 { true } else { false } })
        // AntiSkid crosses low levels without triggering at all.
        var (skid, _, mineID) = armedMineAhead(level: 2, equipment: "anti_skid")
        _ = drive(&skid, .right, ticks: 60)
        #expect(skid.mines.contains { $0.entityID == mineID })
        // Disabled by ruleset data.
        var off = WeaponRuleset.provisional
        off.mineLaunchEnabled = false
        var (plain, plainPlayer, _) = armedMineAhead(level: 3)
        let offEvents = drive(&plain, .right, ticks: 60, weapons: off)
        #expect(offEvents.contains { if case .mineTriggered = $0 { true } else { false } })
        #expect(!offEvents.contains { if case .tankLaunched = $0 { true } else { false } })
        #expect(plain.tank(entityID: plainPlayer)?.statusEffects["airborne"] == nil)
        // A tank destroyed by the blast does not fly.
        var (dead, deadPlayer, _) = armedMineAhead(level: 3, armor: 1)
        let deadEvents = drive(&dead, .right, ticks: 60)
        #expect(deadEvents.contains { if case .tankDestroyed(deadPlayer, _, _) = $0 { true } else { false } })
        #expect(!deadEvents.contains { if case .tankLaunched = $0 { true } else { false } })
        // Ruleset validation.
        var bad = WeaponRuleset.provisional
        bad.mineAirborneTicks = [0, 0, 24, 30]
        #expect(bad.validationIssues().contains { $0.contains("airborne ticks") })
        bad.mineLaunchDistanceSubunits = [0, 1]
        #expect(bad.validationIssues().contains { $0.contains("4 entries") })
    }

    @Test func flightSurvivesSerializationDeterministically() throws {
        var (a, _, _) = armedMineAhead(level: 2)
        #expect(driveUntilLaunched(&a) != nil)
        #expect(a.tanks[0].statusEffects["airborne"] != nil)
        var b = try JSONDecoder().decode(WorldState.self, from: JSONEncoder().encode(a))
        #expect(b == a && b.checksum() == a.checksum())
        _ = drive(&a, .right, ticks: 200); _ = drive(&b, .right, ticks: 200)
        #expect(a.checksum() == b.checksum() && a.tanks[0].landingSubunits == nil)
    }
}
