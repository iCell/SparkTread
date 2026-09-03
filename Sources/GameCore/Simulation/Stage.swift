/// Stage systems (M3): EnemyBrain intents (step 3), player respawn (step 4),
/// pickup collection (step 11), death/score/drops (step 12 extension),
/// EnemyDirector spawning (step 13), and win/loss resolution (step 14).
/// Deterministic: ascending entity order, named RNG streams only.
enum Stage {
    // MARK: - Step 3: EnemyBrain

    /// Emits internal TankIntents for enemy tanks (ADR-0002: never through
    /// the external command API). Movement re-decides on a per-enemy cadence;
    /// fire is evaluated every tick from alignment. Frozen enemies idle.
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
            // per decision is fixed (2) so the ai stream stays aligned.
            if (world.tick + tank.entityID * 13) % 30 == 0 {
                let roll = world.rng.ai.next(upperBound: 100)
                let jitter = world.rng.ai.next(upperBound: 4)
                let attributes = EnemyArchetypes.attributes(for: tank.archetypeID)
                let targetCenter: Vec2i
                if let base = world.base, roll < attributes.baseFocusPercent || playerTank == nil {
                    targetCenter = Vec2i(x: base.topLeftSubunits.x + base.sizeSubunits / 2,
                                         y: base.topLeftSubunits.y + base.sizeSubunits / 2)
                } else if let player = playerTank {
                    targetCenter = Vec2i(x: player.positionSubunits.x + footprint / 2,
                                         y: player.positionSubunits.y + footprint / 2)
                } else {
                    targetCenter = Vec2i(x: world.arena.widthSubunits / 2,
                                         y: world.arena.heightSubunits / 2)
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
                func free(_ direction: Direction) -> Bool {
                    let probe = tank.positionSubunits + direction.vector * 129
                    let inset = ruleset.collisionInsetSubunits
                    return !field.blocksTank(
                        minX: min(tank.positionSubunits.x, probe.x) + inset,
                        minY: min(tank.positionSubunits.y, probe.y) + inset,
                        maxX: max(tank.positionSubunits.x, probe.x) + footprint - inset,
                        maxY: max(tank.positionSubunits.y, probe.y) + footprint - inset)
                }
                if free(primary) {
                    tank.movementIntent = primary
                } else if free(secondary) {
                    tank.movementIntent = secondary
                } else {
                    let all: [Direction] = [.up, .right, .down, .left]
                    let legal = all.filter(free)
                    tank.movementIntent = legal.isEmpty ? primary : legal[jitter % legal.count]
                }
            }

            // Fire evaluation every tick: shoot when roughly aligned with the
            // player or base along the facing axis, or to break terrain ahead.
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
            if let player = playerTank {
                shouldFire = aligned(with: Vec2i(x: player.positionSubunits.x + footprint / 2,
                                                 y: player.positionSubunits.y + footprint / 2))
            }
            if !shouldFire, let base = world.base {
                shouldFire = aligned(with: Vec2i(x: base.topLeftSubunits.x + base.sizeSubunits / 2,
                                                 y: base.topLeftSubunits.y + base.sizeSubunits / 2))
            }
            if !shouldFire {
                // BreakTerrain: brick directly ahead within three cells.
                let probe = selfCenter + tank.facing.vector * (footprint / 2 + SpatialUnits.subunitsPerCell)
                let cx = probe.x / SpatialUnits.subunitsPerCell, cy = probe.y / SpatialUnits.subunitsPerCell
                if world.terrain.isInside(cellX: cx, cellY: cy),
                   world.terrain[cx, cy].kind == .brick {
                    shouldFire = true
                }
            }
            if shouldFire { fire[tank.entityID] = (normal: true, special: false) }
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
            events.append(.tankSpawned(entityID: id, position: position, facing: .up))
        }
    }

    // MARK: - Step 11: pickup collection

    static func processPickups(
        _ world: inout WorldState, weapons: WeaponRuleset, events: inout [DomainEvent]
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
            // enemy-collection reference behavior is ruleset-off).
            for tank in world.tanks where tank.ownerPlayerID != nil {
                let p = tank.positionSubunits
                let hx = pickup.positionSubunits.x - cell / 2, hy = pickup.positionSubunits.y - cell / 2
                guard p.x < hx + cell && p.x + footprint > hx
                    && p.y < hy + cell && p.y + footprint > hy else { continue }
                applyPickup(&world, pickup: pickup, toTank: tank.entityID,
                            weapons: weapons, events: &events)
                collected.append(pickup.entityID)
                break
            }
        }
        world.pickups.removeAll { collected.contains($0.entityID) || $0.lifetimeRemainingTicks <= 0 }
    }

    private static func applyPickup(
        _ world: inout WorldState, pickup: PickupState, toTank tankID: Int,
        weapons: WeaponRuleset, events: inout [DomainEvent]
    ) {
        events.append(.pickupCollected(entityID: pickup.entityID, pickupID: pickup.pickupID,
                                       byTank: tankID))
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
        switch pickup.pickupID {
        case "speed_up": withTank { $0.speedLevel = min(3, $0.speedLevel + 1) }
        case "armor_up": withTank { $0.armor = min($0.maxArmor, $0.armor + 2) }
        case "power_up": withTank { $0.powerLevel = min(3, $0.powerLevel + 1) }
        case "level_up": withTank {
            $0.speedLevel = min(3, $0.speedLevel + 1)
            $0.powerLevel = min(3, $0.powerLevel + 1)
            $0.armor = min($0.maxArmor, $0.armor + 1)
        }
        case "max_speed_power": withTank { $0.speedLevel = 3; $0.powerLevel = 3 }
        case "amphi_tank", "anti_skid", "shield_of_moon", "memory_of_sea":
            withTank { $0.equipmentID = pickup.pickupID == "amphi_tank" ? "amphi_tank" : pickup.pickupID }
            events.append(.equipmentChanged(entityID: tankID, equipmentID: pickup.pickupID))
        case "invincibility": withTank { $0.statusEffects["invincible"] = 600 }
        case "base_shield":
            if var base = world.base {
                // Refresh short, extend long (§6.6): additive with a floor.
                base.shieldRemainingTicks = max(base.shieldRemainingTicks + 300, 600)
                world.base = base
                events.append(.baseShieldChanged(active: true))
            }
        case "freeze_enemy":
            for i in world.tanks.indices where world.tanks[i].teamID != 1 {
                world.tanks[i].statusEffects["frozen"] = 480
            }
        case "bomb":
            // Damages every active (non-telegraph) enemy.
            for i in world.tanks.indices where world.tanks[i].teamID != 1 {
                world.tanks[i].armor -= 3
                events.append(.tankDamaged(entityID: world.tanks[i].entityID, damage: 3,
                                           sourceWeaponID: "bomb"))
            }
        case "extra_life": withPlayer { $0.lives += 1 }
        case "max_armor_ammo":
            withTank { $0.armor = $0.maxArmor }
            if let current = world.tank(entityID: tankID)?.specialWeaponID { refill(current) }
        case "ammo_crate":
            if let current = world.tank(entityID: tankID)?.specialWeaponID { refill(current) }
        case "rapid_weapon", "fire_weapon", "ap_weapon", "explosion_weapon", "mine_weapon":
            let weaponID = String(pickup.pickupID.dropLast("_weapon".count))
            withTank { $0.specialWeaponID = weaponID }
            withPlayer { $0.retainedSpecialWeaponID = weaponID }
            refill(weaponID)
        default:
            break // score pickups arrive with the results milestone
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

    // MARK: - Step 12 extension: enemy score/drops and player lifecycle

    /// Called with the tanks that died this tick, before removal.
    static func processDeaths(
        _ world: inout WorldState, deadTanks: [TankState], events: inout [DomainEvent]
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
                if !stage.dropTable.isEmpty {
                    let roll = world.rng.drops.next(upperBound: 100)
                    let pickIndex = world.rng.drops.next(upperBound: stage.dropTable.count)
                    if roll < stage.dropChancePercent {
                        let pickupID = stage.dropTable[pickIndex]
                        let footprint = SpatialUnits.standardTankFootprintSubunits
                        let originCell = Vec2i(x: (tank.positionSubunits.x + footprint / 2) / cell,
                                               y: (tank.positionSubunits.y + footprint / 2) / cell)
                        spawnPickup(&world, pickupID: pickupID, nearCell: originCell, events: &events)
                    }
                }
            }
        }
    }

    static func spawnPickup(
        _ world: inout WorldState, pickupID: String, nearCell: Vec2i,
        events: inout [DomainEvent]
    ) {
        let cell = SpatialUnits.subunitsPerCell
        for candidate in RingScan.cells(around: nearCell, maxRadius: 4) {
            guard world.terrain.isInside(cellX: candidate.x, cellY: candidate.y) else { continue }
            let kind = world.terrain[candidate.x, candidate.y].kind
            guard kind == .ground || kind == .ice || kind == .foliage else { continue }
            let center = Vec2i(x: candidate.x * cell + cell / 2, y: candidate.y * cell + cell / 2)
            guard !world.pickups.contains(where: { $0.positionSubunits == center }) else { continue }
            let id = world.claimEntityID()
            world.pickups.append(PickupState(entityID: id, pickupID: pickupID, positionSubunits: center))
            events.append(.pickupSpawned(entityID: id, pickupID: pickupID, position: center))
            return
        }
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
                        $0.speedLevel = attributes.speedLevel
                        $0.powerLevel = attributes.powerLevel
                        $0.spawnProtectionTicks = 30
                    }
                    events.append(.tankSpawned(entityID: id, position: telegraph.positionSubunits,
                                               facing: .down))
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
            let pointIndex = stage.nextSpawnPointIndex % stage.spawnPointsCells.count
            stage.nextSpawnPointIndex += 1
            let cellPos = stage.spawnPointsCells[pointIndex]
            let id = world.claimEntityID()
            world.spawnTelegraphs.append(SpawnTelegraph(
                entityID: id, archetypeID: archetypeID, spawnPointIndex: pointIndex,
                positionSubunits: Vec2i(x: cellPos.x * cell, y: cellPos.y * cell),
                ticksRemaining: stage.telegraphTicks))
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
