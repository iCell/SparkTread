/// Stage systems (M3): EnemyBrain intents (step 3), player respawn (step 4),
/// pickup collection (step 11), death/score/drops (step 12 extension),
/// EnemyDirector spawning (step 13), and win/loss resolution (step 14).
/// Deterministic: ascending entity order, named RNG streams only.
enum Stage {
    /// The weapon family an enemy archetype fights with (its own family).
    static func enemyFamily(_ archetypeID: String) -> String {
        String(archetypeID.split(separator: "_").first ?? "normal")
    }

    // MARK: - Step 3: EnemyBrain

    /// Emits internal TankIntents for enemy tanks (ADR-0002: never through
    /// the external command API). Movement re-decides on a per-enemy cadence
    /// by descending a deterministic cost field toward the chosen target
    /// (§10.4 — the base or the player; brick is dug through, steel and
    /// water are routed around); local steering resolves blocking tanks and
    /// a small wander slice keeps groups from grinding on one lane. Fire is
    /// evaluated every tick from alignment. Frozen enemies idle.
    static func computeIntents(
        _ world: inout WorldState, ruleset: MovementRuleset
    ) -> [Int: (normal: Bool, special: Bool)] {
        guard let stage = world.stage, stage.phase == .playing else { return [:] }
        var fire: [Int: (normal: Bool, special: Bool)] = [:]
        let playerTank = world.players.first.flatMap { p in
            p.tankEntityID.flatMap { id in world.tank(entityID: id) }
        }
        let footprint = SpatialUnits.standardTankFootprintSubunits
        for index in world.tanks.indices where world.tanks[index].ownerPlayerID == nil {
            var tank = world.tanks[index]
            guard tank.teamID != 1 else { continue }
            if tank.statusEffects["frozen"] != nil {
                tank.movementIntent = nil
                world.tanks[index] = tank
                continue
            }
            // Movement decision cadence, staggered by entity ID. Draw count
            // per decision is fixed (3) so the ai stream stays aligned.
            if (world.tick + tank.entityID * 13) % 30 == 0 {
                let roll = world.rng.ai.next(upperBound: 100)
                let jitter = world.rng.ai.next(upperBound: 4)
                let commit = world.rng.ai.next(upperBound: 100)
                let attributes = EnemyArchetypes.attributes(for: tank.archetypeID)
                // Flame cannot break brick (weapon data), so the fire family
                // routes around it; every other family digs.
                let canDig = enemyFamily(tank.archetypeID) != "fire"
                let targetCenter: Vec2i
                let goals: [Vec2i]
                if let base = world.base, roll < attributes.baseFocusPercent || playerTank == nil {
                    targetCenter = Vec2i(x: base.topLeftSubunits.x + base.sizeSubunits / 2,
                                         y: base.topLeftSubunits.y + base.sizeSubunits / 2)
                    goals = Navigation.baseApproachGoals(world, canDig: canDig)
                } else if let player = playerTank {
                    targetCenter = Vec2i(x: player.positionSubunits.x + footprint / 2,
                                         y: player.positionSubunits.y + footprint / 2)
                    goals = Navigation.nearGoals(world, around: Navigation.anchor(of: player.positionSubunits),
                                                 canDig: canDig)
                } else {
                    targetCenter = Vec2i(x: world.arena.widthSubunits / 2,
                                         y: world.arena.heightSubunits / 2)
                    goals = []
                }
                let selfCenter = Vec2i(x: tank.positionSubunits.x + footprint / 2,
                                       y: tank.positionSubunits.y + footprint / 2)
                let dx = targetCenter.x - selfCenter.x, dy = targetCenter.y - selfCenter.y
                let primary: Direction = abs(dx) >= abs(dy)
                    ? (dx >= 0 ? .right : .left)
                    : (dy >= 0 ? .down : .up)
                let secondary: Direction = abs(dx) >= abs(dy)
                    ? (dy >= 0 ? .down : .up)
                    : (dx >= 0 ? .right : .left)
                // Local steering: prefer the primary axis; a blocked forward
                // probe falls to the secondary, then a jittered legal turn
                // (Retreat/Reposition resolution is the jitter, §10.4).
                let field = Simulation.ObstacleField(world: world, excludingTank: tank.entityID)
                func freeFrom(_ origin: Vec2i, _ direction: Direction) -> Bool {
                    let probe = origin + direction.vector * 129
                    let inset = ruleset.collisionInsetSubunits
                    return !field.blocksTank(
                        minX: min(origin.x, probe.x) + inset,
                        minY: min(origin.y, probe.y) + inset,
                        maxX: max(origin.x, probe.x) + footprint - inset,
                        maxY: max(origin.y, probe.y) + footprint - inset)
                }
                /// A direction counts as free if the move is legal here OR
                /// from the lane the movement system would snap to (half- or
                /// full-cell, within the assist window), so a tank 20
                /// subunits off a dug opening does not think the opening is
                /// closed. This is an OPTIMISTIC APPROXIMATION of
                /// `Simulation.snapAssistedVectorIsFree`, not the same
                /// query: movement sweeps the lateral nudge and probes
                /// `2 * collisionInset + 1` ahead, while this checks the
                /// snapped endpoint's one-quadrant box and also tries the
                /// snap for same-axis travel. Authoritative movement still
                /// rejects any illegal move, so a wrong "free" costs at most
                /// a wasted decision, never tunnelling.
                func free(_ direction: Direction) -> Bool {
                    if freeFrom(tank.positionSubunits, direction) { return true }
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
                let all: [Direction] = [.up, .right, .down, .left]
                let legal = all.filter(free)
                // Reversing direction reads as "stuck jittering in a corner"
                // (owner report), so jittered turns avoid the about-face
                // unless it is the only legal move.
                func steer() -> Direction {
                    guard !legal.isEmpty else { return primary }
                    let forward = legal.filter { $0 != tank.facing.opposite }
                    let pool = forward.isEmpty ? legal : forward
                    return pool[jitter % pool.count]
                }
                // Course commitment only while it doesn't drive AWAY from
                // the target — otherwise a committed enemy cruises past the
                // base it rolled to attack.
                let keepCourse: Bool = {
                    guard let current = tank.movementIntent, free(current), commit < 55
                    else { return false }
                    let v = current.vector
                    return v.x * dx + v.y * dy >= 0
                }()
                // Dig mode (§10.4 BreakTerrain): a target direction blocked
                // by BRICK is still worth facing — stand at the wall and
                // shoot through. Without this an enemy above the fort just
                // slides away sideways and never sieges the base.
                func brickBlocked(_ direction: Direction) -> Bool {
                    guard canDig else { return false }
                    let probe = selfCenter + direction.vector
                        * (footprint / 2 + SpatialUnits.subunitsPerCell / 2)
                    let cx = probe.x / SpatialUnits.subunitsPerCell
                    let cy = probe.y / SpatialUnits.subunitsPerCell
                    return world.terrain.isInside(cellX: cx, cellY: cy)
                        && world.terrain[cx, cy].kind == .brick
                }
                // Cost-field descent (§10.4): the best neighbour anchor that
                // is free, or brick to dig through; a neighbour blocked by
                // another tank yields to the next-best, then to steering.
                let selfAnchor = Navigation.anchor(of: tank.positionSubunits)
                let costField = goals.isEmpty ? [] : Navigation.distanceField(world, goals: goals, canDig: canDig)
                let descent = costField.isEmpty ? []
                    : Navigation.descent(field: costField, world: world, anchor: selfAnchor,
                                         preferred: tank.facing, canDig: canDig)
                // Permissive digging heuristic: a neighbour that is free, or
                // brick this family can dig through, is taken; a neighbour
                // blocked only by another tank yields to the next option.
                let guided: Direction? = descent.first { free($0.direction) || brickBlocked($0.direction) }?.direction
                let atGoal = !costField.isEmpty && Navigation.isAtGoal(field: costField, world: world, anchor: selfAnchor)
                if roll >= 90 {
                    // Wander (§10.4): a slice of decisions roams instead of
                    // bee-lining, so enemies don't grind at the same wall.
                    tank.movementIntent = steer()
                } else if atGoal {
                    // In firing position: face the target and hold (the
                    // structure blocks the move; the fire pass does the rest).
                    tank.movementIntent = primary
                } else if let guided {
                    tank.movementIntent = guided
                } else if keepCourse {
                    // No field guidance (unreachable / at the goal): stay the
                    // course — classic drive-until-blocked feel.
                } else if free(primary) {
                    tank.movementIntent = primary
                } else if brickBlocked(primary) {
                    tank.movementIntent = primary // dig toward the target
                } else if free(secondary) {
                    tank.movementIntent = secondary
                } else {
                    tank.movementIntent = steer()
                }
            }

            // Fire evaluation every tick, throttled by a per-enemy duty
            // cycle (staggered by entity ID) so an aligned enemy squeezes
            // off single shots instead of hosing at the weapon's cooldown
            // cap. Rapid keeps a wider window — bursts are its identity.
            let cadencePhase = world.tick + tank.entityID * 11
            let family = enemyFamily(tank.archetypeID)
            let alignedWindowOpen = family == "rapid"
                ? cadencePhase % 32 < 16
                : cadencePhase % 48 < 12
            let breakWindowOpen = cadencePhase % 64 < 12
            var shouldFire = false
            let selfCenter = Vec2i(x: tank.positionSubunits.x + footprint / 2,
                                   y: tank.positionSubunits.y + footprint / 2)
            func aligned(with center: Vec2i) -> Bool {
                let dx = center.x - selfCenter.x, dy = center.y - selfCenter.y
                switch tank.facing {
                case .right: return dx > 0 && abs(dy) < footprint / 2
                case .left: return dx < 0 && abs(dy) < footprint / 2
                case .down: return dy > 0 && abs(dx) < footprint / 2
                case .up: return dy < 0 && abs(dx) < footprint / 2
                }
            }
            if alignedWindowOpen, let player = playerTank {
                shouldFire = aligned(with: Vec2i(x: player.positionSubunits.x + footprint / 2,
                                                 y: player.positionSubunits.y + footprint / 2))
            }
            if !shouldFire, alignedWindowOpen, let base = world.base {
                shouldFire = aligned(with: Vec2i(x: base.topLeftSubunits.x + base.sizeSubunits / 2,
                                                 y: base.topLeftSubunits.y + base.sizeSubunits / 2))
            }
            if !shouldFire, breakWindowOpen {
                // BreakTerrain: brick directly ahead within three cells.
                let probe = selfCenter + tank.facing.vector * (footprint / 2 + SpatialUnits.subunitsPerCell)
                let cx = probe.x / SpatialUnits.subunitsPerCell, cy = probe.y / SpatialUnits.subunitsPerCell
                if world.terrain.isInside(cellX: cx, cellY: cy),
                   world.terrain[cx, cy].kind == .brick {
                    shouldFire = true
                }
            }
            // Each family fights with its own weapon (§8, §10.6). Normal
            // uses the free normal channel; the rest use the special channel
            // carrying their family weapon. Mine layers drop mines on a
            // throttled roll while driving (reference 20% cadence, §9.1) and
            // still take basic shots when aligned.
            var pressNormal = false, pressSpecial = false
            switch family {
            case "normal":
                pressNormal = shouldFire
            case "mine":
                pressNormal = shouldFire
                if (world.tick + tank.entityID * 7) % 24 == 0 && world.rng.ai.next(upperBound: 5) == 0 {
                    pressSpecial = true // lay a mine (§9.1)
                }
            default: // rapid, fire, ap, explosion
                pressSpecial = shouldFire
            }
            if pressNormal || pressSpecial {
                fire[tank.entityID] = (normal: pressNormal, special: pressSpecial)
            }
            world.tanks[index] = tank
        }
        return fire
    }

    // MARK: - Step 4: player respawn

    static func processRespawns(
        _ world: inout WorldState, events: inout [DomainEvent]
    ) {
        guard let stage = world.stage, stage.phase == .playing else { return }
        for i in world.players.indices {
            var player = world.players[i]
            guard player.lifeState == .awaitingRespawn else { continue }
            player.respawnCountdownTicks -= 1
            guard player.respawnCountdownTicks <= 0 else {
                world.players[i] = player
                continue
            }
            // Nearest legal cell by deterministic ring scan (§6.5).
            let cell = SpatialUnits.subunitsPerCell
            let footprint = SpatialUnits.standardTankFootprintSubunits
            let field = Simulation.ObstacleField(world: world, excludingTank: -1)
            var position: Vec2i?
            for candidate in RingScan.cells(around: stage.playerRespawnCell, maxRadius: 6) {
                let p = Vec2i(x: candidate.x * cell, y: candidate.y * cell)
                if !field.blocksTank(minX: p.x + 64, minY: p.y + 64,
                                     maxX: p.x + footprint - 64, maxY: p.y + footprint - 64) {
                    position = p
                    break
                }
            }
            guard let position else { // fully blocked: retry next tick
                player.respawnCountdownTicks = 1
                world.players[i] = player
                continue
            }
            player.lifeState = .active
            player.respawnCountdownTicks = 0
            world.players[i] = player
            let id = world.spawnTank(teamID: 1, ownerPlayerID: player.playerID,
                                     archetypeID: "player", positionSubunits: position,
                                     facing: .up)
            // Retention (§6.5): upgrades persist; armor resets; protection on.
            world.withTank(entityID: id) {
                $0.speedLevel = player.retainedSpeedLevel
                $0.powerLevel = player.retainedPowerLevel
                $0.equipmentID = player.retainedEquipmentID
                $0.specialWeaponID = player.retainedSpecialWeaponID
                $0.armor = 3
            }
            events.append(.tankSpawned(entityID: id, ownerPlayerID: player.playerID,
                                       position: position, facing: .up))
        }
    }

    // MARK: - Step 11: pickup collection

    static func processPickups(
        _ world: inout WorldState, weapons: WeaponRuleset, rules: PickupRuleset,
        events: inout [DomainEvent]
    ) {
        let cell = SpatialUnits.subunitsPerCell
        let footprint = SpatialUnits.standardTankFootprintSubunits
        for i in world.pickups.indices {
            world.pickups[i].lifetimeRemainingTicks -= 1
            if world.pickups[i].graceTicksRemaining > 0 { world.pickups[i].graceTicksRemaining -= 1 }
        }
        var collected: [Int] = []
        for pickup in world.pickups {
            guard pickup.graceTicksRemaining == 0, pickup.lifetimeRemainingTicks > 0 else { continue }
            // Only player-owned tanks collect in V1 (§9.3; the Memory-of-Sea
            // enemy-collection reference behavior is ruleset-off). A tank
            // killed earlier this tick collects nothing.
            for tank in world.tanks where tank.ownerPlayerID != nil && tank.armor > 0 {
                let p = tank.positionSubunits
                let hx = pickup.positionSubunits.x - cell / 2, hy = pickup.positionSubunits.y - cell / 2
                guard p.x < hx + cell && p.x + footprint > hx
                    && p.y < hy + cell && p.y + footprint > hy else { continue }
                applyPickup(&world, pickup: pickup, toTank: tank.entityID,
                            weapons: weapons, rules: rules, events: &events)
                collected.append(pickup.entityID)
                break
            }
        }
        world.pickups.removeAll { collected.contains($0.entityID) || $0.lifetimeRemainingTicks <= 0 }
    }

    // MARK: - Fort ring (base shield, §6.6 / ADR-0010)

    /// The ring of cells around the 2×2 base (the fort walls): every
    /// in-bounds, non-border cell in the surrounding 4×4 box — 12 cells for
    /// an interior base, fewer when the base touches the border.
    static func baseFortRingCells(_ world: WorldState) -> [(x: Int, y: Int)] {
        guard let base = world.base else { return [] }
        let cell = SpatialUnits.subunitsPerCell
        let bx = base.topLeftSubunits.x / cell, by = base.topLeftSubunits.y / cell
        var ring: [(x: Int, y: Int)] = []
        for y in (by - 1)...(by + 2) {
            for x in (bx - 1)...(bx + 2) {
                if x >= bx && x <= bx + 1 && y >= by && y <= by + 1 { continue }
                guard x >= 1, x < world.arena.cellsWide - 1,
                      y >= 1, y < world.arena.cellsHigh - 1 else { continue }
                ring.append((x, y))
            }
        }
        return ring
    }

    /// Whether restoring terrain into this cell would entomb something
    /// (§6.6: never into a cell occupied by a tank, mine, or pickup).
    static func fortRingCellOccupied(
        _ world: WorldState, cellX: Int, cellY: Int, mineHalfExtent: Int
    ) -> Bool {
        let cell = SpatialUnits.subunitsPerCell
        let footprint = SpatialUnits.standardTankFootprintSubunits
        let minX = cellX * cell, minY = cellY * cell, maxX = minX + cell, maxY = minY + cell
        for tank in world.tanks {
            let p = tank.positionSubunits
            if p.x < maxX && p.x + footprint > minX && p.y < maxY && p.y + footprint > minY { return true }
        }
        for mine in world.mines {
            let p = mine.positionSubunits
            if p.x - mineHalfExtent < maxX && p.x + mineHalfExtent > minX
                && p.y - mineHalfExtent < maxY && p.y + mineHalfExtent > minY { return true }
        }
        for pickup in world.pickups
        where pickup.positionSubunits.x / cell == cellX && pickup.positionSubunits.y / cell == cellY {
            return true
        }
        return false
    }

    /// Shield activation hardens the fort ring to steel (reference shovel
    /// rule; owner decision). Occupied cells are skipped and simply keep
    /// their state. The pre-shield kinds are recorded once per activation
    /// (a refresh while shielded keeps the original record) so expiry can
    /// restore what was there.
    static func hardenBaseFortRing(
        _ world: inout WorldState, weapons: WeaponRuleset, events: inout [DomainEvent]
    ) {
        guard var base = world.base else { return }
        let ring = baseFortRingCells(world)
        if base.fortRingRestore.isEmpty {
            base.fortRingRestore = ring.map { world.terrain[$0.x, $0.y].kind }
        }
        world.base = base
        for (x, y) in ring
        where world.terrain[x, y] != TerrainCell(kind: .steel) // damaged steel is rebuilt whole
            && !fortRingCellOccupied(world, cellX: x, cellY: y, mineHalfExtent: weapons.mineHalfExtentSubunits) {
            world.terrain[x, y] = TerrainCell(kind: .steel)
            events.append(.terrainChanged(cellX: x, cellY: y,
                                          quadrantMask: world.terrain[x, y].quadrantMask))
        }
    }

    /// Shield expiry rebuilds the ring: with `fortRingRestoresRecordedKinds`
    /// (ADR-0010, owner decision B — the default) cells recorded as steel or
    /// water at activation come back as themselves and every other
    /// unoccupied cell becomes full brick; without it every unoccupied cell
    /// becomes full brick (the reference rebuilds the walls unconditionally).
    /// Occupied cells are skipped and keep their current state with no
    /// retry. Nothing happens when no hardening is pending.
    static func restoreBaseFortRing(
        _ world: inout WorldState, weapons: WeaponRuleset, rules: PickupRuleset,
        events: inout [DomainEvent]
    ) {
        guard var base = world.base, !base.fortRingRestore.isEmpty else { return }
        let ring = baseFortRingCells(world)
        for (i, (x, y)) in ring.enumerated() {
            let recorded: TerrainKind? = i < base.fortRingRestore.count ? base.fortRingRestore[i] : nil
            let preserved = rules.fortRingRestoresRecordedKinds && (recorded == .steel || recorded == .water)
            let target: TerrainKind = preserved ? recorded! : .brick
            guard !fortRingCellOccupied(world, cellX: x, cellY: y,
                                        mineHalfExtent: weapons.mineHalfExtentSubunits) else { continue }
            let current = world.terrain[x, y]
            if current.kind == target && current.quadrantMask == TerrainCell(kind: target).quadrantMask { continue }
            world.terrain[x, y] = TerrainCell(kind: target)
            events.append(.terrainChanged(cellX: x, cellY: y,
                                          quadrantMask: world.terrain[x, y].quadrantMask))
        }
        base.fortRingRestore = []
        world.base = base
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
        case "armor_up": withTank { $0.armor = min($0.maxArmor, $0.armor + min(rules.armorUpAmount, $0.maxArmor)) }
        case "power_up": withTank { $0.powerLevel = min(3, $0.powerLevel + 1) }
        case "level_up": withTank {
            $0.speedLevel = min(3, $0.speedLevel + 1)
            $0.powerLevel = min(3, $0.powerLevel + 1)
            $0.armor = min($0.maxArmor, $0.armor + 1)
        }
        case "max_speed_power": withTank { $0.speedLevel = 3; $0.powerLevel = 3 }
        case "amphi_tank", "anti_skid", "shield_of_moon", "memory_of_sea":
            withTank { $0.equipmentID = pickup.pickupID }
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
                // Refresh short, extend long (§6.6): additive with a floor.
                base.shieldRemainingTicks = rules.baseShieldTicks(afterPickupWith: base.shieldRemainingTicks)
                world.base = base
                // Reference shovel rule: the fort ring hardens to steel while
                // the shield lasts; expiry restores it (Simulation step 2).
                hardenBaseFortRing(&world, weapons: weapons, events: &events)
                events.append(.baseShieldChanged(active: true))
            }
        case "freeze_enemy":
            for i in world.tanks.indices where world.tanks[i].teamID != 1 {
                world.tanks[i].statusEffects["frozen"] = rules.freezeTicks
            }
        case "bomb":
            // Damages every qualified active enemy (§9.4): spawning and
            // invincible tanks are not qualified — the shared damage policy
            // deflects them; shields shatter first (bomb is explosion-class).
            for i in world.tanks.indices where world.tanks[i].teamID != 1 {
                Combat.applyTankDamage(&world, tankIndex: i, damage: rules.bombDamage,
                                       sourceWeaponID: "bomb", events: &events)
            }
        case "extra_life": withPlayer { $0.lives += 1 }
        case "max_armor_ammo":
            // Max armor, and the current special weapon filled to its cap
            // (reference "MAX Caisson / Armor"; §9.4), unlike ammo_crate's
            // single refill.
            withTank { $0.armor = $0.maxArmor }
            if let current = world.tank(entityID: tankID)?.specialWeaponID,
               let weapon = weapons.weapon(current) {
                withPlayer { $0.specialAmmoByWeapon[current] = weapon.maxAmmo }
            }
        case "ammo_crate":
            if let current = world.tank(entityID: tankID)?.specialWeaponID { refill(current) }
        case "rapid_weapon", "fire_weapon", "ap_weapon", "explosion_weapon", "mine_weapon":
            let weaponID = String(pickup.pickupID.dropLast("_weapon".count))
            withTank { $0.specialWeaponID = weaponID }
            withPlayer { $0.retainedSpecialWeaponID = weaponID }
            refill(weaponID)
        default:
            break
        }
        // Keep retained upgrades in sync for respawn (§6.5).
        if let tank = world.tank(entityID: tankID) {
            withPlayer {
                $0.retainedSpeedLevel = tank.speedLevel
                $0.retainedPowerLevel = tank.powerLevel
                $0.retainedEquipmentID = tank.equipmentID
                $0.retainedSpecialWeaponID = tank.specialWeaponID
            }
        }
    }

    // MARK: - Step 11 extension: hidden treasures

    /// Reveals treasures whose covering brick has been destroyed (the
    /// reference editor's hidden-treasure layer, §11): the covering cell
    /// counts as destroyed once it could hold a pickup — the same legality
    /// `spawnPickup` uses (destruction normalizes an emptied cell to
    /// `.ground`). A cell that merely changed material (fort hardening to
    /// steel) keeps the treasure hidden. The record is consumed only once the
    /// pickup was actually placed.
    static func revealHiddenPickups(
        _ world: inout WorldState, rules: PickupRuleset, events: inout [DomainEvent]
    ) {
        guard var stage = world.stage, !stage.hiddenPickups.isEmpty else { return }
        var revealed: [Int] = []
        for (i, hidden) in stage.hiddenPickups.enumerated() {
            guard world.terrain.isInside(cellX: hidden.cell.x, cellY: hidden.cell.y) else { continue }
            guard world.terrain[hidden.cell.x, hidden.cell.y].kind.canHoldPickup else { continue }
            if spawnPickup(&world, pickupID: hidden.pickupID, nearCell: hidden.cell,
                           rules: rules, events: &events) {
                revealed.append(i)
            }
        }
        for i in revealed.reversed() { stage.hiddenPickups.remove(at: i) }
        world.stage = stage
    }

    // MARK: - Step 12 extension: enemy score/drops and player lifecycle

    /// Called with the tanks that died this tick, before removal.
    static func processDeaths(
        _ world: inout WorldState, deadTanks: [TankState], rules: PickupRuleset,
        events: inout [DomainEvent]
    ) {
        guard let stage = world.stage else { return }
        let cell = SpatialUnits.subunitsPerCell
        for tank in deadTanks {
            if let ownerID = tank.ownerPlayerID {
                // Player death (§6.5).
                world.withPlayer(ownerID) { player in
                    player.retainedSpeedLevel = tank.speedLevel
                    player.retainedPowerLevel = tank.powerLevel
                    player.retainedEquipmentID = tank.equipmentID
                    player.retainedSpecialWeaponID = tank.specialWeaponID
                    if player.lives > 0 {
                        player.lives -= 1
                        player.lifeState = .awaitingRespawn
                        player.respawnCountdownTicks = 60
                    } else {
                        player.lifeState = .eliminated
                        events.append(.playerEliminated(playerID: ownerID))
                    }
                }
            } else if tank.teamID != 1 {
                // Enemy death: score and drop roll (drops stream, §9.3).
                let attributes = EnemyArchetypes.attributes(for: tank.archetypeID)
                for i in world.players.indices {
                    world.players[i].score += attributes.score
                }
                events.append(.scoreChanged(delta: attributes.score))
                let footprint = SpatialUnits.standardTankFootprintSubunits
                let originCell = Vec2i(x: (tank.positionSubunits.x + footprint / 2) / cell,
                                       y: (tank.positionSubunits.y + footprint / 2) / cell)
                if let carriedID = tank.carriedPickupID {
                    // Carrier rule (§11): the flashing tank's item drops —
                    // guaranteed, no roll — somewhere on the map (owner
                    // rule) or where it died (plan text), per the ruleset.
                    spawnDrop(&world, pickupID: carriedID, deathCell: originCell,
                              rules: rules, events: &events)
                } else if !stage.dropTable.isEmpty {
                    let roll = world.rng.drops.next(upperBound: 100)
                    let pickIndex = world.rng.drops.next(upperBound: stage.dropTable.count)
                    if roll < stage.dropChancePercent {
                        let pickupID = stage.dropTable[pickIndex]
                        spawnDrop(&world, pickupID: pickupID, deathCell: originCell,
                                  rules: rules, events: &events)
                    }
                }
            }
        }
    }

    /// A kill/carrier drop. Random policy (the reference rule): up to eight
    /// draws from the `drops` stream for an interior seed cell, each placed
    /// by the ring scan restricted to interior cells never under the base or
    /// a tank; then the same restricted scan around the death cell; if no
    /// such cell exists anywhere near, the item is lost (documented — only
    /// a map with no free interior cell can reach this). Plan policy
    /// (`dropsSpawnAtRandomCells == false`): the plan §9.3 text, the death
    /// cell by ring scan, tanks not excluded (the grace period handles them).
    static func spawnDrop(
        _ world: inout WorldState, pickupID: String, deathCell: Vec2i,
        rules: PickupRuleset, events: inout [DomainEvent]
    ) {
        guard rules.dropsSpawnAtRandomCells else {
            spawnPickup(&world, pickupID: pickupID, nearCell: deathCell, rules: rules, events: &events)
            return
        }
        let arena = world.arena
        for _ in 0..<8 {
            let x = 1 + world.rng.drops.next(upperBound: max(1, arena.cellsWide - 2))
            let y = 1 + world.rng.drops.next(upperBound: max(1, arena.cellsHigh - 2))
            if spawnPickup(&world, pickupID: pickupID, nearCell: Vec2i(x: x, y: y), rules: rules,
                           avoidTanks: true, interiorOnly: true, events: &events) {
                return
            }
        }
        spawnPickup(&world, pickupID: pickupID, nearCell: deathCell, rules: rules,
                    avoidTanks: true, interiorOnly: true, events: &events)
    }

    /// Whether a pickup at `cell` would sit under the base structure or, when
    /// asked, under a tank.
    private static func cellIsCoveredForPickup(_ world: WorldState, cell: Vec2i, avoidTanks: Bool) -> Bool {
        let size = SpatialUnits.subunitsPerCell
        let minX = cell.x * size, minY = cell.y * size
        if let base = world.base {
            let b = base.topLeftSubunits
            if minX < b.x + base.sizeSubunits && minX + size > b.x
                && minY < b.y + base.sizeSubunits && minY + size > b.y { return true }
        }
        if avoidTanks {
            let footprint = SpatialUnits.standardTankFootprintSubunits
            for tank in world.tanks {
                let p = tank.positionSubunits
                if minX < p.x + footprint && minX + size > p.x && minY < p.y + footprint && minY + size > p.y {
                    return true
                }
            }
        }
        return false
    }

    /// Places a pickup at the nearest free ground/ice/foliage cell by the
    /// deterministic ring scan — never under the base structure. Returns
    /// false when nothing within the scan radius can hold it (the caller
    /// keeps its record and retries later).
    @discardableResult
    static func spawnPickup(
        _ world: inout WorldState, pickupID: String, nearCell: Vec2i,
        rules: PickupRuleset, avoidTanks: Bool = false, interiorOnly: Bool = false,
        events: inout [DomainEvent]
    ) -> Bool {
        let cell = SpatialUnits.subunitsPerCell
        let arena = world.arena
        for candidate in RingScan.cells(around: nearCell, maxRadius: 4) {
            guard world.terrain.isInside(cellX: candidate.x, cellY: candidate.y) else { continue }
            if interiorOnly, candidate.x == 0 || candidate.y == 0
                || candidate.x == arena.cellsWide - 1 || candidate.y == arena.cellsHigh - 1 { continue }
            guard world.terrain[candidate.x, candidate.y].kind.canHoldPickup else { continue }
            guard !cellIsCoveredForPickup(world, cell: candidate, avoidTanks: avoidTanks) else { continue }
            let center = Vec2i(x: candidate.x * cell + cell / 2, y: candidate.y * cell + cell / 2)
            guard !world.pickups.contains(where: { $0.positionSubunits == center }) else { continue }
            let id = world.claimEntityID()
            world.pickups.append(PickupState(entityID: id, pickupID: pickupID, positionSubunits: center,
                                             lifetimeRemainingTicks: rules.pickupLifetimeTicks,
                                             graceTicksRemaining: rules.pickupGraceTicks))
            events.append(.pickupSpawned(entityID: id, pickupID: pickupID, position: center))
            return true
        }
        return false
    }

    // MARK: - Step 13: EnemyDirector

    static func runDirector(
        _ world: inout WorldState, events: inout [DomainEvent]
    ) {
        guard var stage = world.stage, stage.phase == .playing else { return }
        defer { world.stage = stage }

        if stage.enemyStartDelayTicks > 0 {
            stage.enemyStartDelayTicks -= 1
            return
        }
        let cell = SpatialUnits.subunitsPerCell
        let footprint = SpatialUnits.standardTankFootprintSubunits

        // Advance telegraphs (ascending entity order by construction).
        var spawnedIndices: [Int] = []
        for i in world.spawnTelegraphs.indices {
            var telegraph = world.spawnTelegraphs[i]
            telegraph.ticksRemaining -= 1
            if telegraph.ticksRemaining <= 0 {
                let field = Simulation.ObstacleField(world: world, excludingTank: -1)
                let p = telegraph.positionSubunits
                let blocked = field.blocksTank(minX: p.x + 64, minY: p.y + 64,
                                               maxX: p.x + footprint - 64, maxY: p.y + footprint - 64)
                if blocked {
                    // Deferred spawn (§6.8): hold, then rotate spawn point.
                    telegraph.deferTicks += 1
                    telegraph.ticksRemaining = 1
                    if telegraph.deferTicks >= 120 {
                        telegraph.spawnPointIndex = (telegraph.spawnPointIndex + 1) % stage.spawnPointsCells.count
                        let cellPos = stage.spawnPointsCells[telegraph.spawnPointIndex]
                        telegraph.positionSubunits = Vec2i(x: cellPos.x * cell, y: cellPos.y * cell)
                        telegraph.ticksRemaining = 15 // shortened re-telegraph
                        telegraph.deferTicks = 0
                    }
                } else {
                    let attributes = EnemyArchetypes.attributes(for: telegraph.archetypeID)
                    let id = world.spawnTank(teamID: 2, ownerPlayerID: nil,
                                             archetypeID: telegraph.archetypeID,
                                             positionSubunits: telegraph.positionSubunits,
                                             facing: .down)
                    world.withTank(entityID: id) {
                        $0.armor = attributes.armor
                        $0.maxArmor = attributes.armor
                        $0.shieldHP = attributes.shieldHP
                        $0.equipmentID = attributes.equipmentID
                        $0.speedLevel = attributes.speedLevel
                        $0.powerLevel = attributes.powerLevel
                        $0.specialWeaponID = enemyFamily(telegraph.archetypeID)
                        $0.spawnProtectionTicks = 30
                        $0.carriedPickupID = telegraph.carriedPickupID
                    }
                    events.append(.tankSpawned(entityID: id, ownerPlayerID: nil,
                                               position: telegraph.positionSubunits, facing: .down))
                    spawnedIndices.append(i)
                }
            }
            world.spawnTelegraphs[i] = telegraph
        }
        for i in spawnedIndices.reversed() { world.spawnTelegraphs.remove(at: i) }

        // Schedule new telegraphs up to the alive cap.
        let aliveEnemies = world.tanks.filter { $0.teamID != 1 }.count
        while !stage.spawnQueue.isEmpty,
              aliveEnemies + world.spawnTelegraphs.count < stage.maxAliveEnemies {
            let archetypeID = stage.spawnQueue.removeFirst()
            let carried = stage.carriedPickupQueue.isEmpty
                ? nil : stage.carriedPickupQueue.removeFirst()
            let pointIndex = stage.nextSpawnPointIndex % stage.spawnPointsCells.count
            stage.nextSpawnPointIndex += 1
            let cellPos = stage.spawnPointsCells[pointIndex]
            let id = world.claimEntityID()
            world.spawnTelegraphs.append(SpawnTelegraph(
                entityID: id, archetypeID: archetypeID, spawnPointIndex: pointIndex,
                positionSubunits: Vec2i(x: cellPos.x * cell, y: cellPos.y * cell),
                ticksRemaining: stage.telegraphTicks, carriedPickupID: carried))
            events.append(.enemyWaveStarted(archetypeID: archetypeID,
                                            position: Vec2i(x: cellPos.x * cell, y: cellPos.y * cell)))
        }
    }

    // MARK: - Step 14: win/loss

    /// Resolved after all damage and death events (§6.7). Simultaneity:
    /// base-zero on the last-enemy tick is a LOSS; player elimination on the
    /// last-enemy tick with a surviving base is a WIN (ruleset defaults).
    static func resolveObjective(
        _ world: inout WorldState, events: inout [DomainEvent]
    ) {
        guard var stage = world.stage, stage.phase == .playing else { return }
        defer { world.stage = stage }

        let baseAlive = (world.base?.durability ?? 0) > 0
        if !baseAlive {
            stage.phase = .lost
            events.append(.stageLost(reason: "base_destroyed"))
            return
        }
        let playerAlive = world.players.contains { $0.lifeState != .eliminated }
        let enemiesRemain = !stage.spawnQueue.isEmpty
            || !world.spawnTelegraphs.isEmpty
            || world.tanks.contains { $0.teamID != 1 }
        if !enemiesRemain {
            stage.phase = .won // includes the player-elimination-same-tick case
            events.append(.stageWon)
            return
        }
        if !playerAlive {
            stage.phase = .lost
            events.append(.stageLost(reason: "player_eliminated"))
        }
    }
}
