import Testing
@testable import GameCore

/// GAME_RULES R5 §3 (walls and the damage strip) and §5–§6 (firing,
/// motion, shell contacts).
@Suite("R5 walls and the damage strip")
struct R5WallStripTests {
    @Test func normalRoundCutsATwoCellWideHalfCellDeepNotch() {
        var world = R5.world { R5.column(&$0, x: 10, .brick) }
        R5.step(&world, normal: true)
        R5.step(&world, R5.settle)
        #expect(world.terrain[10, 3].quadrantMask == 0b1010 && world.terrain[10, 4].quadrantMask == 0b1010)
        #expect(world.terrain[10, 2].quadrantMask == 0b1111 && world.terrain[10, 5].quadrantMask == 0b1111)
        #expect(world.projectiles.isEmpty)
        R5.step(&world, normal: true)
        R5.step(&world, R5.settle)
        #expect(world.terrain[10, 3].kind == .ground && world.terrain[10, 4].kind == .ground) // §3.4: two rounds
    }

    @Test func whiteBrickTakesTwoRoundsPerQuadrant() {
        var world = R5.world { R5.column(&$0, x: 10, .whiteBrick) }
        R5.step(&world, normal: true); R5.step(&world, R5.settle)
        #expect(world.terrain[10, 3].quadrantMask == 0b1111 && world.terrain[10, 3].crackMask == 0b0101)
        R5.step(&world, normal: true); R5.step(&world, R5.settle)
        #expect(world.terrain[10, 3].quadrantMask == 0b1010 && world.terrain[10, 3].crackMask == 0)
        R5.step(&world, normal: true); R5.step(&world, R5.settle)
        R5.step(&world, normal: true); R5.step(&world, R5.settle)
        #expect(world.terrain[10, 3].kind == .ground && world.terrain[10, 4].kind == .ground) // §3.4: four rounds
    }

    /// R5.4: AP cuts red brick two cells deep per round, then stops.
    @Test func apClearsTwoCellsOfRedBrickAndStops() {
        var world = R5.world {
            for x in 10...12 { R5.column(&$0, x: x, .brick) }
            R5.give(&$0, "ap", ammo: 1)
        }
        R5.step(&world, R5.settle, special: true)
        for x in 10...11 { #expect(world.terrain[x, 3].kind == .ground && world.terrain[x, 4].kind == .ground, "x \(x)") }
        #expect(world.terrain[12, 3].quadrantMask == 0b1111 && world.terrain[12, 4].quadrantMask == 0b1111)
        #expect(world.terrain[10, 2].quadrantMask == 0b1111) // still two cells wide
        #expect(world.projectiles.isEmpty)
    }

    /// R5.5: AP cuts white brick two cells deep as well; white brick still
    /// takes two rounds per quadrant, so two AP rounds open two cells.
    @Test func apCutsWhiteBrickTwoCellsDeepInTwoRounds() {
        var world = R5.world {
            for x in 10...12 { R5.column(&$0, x: x, .whiteBrick) }
            R5.give(&$0, "ap", ammo: 1)
        }
        R5.step(&world, R5.settle, special: true)
        for x in 10...11 { #expect(world.terrain[x, 3].quadrantMask == 0b1111 && world.terrain[x, 3].crackMask == 0b1111, "x \(x)") }
        #expect(world.terrain[12, 3].crackMask == 0)
        R5.give(&world, "ap", ammo: 1)
        R5.step(&world, R5.settle, special: true)
        for x in 10...11 { #expect(world.terrain[x, 3].kind == .ground && world.terrain[x, 4].kind == .ground, "x \(x)") }
        #expect(world.terrain[12, 3] == TerrainCell(kind: .whiteBrick))
    }

    /// The depth counts from the strip's contact face; in a column whose
    /// front is empty those empty quadrants spend depth, and the column's
    /// first material picks the limit (brick 4 rows, steel 2).
    @Test func stripDepthFollowsTheFirstMaterialFromTheFace() {
        func layout(_ kind: TerrainKind) -> WorldState {
            R5.world {
                $0.terrain[10, 3] = TerrainCell(kind: kind) // meets the shell: the contact face at x = 10 240
                for x in 11...12 { $0.terrain[x, 4] = TerrainCell(kind: kind) } // lower columns start one cell deeper
                R5.give(&$0, "ap", ammo: 1)
            }
        }
        var red = layout(.brick)
        R5.step(&red, R5.settle, special: true)
        #expect(red.terrain[10, 3].kind == .ground)
        #expect(red.terrain[11, 4].kind == .ground) // rows 3–4 of the lower columns
        #expect(red.terrain[12, 4].quadrantMask == 0b1111)
        var steel = layout(.steel)
        R5.step(&steel, R5.settle, special: true)
        #expect(steel.terrain[10, 3].kind == .ground)
        #expect(steel.terrain[11, 4].quadrantMask == 0b1111) // its two rows were spent on empty ground
    }

    @Test func greySteelYieldsOnlyToAPOneRoundPerCellAndWhiteSteelNever() {
        var world = R5.world { R5.column(&$0, x: 10, .steel) }
        R5.step(&world, normal: true); R5.step(&world, R5.settle)
        #expect(world.terrain[10, 3].quadrantMask == 0b1111) // normal: no effect
        R5.give(&world, "ap", ammo: 1)
        R5.step(&world, R5.settle, special: true)
        #expect(world.terrain[10, 3].kind == .ground && world.terrain[10, 4].kind == .ground)
        var white = R5.world { R5.column(&$0, x: 10, .whiteSteel); R5.give(&$0, "ap", ammo: 1) }
        R5.step(&white, R5.settle, special: true)
        #expect(white.terrain[10, 3] == TerrainCell(kind: .whiteSteel))
    }

    /// §3.2: a column passes only through its first material — steel right
    /// behind red brick is not touched by the same AP round.
    @Test func apDoesNotReachSteelBehindBrickInTheSameColumn() {
        var world = R5.world {
            R5.column(&$0, x: 10, .brick, mask: 0b1010) // right half only
            R5.column(&$0, x: 11, .steel)
            R5.give(&$0, "ap", ammo: 1)
        }
        R5.step(&world, R5.settle, special: true)
        #expect(world.terrain[10, 3].kind == .ground && world.terrain[10, 4].kind == .ground)
        #expect(world.terrain[11, 3].quadrantMask == 0b1111 && world.terrain[11, 4].quadrantMask == 0b1111)
    }

    /// §3.2: at a steel|brick seam a normal round still chips the brick
    /// columns; the steel columns stay whole.
    @Test func aSeamShotChipsTheBrickSideOnly() {
        var world = R5.world {
            $0.terrain[10, 3] = TerrainCell(kind: .steel)
            $0.terrain[10, 4] = TerrainCell(kind: .brick)
        }
        let events = R5.step(&world, R5.settle, normal: true)
        #expect(world.terrain[10, 3].quadrantMask == 0b1111)
        #expect(world.terrain[10, 4].quadrantMask == 0b1010)
        #expect(R5.destroyed(events, impact: .steel) == 1) // the contact quadrant was the steel one, (y, x) first
    }

    /// §3.2: the strip centres on the nearest half-cell boundary across the
    /// flight; off-lane it shifts by at most a quarter cell.
    @Test func offLaneShotsSnapTheStripToTheNearestHalfCell() {
        var world = R5.world {
            R5.column(&$0, x: 10, .brick)
            $0.withTanksInEntityOrder { $0.positionSubunits.y += 300 } // centre y 4396 → boundary 4608
        }
        R5.step(&world, R5.settle, normal: true)
        #expect(world.terrain[10, 3].quadrantMask == 0b1011) // bottom-left only
        #expect(world.terrain[10, 4].quadrantMask == 0b1010)
        #expect(world.terrain[10, 5].quadrantMask == 0b1110) // top-left only
    }

    /// §5.4: a muzzle already inside a wall hits that wall on the spawn tick.
    @Test func aMuzzleBuriedInAWallHitsAtOnce() {
        var world = R5.world {
            R5.column(&$0, x: 5, .brick)
            $0.withTanksInEntityOrder { $0.positionSubunits.x += 64 } // collision box flush, nominal box 64 inside
        }
        let events = R5.step(&world, normal: true)
        #expect(R5.fired(events) == 1)
        #expect(world.projectiles.isEmpty)
        #expect(world.terrain[5, 3].quadrantMask == 0b1010 && world.terrain[5, 4].quadrantMask == 0b1010)
    }
}

@Suite("R5 shell contacts")
struct R5ContactTests {
    /// §6.1 strength (owner 2026-09-15): the player's normal shell meets an
    /// enemy shell of each kind. Light shells cancel each other; AP and
    /// explosion shells fly on through a light shell; a fire shell bursts
    /// into flame where it meets any shell.
    @Test func aNormalShellMeetingEachEnemyShell() {
        for weapon in ["normal", "rapid", "ap", "explosion", "fire"] {
            var world = R5.world { R5.column(&$0, x: 30, .brick) }
            let enemyShell = R5.shell(&world, weapon, team: 2, center: Vec2i(x: 20 * 1024, y: 4096), direction: .left)
            var events: [DomainEvent] = []
            for i in 0..<(2 * R5.settle) where !events.contains(where: { if case .projectileDestroyed(_, _, _, .projectile) = $0 { true } else { false } }) {
                events += R5.step(&world, normal: i == 0)
            }
            let cancelled = events.compactMap { if case .projectileDestroyed(let id, _, _, .projectile) = $0 { id } else { nil } }
            switch weapon {
            case "normal", "rapid":
                #expect(cancelled.count == 2, "\(weapon)")
                #expect(world.projectiles.isEmpty && world.fireHazards.isEmpty, "\(weapon)")
            case "fire":
                #expect(cancelled.count == 2 && world.projectiles.isEmpty, "\(weapon)")
                #expect(!world.fireHazards.isEmpty && world.fireHazards.allSatisfy { $0.color == .orange }, "\(weapon)")
            default:
                #expect(cancelled.count == 1 && !cancelled.contains(enemyShell), "\(weapon)")
                #expect(world.projectiles.map(\.entityID) == [enemyShell], "\(weapon) flies on")
                #expect(!events.contains { if case .explosion = $0 { true } else { false } }, "\(weapon)")
            }
        }
    }

    /// Two heavy shells both end with their effects: an explosion shell
    /// blasts at the meeting point, AP simply ends.
    @Test func heavyShellsEndWithTheirEffects() {
        var world = R5.world()
        _ = R5.shell(&world, "explosion", team: 2, center: Vec2i(x: 30 * 1024, y: 12 * 1024), direction: .left)
        _ = R5.shell(&world, "ap", team: 1, center: Vec2i(x: 10 * 1024, y: 12 * 1024), direction: .right)
        var events: [DomainEvent] = []
        for _ in 0..<(2 * R5.settle) where !world.projectiles.isEmpty { events += R5.step(&world) }
        #expect(R5.destroyed(events, impact: .projectile) == 2)
        #expect(events.contains { if case .explosion = $0 { true } else { false } })
    }

    @Test func alliedTanksLetShellsThrough() {
        var world = R5.world { R5.column(&$0, x: 14, .brick) }
        let ally = world.spawnTank(teamID: 1, ownerPlayerID: nil, archetypeID: "normal_a",
                                   positionSubunits: Vec2i(x: 8 * 1024, y: 3 * 1024), facing: .up)
        world.withTank(entityID: ally) { $0.spawnProtectionTicks = 0 }
        R5.step(&world, R5.settle, normal: true)
        #expect(world.tank(entityID: ally)?.armor == 3)
        #expect(world.terrain[14, 3].quadrantMask == 0b1010)
    }

    @Test func apStopsOnTheFirstTankAndDealsItsPowerDamage() {
        var world = R5.world { R5.give(&$0, "ap", ammo: 1, power: 2) }
        let first = R5.enemy(&world, cellX: 8, cellY: 3, armor: 5)
        let second = R5.enemy(&world, cellX: 11, cellY: 3, armor: 5)
        R5.step(&world, R5.settle, special: true)
        #expect(world.tank(entityID: first)?.armor == 2) // LV2: 3 damage
        #expect(world.tank(entityID: second)?.armor == 5)
    }

    @Test func protectedTanksEndShellsWithoutDamage() {
        var world = R5.world()
        let enemy = R5.enemy(&world, cellX: 8, cellY: 3)
        world.withTank(entityID: enemy) { $0.spawnProtectionTicks = 200 }
        let events = R5.step(&world, R5.settle, normal: true)
        #expect(world.tank(entityID: enemy)?.armor == 1)
        #expect(R5.destroyed(events, impact: .deflected) == 1 && world.projectiles.isEmpty)
    }

    /// §6.2 table: shields absorb non-explosive hits without overflow.
    @Test func shieldsAbsorbWithoutOverflow() {
        var world = R5.world { R5.give(&$0, "ap", ammo: 1) }
        let heavy = R5.enemy(&world, cellX: 8, cellY: 3, archetype: "ap_c", armor: 6, shield: 2)
        R5.step(&world, R5.settle, special: true)
        #expect(world.tank(entityID: heavy)?.shieldHP == 0 && world.tank(entityID: heavy)?.armor == 6)
        R5.give(&world, "ap", ammo: 1)
        R5.step(&world, R5.settle, special: true)
        #expect(world.tank(entityID: heavy)?.armor == 4)
    }

    /// §6.3 / §11.1: every shell that meets the base costs it one point.
    @Test func theBaseLosesOnePointPerShellWhateverThePower() {
        var world = R5.world {
            $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 12 * 1024, y: 3 * 1024))
            R5.give(&$0, "ap", ammo: 1, power: 3)
        }
        R5.step(&world, R5.settle, special: true)
        #expect(world.base?.durability == 2)
        var casual = WeaponRuleset.provisional
        casual.alliedBaseDamage = false
        var immune = R5.world { $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 12 * 1024, y: 3 * 1024)) }
        let events = R5.step(&immune, R5.settle, normal: true, weapons: casual)
        #expect(immune.base?.durability == 3 && R5.destroyed(events, impact: .base) == 1) // still ends on the base
    }
}

@Suite("R5 firing channels and motion")
struct R5FiringTests {
    private func shotTicks(_ events: [(Int, [DomainEvent])], weapon: String? = nil) -> [Int] {
        events.filter { R5.fired($0.1, weapon: weapon) > 0 }.map(\.0)
    }

    private func run(_ world: inout WorldState, ticks: Int, normalAt: Set<Int> = [], specialHeld: (Int) -> Bool = { _ in false })
        -> [(Int, [DomainEvent])] {
        var log: [(Int, [DomainEvent])] = []
        for _ in 0..<ticks {
            let t = world.tick
            let events = Simulation.step(&world, commands: [PlayerCommand(
                playerID: .one, targetTick: t, normalFirePressed: normalAt.contains(t), specialFirePressed: specialHeld(t))])
            log.append((t, events))
        }
        return log
    }

    /// §5.1: a press during the cooldown is buffered for 10 ticks.
    @Test func aPressDuringCooldownIsBufferedTenTicks() {
        let cooldown = WeaponRuleset.provisional.weapon("normal")!.cooldownTicks[0]
        #expect(cooldown == 35) // R5.3
        var world = R5.world()
        let log = run(&world, ticks: cooldown + 16, normalAt: [0, cooldown - 9])
        #expect(shotTicks(log) == [0, cooldown])
        var late = R5.world()
        let lateLog = run(&late, ticks: cooldown + 16, normalAt: [0, cooldown - 11])
        #expect(shotTicks(lateLog) == [0])
        #expect(lateLog.contains { $0.0 == cooldown - 1 && $0.1.contains { if case .dryFire = $0 { true } else { false } } })
    }

    /// §5.1: resuming from a pause drops a buffered press.
    @Test func resumingDropsBufferedPresses() {
        let cooldown = WeaponRuleset.provisional.weapon("normal")!.cooldownTicks[0]
        var world = R5.world()
        _ = run(&world, ticks: cooldown - 2, normalAt: [0, cooldown - 5]) // buffered, would fire at the cooldown's end
        #expect(R5.player(world)?.normalFireBufferTicks ?? 0 > 0)
        let events = Simulation.step(&world, commands: [PlayerCommand(playerID: .one, targetTick: world.tick,
                                                                      sessionRequest: .continue)])
        #expect(R5.player(world)?.normalFireBufferTicks == 0)
        let later = run(&world, ticks: 20)
        #expect(R5.fired(events) == 0 && shotTicks(later).isEmpty)
    }

    /// §5.1: an empty special falls back to ONE normal round per press.
    @Test func anEmptySpecialFiresOneNormalRoundPerPress() {
        var world = R5.world { R5.give(&$0, "rapid", ammo: 0) }
        let log = run(&world, ticks: 120, specialHeld: { $0 < 60 || $0 >= 61 })
        #expect(shotTicks(log, weapon: "normal") == [0, 61])
        var loaded = R5.world { R5.give(&$0, "rapid", ammo: 3) }
        let loadedLog = run(&loaded, ticks: 90, specialHeld: { _ in true })
        #expect(shotTicks(loadedLog, weapon: "rapid").count == 3)
        #expect(shotTicks(loadedLog, weapon: "normal").isEmpty) // held through depletion: no new edge
    }

    /// §5.1: a refused shot starts no cooldown; the next legal tick fires.
    @Test func aCapFullAttemptStartsNoCooldown() {
        var world = R5.world { R5.give(&$0, "ap", ammo: 5) }
        let life = WeaponRuleset.provisional.weapon("ap")!.lifetimeTicks
        let log = run(&world, ticks: life + 34, specialHeld: { _ in true })
        #expect(shotTicks(log, weapon: "ap") == [0, life + 1]) // the slot frees at expiry, after that tick's firing step
        let dry = log.filter { $0.1.contains { if case .dryFire = $0 { true } else { false } } }.map(\.0)
        #expect(dry == Array(stride(from: 40, through: life, by: 30))) // cap-full from the end of the cooldown, every 30
    }

    /// §5.2: the exact integer integration — a normal round ends after its
    /// lifetime having travelled Σ(W₀ + k·a)/3 600 000 subunits.
    @Test func normalRoundTravelsItsIntegratedRangeAndExpires() {
        let normal = WeaponRuleset.provisional.weapon("normal")!
        var world = R5.world()
        let log = run(&world, ticks: normal.lifetimeTicks + 5, normalAt: [0])
        let expiry = log.first { $0.1.contains { if case .projectileDestroyed(_, _, _, .expired) = $0 { true } else { false } } }
        #expect(expiry?.0 == normal.lifetimeTicks)
        var total = 0, w = 60 * normal.initialSpeedMilliSubunitsPerSecond
        for _ in 1...normal.lifetimeTicks {
            w = max(0, min(60 * normal.maxSpeedMilliSubunitsPerSecond, w + normal.accelerationMilliSubunitsPerSecond2))
            total += w
        }
        let expected = 5120 + total / WeaponDefinition.travelUnitsPerSubunit
        let position = expiry?.1.compactMap { event -> Int? in
            if case .projectileDestroyed(_, _, let p, .expired) = event { return p.x }
            return nil
        }.first
        #expect(position == expected)
        #expect(abs(Double(expected - 5120) / 1024 - 26.95) < 0.15) // the §5.2 range, whatever the tempo
    }

    @Test func playerStartsAtSpeedLevelOneAndDrivesTheRuleSpeed() {
        #expect(PlayerState(playerID: .one).retainedSpeedLevel == 1)
        #expect(MovementRuleset.provisional.baseSpeedMilliSubunitsPerSecond == 1_966_080) // R5.2: 1.92 cells/s
        var world = R5.world()
        world.withTanksInEntityOrder { $0.speedLevel = 1 }
        R5.step(&world, 60, direction: .right)
        let perSecond = MovementRuleset.provisional.accumulatorIncrement(speedLevel: 1) * 60 / MovementRuleset.accumulatorUnitsPerSubunit
        #expect(R5.player(world)!.positionSubunits.x - 3072 == perSecond) // 2 477 su: 2.4192 cells/s
    }
}
