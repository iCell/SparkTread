import Testing
@testable import GameCore

/// GAME_RULES R5 §6.4 (explosions) and §7 (fire, foliage).
@Suite("R5 explosions")
struct R5ExplosionTests {
    /// §6.4: the wall shields itself — a blast on a flat brick face takes
    /// only the front quadrant column, however large the radius.
    @Test func aBlastOnAFlatWallTakesOnlyTheFrontColumn() {
        var world = R5.world {
            R5.column(&$0, x: 10, .brick); R5.column(&$0, x: 11, .brick)
            R5.give(&$0, "explosion", ammo: 1, power: 3)
        }
        let events = R5.step(&world, R5.settle, special: true)
        #expect(events.contains { if case .explosion(Vec2i(x: 10240, y: 4096), 2048) = $0 { true } else { false } })
        for y in 2...5 { #expect(world.terrain[10, y].quadrantMask & 0b0101 == 0, "row \(y) front column") }
        #expect(world.terrain[10, 1].quadrantMask == 0b1011) // row 3 of quadrants: the lower-left one only
        #expect(world.terrain[10, 6].quadrantMask == 0b1110)
        for y in 1...25 { #expect(world.terrain[11, y].quadrantMask == 0b1111, "second column row \(y)") }
    }

    @Test func steelShieldsATankBehindIt() {
        var world = R5.world {
            R5.column(&$0, x: 10, .steel)
            R5.give(&$0, "explosion", ammo: 1, power: 3)
        }
        let hidden = R5.enemy(&world, cellX: 11, cellY: 3, armor: 5)
        R5.step(&world, R5.settle, special: true)
        #expect(world.tank(entityID: hidden)?.armor == 5)
        #expect(world.terrain[10, 3].quadrantMask == 0b1111)
    }

    /// §6.2: a blast shatters a shield without overflow; the next one hurts.
    @Test func aBlastShattersAShieldThenDamagesArmor() {
        var world = R5.world { R5.give(&$0, "explosion", ammo: 1) }
        let heavy = R5.enemy(&world, cellX: 8, cellY: 3, archetype: "ap_d", armor: 6, shield: 3)
        R5.step(&world, R5.settle, special: true)
        #expect(world.tank(entityID: heavy)?.shieldHP == 0 && world.tank(entityID: heavy)?.armor == 6)
        R5.give(&world, "explosion", ammo: 1)
        R5.step(&world, R5.settle, special: true)
        #expect(world.tank(entityID: heavy)?.armor == 4)
    }

    /// §6.2/§6.4: a protected target still detonates the shell; others in
    /// the radius take the blast.
    @Test func aProtectedTargetStillDetonatesTheShell() {
        var world = R5.world { R5.give(&$0, "explosion", ammo: 1, power: 3) }
        let shielded = R5.enemy(&world, cellX: 8, cellY: 3, armor: 5)
        world.withTank(entityID: shielded) { $0.spawnProtectionTicks = 500 }
        let neighbour = R5.enemy(&world, cellX: 8, cellY: 5, armor: 5)
        let events = R5.step(&world, R5.settle, special: true)
        #expect(R5.destroyed(events, impact: .deflected) == 1)
        #expect(world.tank(entityID: shielded)?.armor == 5)
        #expect(world.tank(entityID: neighbour)?.armor == 2)
    }

    @Test func blastsIgnoreShellsInFlight() {
        var world = R5.world { R5.give(&$0, "explosion", ammo: 1, power: 3) }
        R5.enemy(&world, cellX: 8, cellY: 3, armor: 9)
        let passer = R5.shell(&world, "ap", team: 2, center: Vec2i(x: 8600, y: 7500), direction: .down)
        let events = R5.step(&world, R5.settle, special: true)
        #expect(events.contains { if case .explosion = $0 { true } else { false } })
        #expect(world.projectiles.contains { $0.entityID == passer }) // still flying after the blast
    }

    /// §6.4: two standing quadrants sharing an edge block a blast that runs
    /// along it; one wall's outer face does not.
    @Test func occlusionCountsSharedEdgesButNotOuterFaces() {
        var terrain = TerrainGrid(arena: .universal)
        terrain[10, 10] = TerrainCell(kind: .brick, quadrantMask: 0b0101) // left column of cell 10
        terrain[9, 10] = TerrainCell(kind: .brick, quadrantMask: 0b1010)  // right column of cell 9
        let along = Vec2i(x: 10240, y: 10240 - 100), end = Vec2i(x: 10240, y: 11264 + 100)
        #expect(Combat.occluded(terrain, from: along, to: end, excluding: nil)) // shared edge x = 10240
        terrain[9, 10] = TerrainCell(kind: .ground)
        #expect(!Combat.occluded(terrain, from: along, to: end, excluding: nil)) // outer face only
        #expect(Combat.occluded(terrain, from: Vec2i(x: 9800, y: 10700), to: Vec2i(x: 11000, y: 10700), excluding: nil))
    }
}

@Suite("R5 fire")
struct R5FireTests {
    private func patches(_ world: WorldState) -> Set<Vec2i> { Set(world.fireHazards.map(\.cell)) }

    /// §7.1: flames land on the incident side of a wall only.
    @Test func flamesLandInFrontOfWallsNeverBehind() {
        var world = R5.world { R5.column(&$0, x: 10, .brick); R5.give(&$0, "fire", ammo: 1) }
        R5.step(&world, R5.settle, special: true)
        #expect(patches(world) == [Vec2i(x: 9, y: 3), Vec2i(x: 9, y: 4)])
        #expect(world.terrain[10, 3].quadrantMask == 0b1111) // fire never hurts walls
        var thin = R5.world { R5.column(&$0, x: 10, .brick, mask: 0b0101); R5.give(&$0, "fire", ammo: 1) }
        R5.step(&thin, R5.settle, special: true)
        #expect(patches(thin).allSatisfy { $0.x < 10 })
    }

    /// §7.1: an expiring fire shell drops its 2×2 footprint where it ends,
    /// except on water or ice.
    @Test func expiryFlamesSkipWaterAndIce() {
        var open = R5.world { R5.give(&$0, "fire", ammo: 1) }
        R5.step(&open, WeaponRuleset.provisional.weapon("fire")!.lifetimeTicks + 20, special: true)
        #expect(patches(open) == [Vec2i(x: 21, y: 3), Vec2i(x: 22, y: 3), Vec2i(x: 21, y: 4), Vec2i(x: 22, y: 4)])
        for surface in [TerrainKind.water, .ice] {
            var wet = R5.world {
                for y in 3...4 { $0.terrain[21, y] = TerrainCell(kind: surface) }
                R5.give(&$0, "fire", ammo: 1)
            }
            R5.step(&wet, WeaponRuleset.provisional.weapon("fire")!.lifetimeTicks + 20, special: true)
            #expect(patches(wet) == [Vec2i(x: 22, y: 3), Vec2i(x: 22, y: 4)], "\(surface)")
        }
    }

    /// §7.2: protection blocks the burn without spending the cadence; the
    /// flames outlast it.
    @Test func protectedTargetsBurnOnceProtectionEnds() {
        var world = R5.world { R5.give(&$0, "fire", ammo: 1) }
        let enemy = R5.enemy(&world, cellX: 8, cellY: 3, armor: 8)
        world.withTank(entityID: enemy) { $0.spawnProtectionTicks = 100 }
        R5.step(&world, 90, special: true)
        #expect(!world.fireHazards.isEmpty && world.tank(entityID: enemy)?.armor == 8)
        R5.step(&world, 15)
        #expect(world.tank(entityID: enemy)?.armor == 7) // immediately after protection
        R5.step(&world, 30)
        #expect(world.tank(entityID: enemy)?.armor == 6) // then every 30 ticks
    }

    /// §7.2–§7.3: overlapping flames share one cadence; yellow spares the
    /// player, orange spares enemies, red hurts both.
    @Test func flamesShareACadenceAndFollowTheirColour() {
        var world = R5.world()
        let enemy = R5.enemy(&world, cellX: 20, cellY: 10, armor: 8)
        var events: [DomainEvent] = []
        for (i, cell) in [Vec2i(x: 20, y: 10), Vec2i(x: 21, y: 10), Vec2i(x: 20, y: 11), Vec2i(x: 21, y: 11)].enumerated() {
            Fire.addFlame(&world, cell: cell, color: .yellow, sourceKey: 1 + i, ownerPlayerID: .one,
                          weapons: .provisional, events: &events)
            Fire.addFlame(&world, cell: Vec2i(x: 3 + i % 2, y: 3 + i / 2), color: .yellow, sourceKey: 1,
                          ownerPlayerID: .one, weapons: .provisional, events: &events)
        }
        R5.step(&world, 61)
        #expect(world.tank(entityID: enemy)?.armor == 5) // ticks 0, 30, 60
        #expect(R5.player(world)?.armor == 3) // own yellow fire
        Fire.addFlame(&world, cell: Vec2i(x: 3, y: 3), color: .orange, sourceKey: enemy, ownerPlayerID: nil,
                      weapons: .provisional, events: &events)
        R5.step(&world, 1)
        #expect(R5.player(world)?.armor == 2)
        var red = R5.world()
        let victim = R5.enemy(&red, cellX: 20, cellY: 10, armor: 8)
        red.addEnvironmentFire(cell: Vec2i(x: 20, y: 10), sourceKey: -1, lifetimeTicks: 340)
        red.addEnvironmentFire(cell: Vec2i(x: 3, y: 3), sourceKey: -2, lifetimeTicks: 340)
        R5.step(&red, 1)
        #expect(red.tank(entityID: victim)?.armor == 7 && R5.player(red)?.armor == 2)
        #expect(red.tank(entityID: victim)?.killedBy == nil)
    }

    /// §7.2: a flame is live for exactly 340 ticks from the tick it landed.
    @Test func aFlameLivesThreeHundredFortyTicks() {
        var world = R5.world { R5.column(&$0, x: 10, .brick); R5.give(&$0, "fire", ammo: 1) }
        var landed: Int?
        for _ in 0..<R5.settle {
            let t = world.tick
            let events = R5.step(&world, special: true)
            if landed == nil, events.contains(where: { if case .fireStarted = $0 { true } else { false } }) { landed = t }
        }
        let start = try! #require(landed)
        while world.tick < start + 340 { R5.step(&world) }
        #expect(!world.fireHazards.isEmpty) // after tick start + 339
        R5.step(&world)
        #expect(world.fireHazards.isEmpty) // gone at start + 340
    }

    /// §7.3 / §11.1: flames beside the base burn it (shared edge), filtered
    /// by source; a corner touch does not.
    @Test func theBaseBurnsFromAdjacentFlamesBySource() {
        func burn(_ color: FireColor, at cell: Vec2i, allied: Bool = true) -> Int {
            var world = R5.world { $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 20 * 1024, y: 10 * 1024)) }
            var weapons = WeaponRuleset.provisional
            weapons.alliedBaseDamage = allied
            var events: [DomainEvent] = []
            Fire.addFlame(&world, cell: cell, color: color, sourceKey: color == .red ? -1 : 1,
                          ownerPlayerID: color == .yellow ? .one : nil, weapons: weapons, events: &events)
            R5.step(&world, 31, weapons: weapons)
            return world.base?.durability ?? -1
        }
        #expect(burn(.yellow, at: Vec2i(x: 19, y: 10)) == 1)
        #expect(burn(.yellow, at: Vec2i(x: 19, y: 10), allied: false) == 3)
        #expect(burn(.orange, at: Vec2i(x: 22, y: 11), allied: false) == 1)
        #expect(burn(.red, at: Vec2i(x: 21, y: 12)) == 1)
        #expect(burn(.orange, at: Vec2i(x: 19, y: 9)) == 3) // corner only
    }

    /// §7.4: foliage spreads once per cell to its four neighbours 20 ticks
    /// after igniting, and is gone once its last flame dies; foliage on ice
    /// never burns.
    @Test func foliageSpreadsOnceAndBurnsAway() {
        var world = R5.world {
            for y in 10...14 { for x in 20...24 { $0.terrain[x, y] = TerrainCell(kind: .foliage) } }
            $0.terrain[25, 12] = TerrainCell(kind: .foliage, surface: .ice)
            $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 40 * 1024, y: 22 * 1024))
            $0.stage = StageState(spawnQueue: ["normal_a"], maxAliveEnemies: 1, enemyStartDelayTicks: 999_999,
                                  spawnPointsCells: [Vec2i(x: 50, y: 1)], playerRespawnCell: Vec2i(x: 3, y: 3), dropTable: [])
        }
        var events: [DomainEvent] = []
        Fire.addFlame(&world, cell: Vec2i(x: 22, y: 12), color: .yellow, sourceKey: 1, ownerPlayerID: .one,
                      weapons: .provisional, events: &events)
        R5.step(&world, 20) // ticks 0…19
        #expect(patches(world) == [Vec2i(x: 22, y: 12)])
        R5.step(&world) // tick 20
        #expect(patches(world) == [Vec2i(x: 22, y: 12), Vec2i(x: 22, y: 11), Vec2i(x: 23, y: 12),
                                   Vec2i(x: 22, y: 13), Vec2i(x: 21, y: 12)])
        #expect(world.terrain[22, 12].hasSpread)
        R5.step(&world, 40) // tick 60: Manhattan distance ≤ 3 (1 + 4 + 8 + 8 cells)
        #expect(patches(world).count == 21)
        R5.step(&world, 20) // tick 80: the corners, reached through neighbours only
        #expect(patches(world).count == 25)
        #expect(world.terrain[25, 12].kind == .foliage && !patches(world).contains(Vec2i(x: 25, y: 12)))
        R5.step(&world, 400)
        #expect(world.fireHazards.isEmpty)
        for y in 10...14 { for x in 20...24 { #expect(world.terrain[x, y].kind == .ground) } }
        #expect(world.terrain[25, 12].kind == .foliage)
    }
}
