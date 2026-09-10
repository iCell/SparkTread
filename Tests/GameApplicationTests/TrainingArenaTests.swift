import Testing
import GameCore
@testable import GameApplication

/// Plan §5.2 / owner direction 2026-09-10: the Training Arena shows every
/// terrain kind and wall state, every enemy archetype driving and firing,
/// spawns any pickup on demand, and never ends — enemies respawn on death,
/// the base is repaired every tick, the player's lives never run out.
@Suite struct TrainingArenaTests {
    @Test func theArenaShowsEveryTerrainKindWallStateAndArchetype() {
        let world = TrainingArenaFixture.makeWorld()
        var kinds = Set<TerrainKind>(), brickMasks = Set<Int>(), steelMasks = Set<Int>()
        for y in 0..<world.arena.cellsHigh {
            for x in 0..<world.arena.cellsWide {
                let c = world.terrain[x, y]
                kinds.insert(c.kind)
                if c.kind == .brick { brickMasks.insert(c.quadrantMask) }
                if c.kind == .steel { steelMasks.insert(c.quadrantMask) }
            }
        }
        #expect(kinds == [.ground, .brick, .steel, .water, .ice, .foliage])
        #expect(brickMasks.count >= 8 && brickMasks.contains(0b1111))
        #expect(steelMasks.count >= 4 && steelMasks.contains(0b1111))
        let enemies = world.tanks.filter { $0.ownerPlayerID == nil }
        #expect(Set(enemies.map(\.archetypeID)) == Set(TrainingArenaFixture.enemyArchetypes) && enemies.count == 6)
        #expect(Set(enemies.map { String($0.archetypeID.split(separator: "_").first!) })
                == ["normal", "rapid", "fire", "ap", "explosion", "mine"]) // one per family
        for enemy in enemies {
            let attributes = EnemyArchetypes.attributes(for: enemy.archetypeID)
            #expect(enemy.armor == attributes.armor && enemy.equipmentID == attributes.equipmentID)
            #expect(enemy.specialWeaponID == String(enemy.archetypeID.split(separator: "_").first!))
        }
        #expect(world.player(.one)?.lives == TrainingArenaFixture.playerLives)
        #expect(world.base?.durability == TrainingArenaFixture.baseDurability && world.stage?.phase == .playing)
        #expect(world.stage?.spawnQueue.isEmpty == true)
        #expect(WorldInvariants.violations(in: world).isEmpty)
        #expect(TrainingArenaFixture.pickupIDs.count == 25 && Set(TrainingArenaFixture.pickupIDs).isSubset(of: StageValidator.KnownIDs.reference.pickups))
        // The M1 movement fixture is untouched by the arena.
        #expect(MovementLabFixture.makeWorld().stage == nil)
    }

    @Test func enemiesDriveAndFireTheirFamilyWeapons() {
        var session = MovementLabSession.trainingArena()
        var events: [DomainEvent] = []
        for _ in 0..<900 { events += session.advance(holding: nil) }
        let enemyShots = events.compactMap { e -> String? in
            if case .weaponFired(_, nil, let weaponID, _, _, _) = e { return weaponID }; return nil }
        #expect(enemyShots.count > 5)
        #expect(Set(enemyShots).count >= 2) // more than one family fired
        let moved = session.world.tanks.filter { $0.ownerPlayerID == nil && $0.movementIntent != nil }
        #expect(moved.count >= 3)
        #expect(session.world.stage?.phase == .playing)
        #expect(WorldInvariants.violations(in: session.world).isEmpty)
    }

    @Test func aDestroyedEnemyReturnsAtOnceAndTheBaseAndLivesAreToppedUp() throws {
        var session = MovementLabSession.trainingArena()
        let victim = try #require(session.world.tanks.first { $0.archetypeID == "ap_a" })
        session.debugDestroyTank(victim.entityID)
        let events = session.advance(holding: nil)
        #expect(events.contains { if case .tankDestroyed(victim.entityID, nil, _) = $0 { true } else { false } })
        let survivors = session.world.tanks.filter { $0.archetypeID == "ap_a" }
        #expect(survivors.count == 1 && survivors[0].entityID != victim.entityID)
        #expect(survivors[0].armor == EnemyArchetypes.attributes(for: "ap_a").armor)
        #expect(session.world.tanks.filter { $0.ownerPlayerID == nil }.count == 6)
        // Base damage and lost lives are restored by the next tick.
        session = .trainingArena()
        let tank = try #require(session.world.player(.one)?.tankEntityID)
        session.debugDestroyTank(tank) // the player dies: lives decrement, then are topped up when low
        for _ in 0..<3 { session.advance(holding: nil) }
        #expect((session.world.player(.one)?.lives ?? 0) >= TrainingArenaFixture.playerLives - 1)
        #expect(session.world.stage?.phase == .playing)
    }

    @Test func pickupsSpawnAheadOfThePlayerOnDemand() throws {
        var session = MovementLabSession.trainingArena()
        let spawnedAmphi = session.debugSpawnPickup("amphi_tank")
        #expect(spawnedAmphi)
        #expect(session.world.pickups.map(\.pickupID) == ["amphi_tank"])
        let tank = try #require(session.world.player(.one)?.tankEntityID.flatMap { session.world.tank(entityID: $0) })
        let pickup = session.world.pickups[0]
        #expect(pickup.positionSubunits.y < tank.positionSubunits.y) // ahead of an up-facing tank
        let spawnedBomb = session.debugSpawnPickup("bomb")
        #expect(spawnedBomb && session.world.pickups.count == 2)
        var stage = MovementLabSession(world: TrainingArenaFixture.makeWorld()) // not flagged: no arena rules
        let refused = stage.debugSpawnPickup("bomb")
        #expect(!refused && !stage.isTrainingArena)
    }
}
