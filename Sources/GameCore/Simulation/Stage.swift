/// Stage systems: EnemyBrain intents, player respawn, pickups and their
/// placement queue, Flag On Guard, deaths and statistics, the enemy
/// director, and win/loss (GAME_RULES §9–§13). Deterministic: ascending
/// entity order, named RNG streams only.
enum Stage {
    /// The weapon family an enemy archetype fights with.
    static func enemyFamily(_ archetypeID: String) -> String {
        String(archetypeID.split(separator: "_").first ?? "normal")
    }

    /// §9.2: which wall materials a family's weapon can open.
    static func digAbility(family: String) -> Navigation.DigAbility {
        switch family {
        case "fire": Navigation.DigAbility(brick: false, steel: false)
        case "ap": Navigation.DigAbility(brick: true, steel: true)
        default: Navigation.DigAbility(brick: true, steel: false)
        }
    }

    // MARK: - Step 2: EnemyBrain

    static func computeIntents(
        _ world: inout WorldState, ruleset: MovementRuleset, weapons: WeaponRuleset
    ) -> [Int: (normal: Bool, special: Bool)] {
        guard let stage = world.stage, stage.phase == .playing else { return [:] }
        let profile = stage.enemyBehavior
        var fire: [Int: (normal: Bool, special: Bool)] = [:]
        let playerTank = world.players.first.flatMap { p in p.tankEntityID.flatMap { world.tank(entityID: $0) } }
        let footprint = SpatialUnits.standardTankFootprintSubunits
        let burning = Navigation.burningCells(world, hurtingTeam: 2)
        for index in world.tanks.indices where world.tanks[index].ownerPlayerID == nil {
            var tank = world.tanks[index]
            guard tank.teamID != 1, tank.armor > 0 else { continue }
            if tank.statusEffects["frozen"] != nil {
                tank.movementIntent = nil
                world.tanks[index] = tank
                continue
            }
            let family = enemyFamily(tank.archetypeID)
            let dig = digAbility(family: family)
            let selfCenter = Vec2i(x: tank.positionSubunits.x + footprint / 2, y: tank.positionSubunits.y + footprint / 2)

            if (world.tick + tank.entityID * 13) % max(1, profile.decisionIntervalTicks) == 0 {
                // Three draws per decision, in rule order: target, wander, keep course.
                let targetRoll = world.rng.ai.next(upperBound: 100)
                let wanderRoll = world.rng.ai.next(upperBound: 100)
                let commitRoll = world.rng.ai.next(upperBound: 100)
                let attributes = EnemyArchetypes.attributes(for: tank.archetypeID)
                let traversal = TraversalProfile(equipmentID: tank.equipmentID)
                let context = Navigation.Context(dig: dig, profile: traversal, burning: burning)
                let targetCenter: Vec2i
                let goals: [Vec2i]
                let baseFocus = min(100, max(0, attributes.baseFocusPercent * profile.baseFocusPercent / 100))
                if let base = world.base, targetRoll < baseFocus || playerTank == nil {
                    targetCenter = Vec2i(x: base.topLeftSubunits.x + base.sizeSubunits / 2,
                                         y: base.topLeftSubunits.y + base.sizeSubunits / 2)
                    goals = Navigation.baseApproachGoals(world, context: context)
                } else if let player = playerTank {
                    targetCenter = Vec2i(x: player.positionSubunits.x + footprint / 2,
                                         y: player.positionSubunits.y + footprint / 2)
                    goals = Navigation.nearGoals(world, around: Navigation.anchor(of: player.positionSubunits), context: context)
                } else {
                    targetCenter = Vec2i(x: world.arena.widthSubunits / 2, y: world.arena.heightSubunits / 2)
                    goals = []
                }
                let dx = targetCenter.x - selfCenter.x, dy = targetCenter.y - selfCenter.y
                let primary: Direction = abs(dx) >= abs(dy) ? (dx >= 0 ? .right : .left) : (dy >= 0 ? .down : .up)
                let secondary: Direction = abs(dx) >= abs(dy) ? (dy >= 0 ? .down : .up) : (dx >= 0 ? .right : .left)
                let field = Simulation.ObstacleField(world: world, excludingTank: tank.entityID,
                                                     movingWithInset: ruleset.collisionInsetSubunits)
                func freeFrom(_ origin: Vec2i, _ direction: Direction) -> Bool {
                    let probe = origin + direction.vector * 129
                    let inset = ruleset.collisionInsetSubunits
                    return !field.blocksTank(minX: min(origin.x, probe.x) + inset, minY: min(origin.y, probe.y) + inset,
                                             maxX: max(origin.x, probe.x) + footprint - inset,
                                             maxY: max(origin.y, probe.y) + footprint - inset)
                }
                /// Legal here or from the lane the movement system would snap
                /// to. The snap exists only for PERPENDICULAR turns (§4.2):
                /// counting it for a parallel candidate makes the AI believe
                /// in a sidestep movement will never take, so a tank pushed
                /// off-lane by another tank stalls against its blocker
                /// forever (owner stall report 2026-09-16).
                func free(_ direction: Direction) -> Bool {
                    if freeFrom(tank.positionSubunits, direction) { return true }
                    guard direction.isPerpendicular(to: tank.facing) else { return false }
                    let travelAxisIsX = direction == .up || direction == .down
                    let coordinate = travelAxisIsX ? tank.positionSubunits.x : tank.positionSubunits.y
                    for granularity in [SpatialUnits.subunitsPerQuadrant, SpatialUnits.subunitsPerCell] {
                        let lane = ((coordinate + granularity / 2) / granularity) * granularity
                        guard abs(lane - coordinate) <= ruleset.alignmentAssistWindowSubunits else { continue }
                        var snapped = tank.positionSubunits
                        if travelAxisIsX { snapped.x = lane } else { snapped.y = lane }
                        if freeFrom(snapped, direction) { return true }
                    }
                    return false
                }
                let legal = Direction.allCases.filter(free)
                func steer() -> Direction {
                    guard !legal.isEmpty else { return primary }
                    let forward = legal.filter { $0 != tank.facing.opposite }
                    let pool = forward.isEmpty ? legal : forward
                    return pool[wanderRoll % pool.count]
                }
                let keepCourse: Bool = {
                    guard let current = tank.movementIntent, free(current), commitRoll < profile.courseCommitPercent
                    else { return false }
                    let v = current.vector
                    return v.x * dx + v.y * dy >= 0
                }()
                /// A direction blocked by a wall this family can open is
                /// still worth facing: stand and shoot through. The probe is
                /// the same sweep the shot itself uses, so "worth facing"
                /// and "the shot will connect" can never disagree (a point
                /// probe past a thin wall left tanks standing without ever
                /// firing — owner stall report 2026-09-16).
                func wallAhead(_ direction: Direction) -> TerrainKind? {
                    guard let hit = Combat.firstSolidQuadrant(
                        world.terrain, from: selfCenter, vector: direction.vector,
                        remaining: footprint / 2 + SpatialUnits.subunitsPerCell,
                        half: weapons.projectileHalfExtentSubunits) else { return nil }
                    return world.terrain[hit.qx / 2, hit.qy / 2].kind
                }
                func diggable(_ direction: Direction) -> Bool {
                    wallAhead(direction).map(dig.opens) ?? false
                }
                let selfAnchor = Navigation.anchor(of: tank.positionSubunits)
                let costField = goals.isEmpty ? [] : Navigation.distanceField(world, goals: goals, context: context)
                let descent = costField.isEmpty ? []
                    : Navigation.descent(field: costField, world: world, anchor: selfAnchor,
                                         preferred: tank.facing, context: context)
                let guided = descent.first { free($0.direction) || diggable($0.direction) }?.direction
                let atGoal = !costField.isEmpty && Navigation.isAtGoal(field: costField, world: world, anchor: selfAnchor)
                if wanderRoll < profile.wanderPercent {
                    tank.movementIntent = steer()
                } else if atGoal {
                    tank.movementIntent = primary
                } else if let guided {
                    tank.movementIntent = guided
                } else if keepCourse {
                    // Stay the course.
                } else if free(primary) || diggable(primary) {
                    tank.movementIntent = primary
                } else if free(secondary) {
                    tank.movementIntent = secondary
                } else {
                    tank.movementIntent = steer()
                }
            }

            // Fire windows (§9.2), staggered by entity id and scaled by the
            // difficulty, then the shot conditions.
            guard tank.spawnProtectionTicks == 0 else { world.tanks[index] = tank; continue }
            let phase = world.tick + tank.entityID * 11
            func open(_ base: Int, of period: Int) -> Int { min(period, base * profile.fireWindowPercent / 100) }
            let alignedWindowOpen = family == "rapid" ? phase % 32 < open(16, of: 32) : phase % 48 < open(12, of: 48)
            let breakWindowOpen = phase % 64 < open(12, of: 64)
            let weaponID = family == "normal" ? "normal" : family
            let weapon = weapons.weapon(weaponID)
            func canDamage(_ kind: TerrainKind) -> Bool {
                guard let weapon else { return false }
                if weapon.family == .explosion { return kind.isBrickFamily }
                return weapon.damages(kind)
            }
            /// A shot at a target: the facing points at it within a cell of
            /// centre line, and the first wall on the way (if any) decides
            /// between the aligned window and the wall-breaking window.
            func shotAt(_ center: Vec2i) -> Bool {
                let dx = center.x - selfCenter.x, dy = center.y - selfCenter.y
                let along: Int
                switch tank.facing {
                case .right: guard dx > 0 && abs(dy) < footprint / 2 else { return false }; along = dx
                case .left: guard dx < 0 && abs(dy) < footprint / 2 else { return false }; along = -dx
                case .down: guard dy > 0 && abs(dx) < footprint / 2 else { return false }; along = dy
                case .up: guard dy < 0 && abs(dx) < footprint / 2 else { return false }; along = -dy
                }
                if let wall = Combat.firstSolidQuadrant(world.terrain, from: selfCenter, vector: tank.facing.vector,
                                                        remaining: max(0, along - footprint / 2),
                                                        half: weapons.projectileHalfExtentSubunits) {
                    return breakWindowOpen && canDamage(world.terrain[wall.qx / 2, wall.qy / 2].kind)
                }
                return alignedWindowOpen
            }
            var shouldFire = false
            if let player = playerTank {
                shouldFire = shotAt(Vec2i(x: player.positionSubunits.x + footprint / 2, y: player.positionSubunits.y + footprint / 2))
            }
            if !shouldFire, let base = world.base {
                shouldFire = shotAt(Vec2i(x: base.topLeftSubunits.x + base.sizeSubunits / 2,
                                          y: base.topLeftSubunits.y + base.sizeSubunits / 2))
            }
            if !shouldFire, breakWindowOpen {
                // Break terrain: a wall this weapon damages right ahead,
                // found by the shot's own sweep — a point probe one cell
                // past the muzzle skipped over adjacent thin walls, so the
                // tank stood facing a wall it never fired at (owner stall
                // report 2026-09-16).
                if let hit = Combat.firstSolidQuadrant(
                    world.terrain, from: selfCenter, vector: tank.facing.vector,
                    remaining: footprint / 2 + SpatialUnits.subunitsPerCell,
                    half: weapons.projectileHalfExtentSubunits),
                   canDamage(world.terrain[hit.qx / 2, hit.qy / 2].kind) {
                    shouldFire = true
                }
            }
            if shouldFire {
                fire[tank.entityID] = family == "normal" ? (normal: true, special: false) : (normal: false, special: true)
            }
            world.tanks[index] = tank
        }
        return fire
    }

    // MARK: - Step 2: player respawn

    static func processRespawns(_ world: inout WorldState, events: inout [DomainEvent]) {
        guard let stage = world.stage, stage.phase == .playing else { return }
        for i in world.players.indices {
            var player = world.players[i]
            guard player.lifeState == .awaitingRespawn else { continue }
            player.respawnCountdownTicks -= 1
            guard player.respawnCountdownTicks <= 0 else {
                world.players[i] = player
                continue
            }
            let cell = SpatialUnits.subunitsPerCell
            let footprint = SpatialUnits.standardTankFootprintSubunits
            let field = Simulation.ObstacleField(world: world, excludingTank: -1)
            var position: Vec2i?
            for candidate in RingScan.cells(around: stage.playerRespawnCell, maxRadius: 6) {
                let p = Vec2i(x: candidate.x * cell, y: candidate.y * cell)
                if !field.blocksTank(minX: p.x + 64, minY: p.y + 64, maxX: p.x + footprint - 64, maxY: p.y + footprint - 64) {
                    position = p
                    break
                }
            }
            guard let position else { // no room: stay pending, retry next tick
                player.respawnCountdownTicks = 1
                world.players[i] = player
                continue
            }
            player.lifeState = .active
            player.respawnCountdownTicks = 0
            world.players[i] = player
            let id = world.spawnTank(teamID: 1, ownerPlayerID: player.playerID, archetypeID: "player",
                                     positionSubunits: position, facing: .up)
            world.withTank(entityID: id) {
                $0.speedLevel = player.retainedSpeedLevel
                $0.powerLevel = player.retainedPowerLevel
                $0.equipmentID = player.retainedEquipmentID
                $0.specialWeaponID = player.retainedSpecialWeaponID
                $0.armor = LifecycleRules.playerRespawnArmor
                $0.spawnProtectionTicks = LifecycleRules.playerSpawnProtectionTicks
            }
            events.append(.tankSpawned(entityID: id, ownerPlayerID: player.playerID, position: position, facing: .up))
        }
    }

    // MARK: - Step 8: pickups

    static func processPickups(_ world: inout WorldState, weapons: WeaponRuleset, rules: PickupRuleset,
                               events: inout [DomainEvent]) {
        let footprint = SpatialUnits.standardTankFootprintSubunits
        var collected = Set<Int>()
        for pickup in world.pickups where pickup.graceTicksRemaining == 0 {
            let origin = Vec2i(x: pickup.cell.x * SpatialUnits.subunitsPerCell, y: pickup.cell.y * SpatialUnits.subunitsPerCell)
            for tank in world.tanks where tank.ownerPlayerID != nil && tank.armor > 0 {
                let p = tank.positionSubunits
                guard p.x < origin.x + pickup.sizeSubunits && p.x + footprint > origin.x
                    && p.y < origin.y + pickup.sizeSubunits && p.y + footprint > origin.y else { continue }
                applyPickup(&world, pickup: pickup, toTank: tank.entityID, weapons: weapons, rules: rules, events: &events)
                collected.insert(pickup.entityID)
                break
            }
        }
        world.pickups.removeAll { collected.contains($0.entityID) }
    }

    private static func applyPickup(
        _ world: inout WorldState, pickup: PickupState, toTank tankID: Int,
        weapons: WeaponRuleset, rules: PickupRuleset, events: inout [DomainEvent]
    ) {
        events.append(.pickupCollected(entityID: pickup.entityID, pickupID: pickup.pickupID,
                                       byTank: tankID, position: pickup.positionSubunits))
        guard let ownerID = world.tank(entityID: tankID)?.ownerPlayerID else { return }
        func withTank(_ body: (inout TankState) -> Void) { world.withTank(entityID: tankID, body) }
        func withPlayer(_ body: (inout PlayerState) -> Void) { world.withPlayer(ownerID, body) }
        func refill(_ weaponID: String) {
            guard let weapon = weapons.weapon(weaponID) else { return }
            withPlayer {
                let current = $0.specialAmmoByWeapon[weaponID, default: 0]
                $0.specialAmmoByWeapon[weaponID] = min(weapon.maxAmmo, current + weapon.refillAmount)
            }
        }
        func award(_ points: Int) {
            withPlayer { $0.score += points }
            events.append(.scoreChanged(delta: points))
        }
        switch pickup.pickupID {
        case "speed_up": withTank { $0.speedLevel = min(3, $0.speedLevel + 1) }
        case "armor_up": withTank { $0.armor = min($0.maxArmor, $0.armor + rules.armorUpAmount) }
        case "power_up": withTank { $0.powerLevel = min(3, $0.powerLevel + 1) }
        case "level_up": withTank {
            $0.speedLevel = min(3, $0.speedLevel + 1)
            $0.powerLevel = min(3, $0.powerLevel + 1)
            $0.armor = min($0.maxArmor, $0.armor + 1)
        }
        case "max_speed_power": withTank { $0.speedLevel = 3; $0.powerLevel = 3 }
        case "amphi_tank", "anti_skid":
            withTank { $0.equipmentID = pickup.pickupID }
            if pickup.pickupID != "amphi_tank", let tank = world.tank(entityID: tankID) {
                let box = Simulation.collisionBox(position: tank.positionSubunits, ruleset: .provisional)
                if world.terrain.waterOverlapArea(minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY) > 0 {
                    withTank { $0.leavingWater = true } // §4.4
                }
            }
            events.append(.equipmentChanged(entityID: tankID, equipmentID: pickup.pickupID))
        case "score_200": award(200)
        case "score_500": award(500)
        case "score_1000": award(1000)
        case "score_2000": award(2000)
        case "invincibility":
            withTank {
                let remaining = $0.statusEffects["invincible"] ?? 0
                $0.statusEffects["invincible"] = rules.invincibilityTicks(afterPickupWith: remaining)
            }
        case "base_shield":
            if var base = world.base {
                let wasActive = base.shieldRemainingTicks > 0
                base.shieldRemainingTicks = rules.baseShieldTicks(afterPickupWith: base.shieldRemainingTicks)
                world.base = base
                activateFort(&world, events: &events)
                if !wasActive { events.append(.baseShieldChanged(active: true)) }
            }
        case "freeze_enemy":
            for i in world.tanks.indices where world.tanks[i].teamID != 1 && world.tanks[i].armor > 0 {
                world.tanks[i].statusEffects["frozen"] = max(world.tanks[i].statusEffects["frozen"] ?? 0, rules.freezeTicks)
            }
        case "bomb":
            // §10.4: every spawned enemy outside spawn protection and
            // invincibility is cleared, shields ignored.
            for i in world.tanks.indices where world.tanks[i].teamID != 1 && world.tanks[i].armor > 0
                && !Combat.isProtected(world.tanks[i]) {
                let tank = world.tanks[i]
                world.tanks[i].armor = 0
                world.tanks[i].shieldHP = 0
                world.tanks[i].killedBy = KillAttribution(playerID: ownerID, byBomb: true)
                events.append(.tankDamaged(entityID: tank.entityID, ownerPlayerID: nil, damage: tank.armor,
                                           sourceWeaponID: "bomb", position: tank.positionSubunits))
            }
        case "extra_life":
            // Never past the state domain: the Training Arena starts at 999
            // reserves and a second 1UP used to break the invariant (a crash
            // in debug builds, owner report 2026-09-15).
            withPlayer { $0.lives = min(WorldInvariants.maxLives, $0.lives + 1) }
        case "max_armor_ammo":
            withTank { $0.armor = $0.maxArmor }
            if let current = world.tank(entityID: tankID)?.specialWeaponID, let weapon = weapons.weapon(current) {
                withPlayer { $0.specialAmmoByWeapon[current] = weapon.maxAmmo }
            }
        case "ammo_crate":
            if let current = world.tank(entityID: tankID)?.specialWeaponID { refill(current) }
        case "rapid_weapon", "fire_weapon", "ap_weapon", "explosion_weapon":
            let weaponID = String(pickup.pickupID.dropLast("_weapon".count))
            withTank { $0.specialWeaponID = weaponID }
            refill(weaponID)
        default:
            break
        }
        if let tank = world.tank(entityID: tankID) {
            withPlayer {
                $0.retainedSpeedLevel = tank.speedLevel
                $0.retainedPowerLevel = tank.powerLevel
                $0.retainedEquipmentID = tank.equipmentID
                $0.retainedSpecialWeaponID = tank.specialWeaponID
            }
        }
    }

    // MARK: - Pickup placement (§10.2)

    /// Whether a pickup may occupy the 2×2 area at `cell`: legal surface with
    /// no structure, and (when asked) clear of tanks, the base, spawn
    /// reservations, other pickups and fire.
    static func pickupAreaIsLegal(_ world: WorldState, cell: Vec2i, avoidDynamic: Bool) -> Bool {
        let size = SpatialUnits.subunitsPerCell
        for dy in 0..<2 {
            for dx in 0..<2 {
                let cx = cell.x + dx, cy = cell.y + dy
                guard world.terrain.isInside(cellX: cx, cellY: cy), world.terrain[cx, cy].canHoldPickup else { return false }
            }
        }
        guard avoidDynamic else { return true }
        let minX = cell.x * size, minY = cell.y * size, maxX = minX + 2 * size, maxY = minY + 2 * size
        func overlaps(_ x: Int, _ y: Int, _ w: Int) -> Bool { minX < x + w && maxX > x && minY < y + w && maxY > y }
        let footprint = SpatialUnits.standardTankFootprintSubunits
        if world.tanks.contains(where: { overlaps($0.positionSubunits.x, $0.positionSubunits.y, footprint) }) { return false }
        if let base = world.base, overlaps(base.topLeftSubunits.x, base.topLeftSubunits.y, base.sizeSubunits) { return false }
        if world.spawnTelegraphs.contains(where: { overlaps($0.positionSubunits.x, $0.positionSubunits.y, footprint) }) { return false }
        if world.pickups.contains(where: { overlaps($0.cell.x * size, $0.cell.y * size, $0.sizeSubunits) }) { return false }
        if world.fireHazards.contains(where: { $0.cell.x >= cell.x && $0.cell.x <= cell.x + 1 && $0.cell.y >= cell.y && $0.cell.y <= cell.y + 1 }) {
            return false
        }
        return true
    }

    static func placePickup(_ world: inout WorldState, pickupID: String, cell: Vec2i, critical: Bool,
                            graceTicks: Int, rules: PickupRuleset, events: inout [DomainEvent]) {
        let id = world.claimEntityID()
        let pickup = PickupState(entityID: id, pickupID: pickupID, cell: cell,
                                 lifetimeRemainingTicks: rules.pickupLifetimeTicks,
                                 graceTicksRemaining: graceTicks, critical: critical)
        world.pickups.append(pickup)
        events.append(.pickupSpawned(entityID: id, pickupID: pickupID, position: pickup.positionSubunits))
    }

    /// Queues a drop (§10.2); placement happens in step 8.
    static func requestPickup(_ world: inout WorldState, pickupID: String, critical: Bool,
                              preferredCell: Vec2i? = nil) {
        guard var stage = world.stage else { return }
        stage.pendingPickups.append(PendingPickup(requestID: stage.nextPickupRequestID, requestTick: world.tick,
                                                  pickupID: pickupID, critical: critical, preferredCell: preferredCell))
        stage.nextPickupRequestID += 1
        world.stage = stage
    }

    /// §10.5 brick drops (step 7, after the deaths' drops): every brick cell
    /// the player's rounds cleared this tick rolls once on the `drop`
    /// stream, in (y, x) order, until the stage's cap is reached — a capped
    /// stage rolls nothing more. A granted drop takes an entry of the drop
    /// table other than an extra life (lives are not farmed out of walls)
    /// and asks to be placed nearest the cleared cell. Fort cells and cells
    /// under a hidden pickup were never queued (Combat). The roll is one
    /// draw; the choice a second draw only when the roll succeeds.
    static func rollBrickDrops(_ world: inout WorldState) {
        guard var stage = world.stage, !stage.clearedBrickCells.isEmpty else { return }
        let cells = stage.clearedBrickCells.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        stage.clearedBrickCells = []
        world.stage = stage
        let table = stage.dropTable.filter { $0 != "extra_life" }
        for cell in cells {
            guard stage.brickDropsGranted < stage.brickDropCap, !table.isEmpty else { break }
            let roll = world.rng.drops.next(upperBound: 1000)
            guard roll < stage.brickDropChancePermille else { continue }
            let pick = world.rng.drops.next(upperBound: table.count)
            stage.brickDropsGranted += 1
            world.stage = stage
            requestPickup(&world, pickupID: table[pick], critical: false, preferredCell: cell)
            stage = world.stage ?? stage
        }
        world.stage = stage
    }

    /// Places queued drops at random legal interior areas the player can
    /// reach with the current equipment; waits while no player tank lives
    /// or no area qualifies.
    static func placePendingPickups(_ world: inout WorldState, ruleset: MovementRuleset, rules: PickupRuleset,
                                    events: inout [DomainEvent]) {
        guard var stage = world.stage, !stage.pendingPickups.isEmpty else { return }
        guard let player = world.players.first(where: { $0.active }),
              let tank = player.tankEntityID.flatMap({ world.tank(entityID: $0) }), tank.armor > 0 else { return }
        let reachable = Navigation.reachableLanes(world, from: tank, ruleset: ruleset)
        let lane = SpatialUnits.subunitsPerQuadrant
        let lanesWide = (world.arena.widthSubunits - SpatialUnits.standardTankFootprintSubunits) / lane + 1
        var remaining: [PendingPickup] = []
        for request in stage.pendingPickups.sorted(by: { ($0.requestTick, $0.requestID) < ($1.requestTick, $1.requestID) }) {
            var candidates: [Vec2i] = []
            if world.arena.cellsHigh >= 4 && world.arena.cellsWide >= 4 {
                for cy in 1...(world.arena.cellsHigh - 3) {
                    for cx in 1...(world.arena.cellsWide - 3) {
                        let laneIndex = (cy * 2) * lanesWide + cx * 2
                        guard reachable.contains(laneIndex),
                              pickupAreaIsLegal(world, cell: Vec2i(x: cx, y: cy), avoidDynamic: true) else { continue }
                        candidates.append(Vec2i(x: cx, y: cy))
                    }
                }
            }
            guard !candidates.isEmpty else {
                remaining.append(request)
                continue
            }
            // A brick drop lands where the brick was — the legal area whose
            // centre is nearest the cleared cell's, first in (y, x) on a tie,
            // and no draw is spent; every other request draws from the
            // candidates (§10.2).
            let pick: Vec2i
            if let near = request.preferredCell {
                func distance(_ c: Vec2i) -> Int { abs(2 * c.x + 2 - 2 * near.x - 1) + abs(2 * c.y + 2 - 2 * near.y - 1) }
                pick = candidates.min { (distance($0), $0.y, $0.x) < (distance($1), $1.y, $1.x) }!
            } else {
                pick = candidates[world.rng.drops.next(upperBound: candidates.count)]
            }
            placePickup(&world, pickupID: request.pickupID, cell: pick, critical: request.critical,
                        graceTicks: 0, rules: rules, events: &events)
        }
        stage = world.stage ?? stage
        stage.pendingPickups = remaining
        world.stage = stage
    }

    /// §10.2 hidden pickups: revealed in place once their 2×2 area holds no
    /// wall, with an avoidance window when a tank sits on them.
    static func revealHiddenPickups(_ world: inout WorldState, rules: PickupRuleset, events: inout [DomainEvent]) {
        guard var stage = world.stage, !stage.hiddenPickups.isEmpty else { return }
        let size = SpatialUnits.subunitsPerCell
        let footprint = SpatialUnits.standardTankFootprintSubunits
        var kept: [HiddenPickup] = []
        for hidden in stage.hiddenPickups {
            let cell = hidden.cell
            guard pickupAreaIsLegal(world, cell: cell, avoidDynamic: false),
                  !world.pickups.contains(where: { abs($0.cell.x - cell.x) < 2 && abs($0.cell.y - cell.y) < 2 }) else {
                kept.append(hidden)
                continue
            }
            let minX = cell.x * size, minY = cell.y * size
            let underTank = world.tanks.contains {
                minX < $0.positionSubunits.x + footprint && minX + footprint > $0.positionSubunits.x
                    && minY < $0.positionSubunits.y + footprint && minY + footprint > $0.positionSubunits.y
            }
            placePickup(&world, pickupID: hidden.pickupID, cell: cell, critical: hidden.critical,
                        graceTicks: underTank ? rules.revealGraceTicks : 0, rules: rules, events: &events)
        }
        stage = world.stage ?? stage
        stage.hiddenPickups = kept
        world.stage = stage
    }

    // MARK: - Flag On Guard (§11.2)

    /// Whether a quadrant of a template cell would bury a tank, a pickup or a
    /// spawn reservation.
    private static func quadrantOccupied(_ world: WorldState, cell: Vec2i, bit: Int) -> Bool {
        let q = SpatialUnits.subunitsPerQuadrant
        let minX = cell.x * 2 * q + (bit % 2) * q, minY = cell.y * 2 * q + (bit / 2) * q
        func overlaps(_ x: Int, _ y: Int, _ w: Int) -> Bool { minX < x + w && minX + q > x && minY < y + w && minY + q > y }
        let footprint = SpatialUnits.standardTankFootprintSubunits
        if world.tanks.contains(where: { overlaps($0.positionSubunits.x, $0.positionSubunits.y, footprint) }) { return true }
        if world.pickups.contains(where: { overlaps($0.cell.x * 2 * q, $0.cell.y * 2 * q, $0.sizeSubunits) }) { return true }
        if world.spawnTelegraphs.contains(where: { overlaps($0.positionSubunits.x, $0.positionSubunits.y, footprint) }) { return true }
        return false
    }

    /// A pickup starts or continues the cycle: the first one records the
    /// template's original cells; every one re-arms hardening.
    static func activateFort(_ world: inout WorldState, events: inout [DomainEvent]) {
        guard var base = world.base, let stage = world.stage else { return }
        if base.fortRecord.isEmpty {
            base.fortRecord = stage.fortTemplate
                .filter { world.terrain.isInside(cellX: $0.x, cellY: $0.y) }
                .map { FortCellRecord(cell: $0, original: world.terrain[$0.x, $0.y]) }
        } else {
            for i in base.fortRecord.indices { base.fortRecord[i].hardenedMask = 0 }
        }
        world.base = base
        hardenFort(&world, events: &events)
    }

    /// Step 1 each tick: harden while shielded, restore after.
    static func updateFort(_ world: inout WorldState, events: inout [DomainEvent]) {
        guard let base = world.base, !base.fortRecord.isEmpty else { return }
        if base.shieldRemainingTicks > 0 { hardenFort(&world, events: &events) } else { restoreFort(&world, events: &events) }
    }

    /// Hardens every template quadrant not hardened since the last pickup
    /// and not occupied; a quadrant broken after hardening stays broken.
    private static func hardenFort(_ world: inout WorldState, events: inout [DomainEvent]) {
        guard var base = world.base else { return }
        for i in base.fortRecord.indices {
            let record = base.fortRecord[i]
            guard record.original.kind != .whiteSteel else { continue }
            var newly = 0
            for bit in 0..<4 where record.hardenedMask & (1 << bit) == 0
                && !quadrantOccupied(world, cell: record.cell, bit: bit) {
                newly |= 1 << bit
            }
            guard newly != 0 else { continue }
            let current = world.terrain[record.cell.x, record.cell.y]
            let standing = current.kind.isWall ? current.quadrantMask : 0
            let surface: TerrainKind = current.surface == .water ? .ground : current.surface
            world.terrain[record.cell.x, record.cell.y] = TerrainCell(kind: .steel, quadrantMask: standing | newly, surface: surface)
            base.fortRecord[i].hardenedMask |= newly | standing
            events.append(.terrainChanged(cellX: record.cell.x, cellY: record.cell.y,
                                          quadrantMask: world.terrain[record.cell.x, record.cell.y].quadrantMask))
        }
        world.base = base
    }

    /// Restores template cells to their recorded state, quadrant by quadrant;
    /// what would bury something stays pending. The cycle ends when all match.
    private static func restoreFort(_ world: inout WorldState, events: inout [DomainEvent]) {
        guard var base = world.base else { return }
        var allRestored = true
        for record in base.fortRecord {
            let c = record.cell
            let current = world.terrain[c.x, c.y]
            let original = record.original
            if current == original { continue }
            var target = original
            if original.kind.isSolidStructure {
                let standing = current.kind.isSolidStructure ? current.quadrantMask : 0
                var blocked = 0
                for bit in 0..<4 where original.quadrantMask & (1 << bit) != 0 && standing & (1 << bit) == 0
                    && quadrantOccupied(world, cell: c, bit: bit) {
                    blocked |= 1 << bit
                }
                if blocked != 0 {
                    let mask = original.quadrantMask & ~blocked
                    target = mask == 0 ? TerrainCell(kind: original.surface == .water ? .ground : original.surface)
                        : TerrainCell(kind: original.kind, quadrantMask: mask, crackMask: original.crackMask, surface: original.surface)
                }
            } else if original.surface == .water {
                let size = SpatialUnits.subunitsPerCell
                let minX = c.x * size, minY = c.y * size
                let footprint = SpatialUnits.standardTankFootprintSubunits
                let buried = world.tanks.contains { tank in
                    TraversalProfile(equipmentID: tank.equipmentID) != .amphibious
                        && minX < tank.positionSubunits.x + footprint - 64 && minX + size > tank.positionSubunits.x + 64
                        && minY < tank.positionSubunits.y + footprint - 64 && minY + size > tank.positionSubunits.y + 64
                } || world.pickups.contains { minX < $0.cell.x * size + $0.sizeSubunits && minX + size > $0.cell.x * size
                    && minY < $0.cell.y * size + $0.sizeSubunits && minY + size > $0.cell.y * size }
                if buried { target = TerrainCell(kind: .ground) }
            }
            if target != current {
                world.terrain[c.x, c.y] = target
                events.append(.terrainChanged(cellX: c.x, cellY: c.y, quadrantMask: target.quadrantMask))
            }
            if target != original { allRestored = false }
        }
        if allRestored { base.fortRecord = [] }
        world.base = base
    }

    // MARK: - Step 7: deaths, score, drops, statistics

    static func processDeaths(_ world: inout WorldState, events: inout [DomainEvent]) {
        let dead = world.tanks.filter { $0.armor <= 0 }
        guard !dead.isEmpty else { return }
        for tank in dead {
            events.append(.tankDestroyed(entityID: tank.entityID, ownerPlayerID: tank.ownerPlayerID, position: tank.positionSubunits))
        }
        for tank in dead {
            if let ownerID = tank.ownerPlayerID {
                world.withPlayer(ownerID) { player in
                    player.retainedSpeedLevel = tank.speedLevel
                    player.retainedPowerLevel = tank.powerLevel
                    player.retainedEquipmentID = tank.equipmentID
                    player.retainedSpecialWeaponID = tank.specialWeaponID
                    if player.lives > 0 {
                        player.lives -= 1
                        player.lifeState = .awaitingRespawn
                        player.respawnCountdownTicks = LifecycleRules.playerRespawnDelayTicks
                    } else {
                        player.lifeState = .eliminated
                    }
                }
                if world.player(ownerID)?.lifeState == .eliminated {
                    events.append(.playerEliminated(playerID: ownerID))
                }
            } else if tank.teamID != 1 {
                let attributes = EnemyArchetypes.attributes(for: tank.archetypeID)
                if let killer = tank.killedBy, let playerID = killer.playerID {
                    let tick = world.tick
                    world.withPlayer(playerID) { player in
                        player.score += attributes.score
                        if !killer.byBomb {
                            if let last = player.lastComboKillTick, tick - last <= LifecycleRules.comboWindowTicks {
                                player.comboStreak += 1
                            } else {
                                player.comboStreak = 1
                            }
                            player.maxCombos = max(player.maxCombos, player.comboStreak)
                            player.lastComboKillTick = tick
                        }
                    }
                    events.append(.scoreChanged(delta: attributes.score))
                }
                if let carried = tank.carriedPickup {
                    requestPickup(&world, pickupID: carried.pickupID, critical: carried.critical)
                } else if let stage = world.stage, !stage.dropTable.isEmpty {
                    let roll = world.rng.drops.next(upperBound: 100)
                    let pick = world.rng.drops.next(upperBound: stage.dropTable.count)
                    if roll < stage.dropChancePercent {
                        requestPickup(&world, pickupID: stage.dropTable[pick], critical: false)
                    }
                }
            }
        }
        for tank in dead { world.removeTank(entityID: tank.entityID) }
    }

    // MARK: - Step 9: EnemyDirector (§9.3)

    static func runDirector(_ world: inout WorldState, ruleset: MovementRuleset, events: inout [DomainEvent]) {
        guard var stage = world.stage, stage.phase == .playing else { return }
        defer { world.stage = stage }
        if stage.enemyStartDelayTicks > 0 {
            stage.enemyStartDelayTicks -= 1
            return
        }
        if stage.spawnCooldownTicks > 0 { stage.spawnCooldownTicks -= 1 }
        let cell = SpatialUnits.subunitsPerCell
        let footprint = SpatialUnits.standardTankFootprintSubunits
        func reserved(_ pointIndex: Int, except telegraphID: Int? = nil) -> Bool {
            world.spawnTelegraphs.contains { $0.spawnPointIndex == pointIndex && $0.entityID != telegraphID }
        }

        var spawnedIDs = Set<Int>()
        for i in world.spawnTelegraphs.indices {
            var telegraph = world.spawnTelegraphs[i]
            telegraph.ticksRemaining -= 1
            if telegraph.ticksRemaining <= 0 {
                let field = Simulation.ObstacleField(world: world, excludingTank: -1, excludingTelegraph: telegraph.entityID)
                let p = telegraph.positionSubunits
                let inset = ruleset.collisionInsetSubunits
                if field.blocksTank(minX: p.x + inset, minY: p.y + inset,
                                    maxX: p.x + footprint - inset, maxY: p.y + footprint - inset) {
                    telegraph.deferTicks += 1
                    telegraph.ticksRemaining = 1
                    if telegraph.deferTicks >= LifecycleRules.spawnBlockedSwitchTicks, stage.spawnPointsCells.count > 1 {
                        let count = stage.spawnPointsCells.count
                        for offset in 1..<count {
                            let candidate = (telegraph.spawnPointIndex + offset) % count
                            guard !reserved(candidate, except: telegraph.entityID) else { continue }
                            telegraph.spawnPointIndex = candidate
                            let cellPos = stage.spawnPointsCells[candidate]
                            telegraph.positionSubunits = Vec2i(x: cellPos.x * cell, y: cellPos.y * cell)
                            telegraph.ticksRemaining = stage.telegraphTicks
                            telegraph.deferTicks = 0
                            break
                        }
                    }
                } else {
                    let attributes = EnemyArchetypes.attributes(for: telegraph.archetypeID)
                    let id = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: telegraph.archetypeID,
                                             positionSubunits: telegraph.positionSubunits, facing: .down)
                    world.withTank(entityID: id) {
                        $0.armor = attributes.armor
                        $0.maxArmor = attributes.armor
                        $0.shieldHP = attributes.shieldHP
                        $0.equipmentID = attributes.equipmentID
                        $0.speedLevel = attributes.speedLevel
                        $0.powerLevel = attributes.powerLevel
                        $0.specialWeaponID = enemyFamily(telegraph.archetypeID)
                        $0.spawnProtectionTicks = LifecycleRules.enemySpawnProtectionTicks
                        $0.carriedPickup = telegraph.carriedPickup
                    }
                    events.append(.tankSpawned(entityID: id, ownerPlayerID: nil, position: telegraph.positionSubunits, facing: .down))
                    spawnedIDs.insert(telegraph.entityID)
                }
            }
            world.spawnTelegraphs[i] = telegraph
        }
        world.spawnTelegraphs.removeAll { spawnedIDs.contains($0.entityID) }

        while stage.directorPhasesFired < stage.directorPhases.count,
              stage.directorPhases[stage.directorPhasesFired].afterSpawned <= stage.directorSpawned {
            let phase = stage.directorPhases[stage.directorPhasesFired]
            stage.directorPhasesFired += 1
            stage.spawnQueue.insert(contentsOf: phase.reinforcements, at: 0)
            if !stage.carriedPickupQueue.isEmpty {
                stage.carriedPickupQueue.insert(contentsOf: [CarriedPickup?](repeating: nil, count: phase.reinforcements.count), at: 0)
            }
            if let cap = phase.maxAliveEnemies { stage.maxAliveEnemies = cap }
            if phase.repairsBase, var base = world.base, base.durability > 0 {
                let restored = base.maxDurability - base.durability
                base.durability = base.maxDurability
                world.base = base
                if restored > 0 { events.append(.baseRepaired(restored: restored)) }
            }
            events.append(.directorPhaseStarted(id: phase.id, reinforcements: phase.reinforcements.count))
        }

        /// Starts one spawn process at the next unreserved point; false when
        /// every point is reserved.
        func startProcess() -> Bool {
            let count = stage.spawnPointsCells.count
            guard count > 0 else { return false }
            for offset in 0..<count {
                let pointIndex = (stage.nextSpawnPointIndex + offset) % count
                guard !reserved(pointIndex) else { continue }
                stage.nextSpawnPointIndex = (pointIndex + 1) % count
                let archetypeID = stage.spawnQueue.removeFirst()
                let carried = stage.carriedPickupQueue.isEmpty ? nil : stage.carriedPickupQueue.removeFirst()
                stage.directorSpawned += 1
                let cellPos = stage.spawnPointsCells[pointIndex]
                let position = Vec2i(x: cellPos.x * cell, y: cellPos.y * cell)
                world.spawnTelegraphs.append(SpawnTelegraph(
                    entityID: world.claimEntityID(), archetypeID: archetypeID, spawnPointIndex: pointIndex,
                    positionSubunits: position, ticksRemaining: stage.telegraphTicks, carriedPickup: carried))
                events.append(.enemyWaveStarted(archetypeID: archetypeID, position: position))
                return true
            }
            return false
        }
        func roomForAnother() -> Bool {
            !stage.spawnQueue.isEmpty
                && world.tanks.filter({ $0.teamID != 1 }).count + world.spawnTelegraphs.count < stage.maxAliveEnemies
        }
        if !stage.firstWaveStarted {
            // The first wave starts together at distinct points.
            stage.firstWaveStarted = true
            while roomForAnother(), startProcess() {}
            stage.spawnCooldownTicks = LifecycleRules.spawnCadenceTicks
        } else if stage.spawnCooldownTicks == 0, roomForAnother(), startProcess() {
            stage.spawnCooldownTicks = LifecycleRules.spawnCadenceTicks
        }
    }

    // MARK: - Step 9: win/loss (§11.4)

    static func resolveObjective(_ world: inout WorldState, events: inout [DomainEvent]) {
        guard var stage = world.stage, stage.phase == .playing else { return }
        defer { world.stage = stage }

        if (world.base?.durability ?? 0) <= 0 {
            stage.phase = .lost
            events.append(.stageLost(reason: "base_destroyed"))
            return
        }
        let activePlayers = world.players.filter(\.active)
        if !activePlayers.isEmpty, activePlayers.allSatisfy({ $0.lifeState == .eliminated }) {
            stage.phase = .lost
            events.append(.stageLost(reason: "player_eliminated"))
            return
        }
        let unfiredReinforcements = stage.directorPhases.dropFirst(stage.directorPhasesFired).contains { !$0.reinforcements.isEmpty }
        let enemiesRemain = !stage.spawnQueue.isEmpty || !world.spawnTelegraphs.isEmpty
            || world.tanks.contains { $0.teamID != 1 } || unfiredReinforcements
        if !enemiesRemain {
            stage.phase = .won
            events.append(.stageWon)
            let bonus = stage.clearBonus
            if bonus.total > 0 {
                for i in world.players.indices where world.players[i].active {
                    world.players[i].score += bonus.total
                }
                events.append(.stageClearBonus(tally: bonus.tally, reward: bonus.reward))
            }
        }
    }
}
