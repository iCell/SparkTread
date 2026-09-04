/// Combat phases of the tick (§13.6 steps 6–12) and the §8.5 collision
/// matrix. Every category has explicit, documented semantics — an unlisted
/// collision is a defect, not an implicit no-op. Deterministic throughout:
/// ascending entity IDs, parametric-entry order along swept segments,
/// breadth-first chain detonation capped at `chainDetonationWaveCap`.
enum Combat {
    // MARK: - Entry point

    static func run(
        _ world: inout WorldState,
        firePressed: [PlayerID: (normal: Bool, special: Bool)],
        aiFire: [Int: (normal: Bool, special: Bool)] = [:],
        movement: MovementRuleset,
        weapons: WeaponRuleset,
        events: inout [DomainEvent]
    ) {
        // 6–7. Fire requests, then spawns. Spawned projectiles do not
        // advance in step 8 of the same tick (§13.6 clarification).
        let spawnedThisTick = processFireRequests(
            &world, firePressed: firePressed, aiFire: aiFire, weapons: weapons, events: &events)

        // 8. Advance projectiles and continuous hazards.
        var segments: [Int: (from: Vec2i, to: Vec2i)] = [:]
        for i in world.projectiles.indices {
            var p = world.projectiles[i]
            guard !spawnedThisTick.contains(p.entityID) else { continue }
            guard let weapon = weapons.weapon(p.weaponID) else { continue }
            p.speedSubunitsPerTick = min(
                p.speedSubunitsPerTick + weapon.level(weapon.accelerationSubunitsPerTick2, p.powerLevel),
                weapon.level(weapon.maxSpeedSubunitsPerTick, p.powerLevel))
            let from = p.positionSubunits
            p.positionSubunits = from + p.direction.vector * p.speedSubunitsPerTick
            p.lifetimeRemainingTicks -= 1
            segments[p.entityID] = (from, p.positionSubunits)
            world.projectiles[i] = p
        }
        for i in world.fireHazards.indices { world.fireHazards[i].lifetimeRemainingTicks -= 1 }
        for i in world.mines.indices where world.mines[i].phase == .arming {
            world.mines[i].phaseTicksRemaining -= 1
            if world.mines[i].phaseTicksRemaining <= 0 { world.mines[i].phase = .armed }
        }

        // 9–10. Collision candidates and resolution.
        var explosionQueue: [Explosion] = []
        var destroyedProjectiles = Set<Int>()

        for id in world.projectiles.map(\.entityID) {
            guard !destroyedProjectiles.contains(id), let segment = segments[id] else { continue }
            resolveProjectileSweep(
                &world, projectileID: id, segment: segment, weapons: weapons,
                explosions: &explosionQueue, destroyed: &destroyedProjectiles, events: &events)
        }
        resolveProjectileVsProjectile(
            &world, segments: segments, weapons: weapons,
            explosions: &explosionQueue, destroyed: &destroyedProjectiles, events: &events)
        resolveMineTriggers(&world, weapons: weapons, explosions: &explosionQueue, events: &events)
        resolveFireHazardDamage(&world, weapons: weapons, events: &events)
        resolveExplosions(&world, queue: explosionQueue, weapons: weapons,
                          destroyedProjectiles: &destroyedProjectiles, events: &events)

        // Lifetime expiry: explosion-family projectiles detonate; others fade.
        var expiryExplosions: [Explosion] = []
        for p in world.projectiles
        where !destroyedProjectiles.contains(p.entityID) && p.lifetimeRemainingTicks <= 0 {
            destroyedProjectiles.insert(p.entityID)
            events.append(.projectileDestroyed(entityID: p.entityID, position: p.positionSubunits))
            if let weapon = weapons.weapon(p.weaponID), weapon.family == .explosion {
                expiryExplosions.append(Explosion(from: p, weapon: weapon))
            }
        }
        if !expiryExplosions.isEmpty {
            resolveExplosions(&world, queue: expiryExplosions, weapons: weapons,
                              destroyedProjectiles: &destroyedProjectiles, events: &events)
        }

        // 11–12. Pickups, deaths, cleanup, and active-count bookkeeping.
        cleanup(&world, destroyedProjectiles: destroyedProjectiles, weapons: weapons, events: &events)
    }

    // MARK: - Steps 6–7: firing and spawning

    private static func processFireRequests(
        _ world: inout WorldState,
        firePressed: [PlayerID: (normal: Bool, special: Bool)],
        aiFire: [Int: (normal: Bool, special: Bool)],
        weapons: WeaponRuleset,
        events: inout [DomainEvent]
    ) -> Set<Int> {
        var spawned = Set<Int>()
        for index in world.tanks.indices {
            let tank = world.tanks[index]
            // External commands for player tanks, internal intents for AI.
            let pressed: (normal: Bool, special: Bool)
            if let owner = tank.ownerPlayerID {
                guard let p = firePressed[owner] else { continue }
                pressed = p
            } else {
                guard let p = aiFire[tank.entityID] else { continue }
                pressed = p
            }
            if pressed.normal, let weapon = weapons.weapon("normal") {
                fire(&world, tankIndex: index, weapon: weapon, channel: .normal,
                     weapons: weapons, spawned: &spawned, events: &events)
            }
            if pressed.special, let weapon = weapons.weapon(world.tanks[index].specialWeaponID) {
                fire(&world, tankIndex: index, weapon: weapon, channel: .special,
                     weapons: weapons, spawned: &spawned, events: &events)
            }
        }
        return spawned
    }

    private static func fire(
        _ world: inout WorldState, tankIndex: Int, weapon: WeaponDefinition,
        channel: FireChannel, weapons: WeaponRuleset,
        spawned: inout Set<Int>, events: inout [DomainEvent]
    ) {
        var tank = world.tanks[tankIndex]
        let power = tank.powerLevel
        guard tank.fireCooldowns[channel, default: 0] == 0 else { return }
        guard tank.activeProjectileCounts[weapon.id, default: 0] < weapon.level(weapon.maxActive, power) else { return }

        // Ammunition lives on the owning player (§6.4); AI tanks are exempt.
        if channel == .special, let owner = tank.ownerPlayerID {
            let ammo = world.player(owner)?.specialAmmoByWeapon[weapon.id, default: 0] ?? 0
            guard ammo >= weapon.ammoCost else {
                events.append(.dryFire(entityID: tank.entityID, weaponID: weapon.id))
                tank.fireCooldowns[channel] = weapon.level(weapon.cooldownTicks, power)
                world.tanks[tankIndex] = tank
                return
            }
        }

        let footprint = SpatialUnits.standardTankFootprintSubunits
        let center = tank.positionSubunits + Vec2i(x: footprint / 2, y: footprint / 2)
        let cell = SpatialUnits.subunitsPerCell
        var consumeAmmo = weapon.ammoCost

        switch weapon.family {
        case .mine:
            // Rear deploy onto the cell behind the tank (§8.6); placement
            // legality: in bounds, not solid, water needs AmphiTank, and no
            // hardware overlap with an existing mine (mine-vs-mine, §8.5).
            let rawCenter = center + tank.facing.opposite.vector * (footprint / 2 + cell / 2)
            let mineCenter = Vec2i(x: (rawCenter.x / cell) * cell + cell / 2,
                                   y: (rawCenter.y / cell) * cell + cell / 2)
            guard let placement = minePlacement(world, center: mineCenter, tank: tank, weapons: weapons) else {
                events.append(.dryFire(entityID: tank.entityID, weaponID: weapon.id))
                world.tanks[tankIndex] = tank
                return
            }
            let id = world.claimEntityID()
            world.mines.append(MineState(
                entityID: id, level: power, ownerEntityID: tank.entityID,
                ownerPlayerID: tank.ownerPlayerID, teamID: tank.teamID,
                positionSubunits: mineCenter, phase: .arming,
                phaseTicksRemaining: weapons.mineArmingTicks,
                triggerRadiusSubunits: weapon.level(weapon.mineTriggerRadiusSubunits, power),
                onWater: placement.onWater))
            spawned.insert(id)
            events.append(.minePlaced(entityID: id, level: power, position: mineCenter))
        case .fire:
            // A flame wall as wide as the tank (the two cross-axis cells the
            // 2-cell footprint spans, symmetric about the tank's center
            // line), marching three cells forward. Each column advances
            // independently; walls stop it and water extinguishes it
            // (fire-hazard-vs-terrain, §8.5).
            let filter: FireTeamFilter = .enemyOnly // campaign player default (§8.7)
            let horizontal = tank.facing.vector.x != 0
            let crossTopLeft = horizontal ? tank.positionSubunits.y : tank.positionSubunits.x
            let crossCells = [crossTopLeft / cell, (crossTopLeft + footprint - 1) / cell]
            var spawnedPatches = 0
            for cross in Set(crossCells).sorted() {
                for step in 1...3 {
                    let along = (horizontal ? center.x : center.y)
                        + (tank.facing.vector.x + tank.facing.vector.y) * (footprint / 2 + cell / 2 + (step - 1) * cell)
                    let (cx, cy) = horizontal ? (along / cell, cross) : (cross, along / cell)
                    guard world.terrain.isInside(cellX: cx, cellY: cy) else { break }
                    let kind = world.terrain[cx, cy].kind
                    if kind == .brick || kind == .steel || kind == .base || kind == .water { break }
                    let patchCenter = Vec2i(x: cx * cell + cell / 2, y: cy * cell + cell / 2)
                    let id = world.claimEntityID()
                    world.fireHazards.append(FireHazardState(
                        entityID: id, ownerPlayerID: tank.ownerPlayerID, teamID: tank.teamID,
                        filter: filter, positionSubunits: patchCenter,
                        lifetimeRemainingTicks: weapon.level(weapon.lifetimeTicks, power),
                        damagePerTouch: weapon.level(weapon.tankDamage, power)))
                    spawned.insert(id)
                    spawnedPatches += 1
                }
            }
            guard spawnedPatches > 0 else {
                // Muzzle flush against a wall/water: nothing to ignite.
                events.append(.dryFire(entityID: tank.entityID, weaponID: weapon.id))
                world.tanks[tankIndex] = tank
                return
            }
            // Active-count bookkeeping is per PATCH (cleanup decrements one
            // per expired patch), so account for what actually spawned
            // (the shared +1 below completes the total).
            tank.activeProjectileCounts[weapon.id, default: 0] += spawnedPatches - 1
        case .normal, .rapid, .ap, .explosion:
            let muzzle = center + tank.facing.vector * (footprint / 2)
            let id = world.claimEntityID()
            world.projectiles.append(ProjectileState(
                entityID: id, weaponID: weapon.id, ownerEntityID: tank.entityID,
                ownerPlayerID: tank.ownerPlayerID, teamID: tank.teamID, powerLevel: power,
                positionSubunits: muzzle, direction: tank.facing,
                speedSubunitsPerTick: weapon.level(weapon.initialSpeedSubunitsPerTick, power),
                lifetimeRemainingTicks: weapon.level(weapon.lifetimeTicks, power),
                penetrationRemaining: weapon.level(weapon.penetrationCount, power),
                durability: weapon.level(weapon.projectileDurability, power)))
            spawned.insert(id)
            if weapon.family == .normal { consumeAmmo = 0 }
        }

        tank.fireCooldowns[channel] = weapon.level(weapon.cooldownTicks, tank.powerLevel)
        tank.activeProjectileCounts[weapon.id, default: 0] += 1
        if channel == .special, consumeAmmo > 0, let owner = tank.ownerPlayerID {
            world.withPlayer(owner) { $0.specialAmmoByWeapon[weapon.id, default: 0] -= consumeAmmo }
        }
        world.tanks[tankIndex] = tank
        events.append(.weaponFired(entityID: tank.entityID, weaponID: weapon.id,
                                   channel: channel, position: tank.positionSubunits))
    }

    private static func minePlacement(
        _ world: WorldState, center: Vec2i, tank: TankState, weapons: WeaponRuleset
    ) -> (onWater: Bool, ())? {
        let cell = SpatialUnits.subunitsPerCell
        let cx = center.x / cell, cy = center.y / cell
        guard world.terrain.isInside(cellX: cx, cellY: cy) else { return nil }
        let kind = world.terrain[cx, cy].kind
        if kind == .brick || kind == .steel || kind == .base { return nil }
        let onWater = kind == .water
        if onWater && tank.equipmentID != "amphi_tank" { return nil } // §8.6
        let half = weapons.mineHalfExtentSubunits
        for mine in world.mines
        where abs(mine.positionSubunits.x - center.x) < half * 2
            && abs(mine.positionSubunits.y - center.y) < half * 2 {
            return nil // stacking is illegal (§8.5 mine vs mine)
        }
        return (onWater, ())
    }

    // MARK: - Steps 9–10: projectile sweeps

    private struct Explosion {
        let center: Vec2i
        let radius: Int
        let tankDamage: Int
        let brickDamage: Int
        let steelDamage: Int
        let powerLevel: Int
        let teamID: Int
        let ownerPlayerID: PlayerID?

        init(from p: ProjectileState, weapon: WeaponDefinition) {
            center = p.positionSubunits
            radius = weapon.level(weapon.explosionRadiusSubunits, p.powerLevel)
            tankDamage = weapon.level(weapon.tankDamage, p.powerLevel)
            brickDamage = weapon.level(weapon.brickDamage, p.powerLevel)
            steelDamage = weapon.level(weapon.steelDamage, p.powerLevel)
            powerLevel = p.powerLevel
            teamID = p.teamID
            ownerPlayerID = p.ownerPlayerID
        }

        init(fromMine mine: MineState, weapon: WeaponDefinition) {
            center = mine.positionSubunits
            radius = weapon.level(weapon.explosionRadiusSubunits, mine.level)
            tankDamage = weapon.level(weapon.tankDamage, mine.level)
            brickDamage = weapon.level(weapon.brickDamage, mine.level)
            steelDamage = weapon.level(weapon.steelDamage, mine.level)
            powerLevel = mine.level
            teamID = mine.teamID
            ownerPlayerID = mine.ownerPlayerID
        }
    }

    private enum SweepHit {
        case boundary(t: Int)
        case terrain(t: Int, qx: Int, qy: Int)
        case tank(t: Int, index: Int)
        case base(t: Int)
        case mine(t: Int, index: Int)
    }

    /// Resolves one projectile's swept segment in parametric-entry order.
    /// The parameter t is the travelled distance in subunits along the
    /// segment (integer; ties resolve by category order boundary → terrain
    /// → tank → base → mine, then ascending target id — documented).
    private static func resolveProjectileSweep(
        _ world: inout WorldState, projectileID: Int, segment: (from: Vec2i, to: Vec2i),
        weapons: WeaponRuleset,
        explosions: inout [Explosion], destroyed: inout Set<Int>,
        events: inout [DomainEvent]
    ) {
        guard let startIndex = world.projectiles.firstIndex(where: { $0.entityID == projectileID }) else { return }
        var projectile = world.projectiles[startIndex]
        guard let weapon = weapons.weapon(projectile.weaponID) else { return }
        let half = weapons.projectileHalfExtentSubunits
        let vector = projectile.direction.vector
        var travelled = 0
        let totalDistance = abs(segment.to.x - segment.from.x) + abs(segment.to.y - segment.from.y)

        func position(at t: Int) -> Vec2i { segment.from + vector * t }

        while travelled <= totalDistance {
            guard let hit = earliestHit(
                world, projectile: projectile, from: position(at: travelled),
                remaining: totalDistance - travelled, half: half) else { break }

            switch hit {
            case .boundary(let t):
                travelled += t
                projectile.positionSubunits = position(at: travelled)
                destroyProjectile(&projectile, at: startIndex, world: &world, weapon: weapon,
                                  explosions: &explosions, destroyed: &destroyed, events: &events)
                return

            case .terrain(let t, let qx, let qy):
                travelled += t
                projectile.positionSubunits = position(at: travelled)
                let destroyedCount = applyTerrainDamage(
                    &world, entryQuadrant: (qx, qy), direction: projectile.direction,
                    crossCenter: projectile.positionSubunits, half: half,
                    brickDamage: weapon.level(weapon.brickDamage, projectile.powerLevel),
                    steelDamage: weapon.level(weapon.steelDamage, projectile.powerLevel),
                    events: &events)
                if destroyedCount == 0 || projectile.penetrationRemaining < destroyedCount {
                    destroyProjectile(&projectile, at: startIndex, world: &world, weapon: weapon,
                                      explosions: &explosions, destroyed: &destroyed, events: &events)
                    return
                }
                projectile.penetrationRemaining -= destroyedCount
                travelled += 1 // step past the destroyed layer

            case .tank(let t, let tankIndex):
                travelled += t
                projectile.positionSubunits = position(at: travelled)
                let target = world.tanks[tankIndex]
                if target.spawnProtectionTicks > 0 || target.statusEffects["invincible"] != nil {
                    // Deflection (§8.5): destroyed without damage or detonation.
                    events.append(.projectileDestroyed(entityID: projectile.entityID,
                                                       position: projectile.positionSubunits))
                    removeProjectile(&world, entityID: projectile.entityID, destroyed: &destroyed)
                    return
                }
                if weapon.family == .explosion {
                    // Explosive shells deal ALL their damage through the
                    // blast — no separate contact damage (no double-dipping).
                    destroyProjectile(&projectile, at: startIndex, world: &world, weapon: weapon,
                                      explosions: &explosions, destroyed: &destroyed, events: &events)
                    return
                }
                applyTankDamage(&world, tankIndex: tankIndex,
                                damage: weapon.level(weapon.tankDamage, projectile.powerLevel),
                                sourceWeaponID: weapon.id, events: &events)
                if projectile.penetrationRemaining < 1 {
                    destroyProjectile(&projectile, at: startIndex, world: &world, weapon: weapon,
                                      explosions: &explosions, destroyed: &destroyed, events: &events)
                    return
                }
                projectile.penetrationRemaining -= 1
                travelled += 1

            case .base(let t):
                travelled += t
                projectile.positionSubunits = position(at: travelled)
                applyBaseHit(&world, damage: weapon.level(weapon.tankDamage, projectile.powerLevel),
                             sourceIsAllied: projectile.teamID == world.base?.teamID,
                             weapons: weapons, events: &events)
                destroyProjectile(&projectile, at: startIndex, world: &world, weapon: weapon,
                                  explosions: &explosions, destroyed: &destroyed, events: &events)
                return

            case .mine(let t, let mineIndex):
                travelled += t
                projectile.positionSubunits = position(at: travelled)
                let mine = world.mines[mineIndex]
                if weapon.family == .explosion {
                    // Detonating on contact; the area blast chains qualified
                    // mines breadth-first (§8.5).
                    destroyProjectile(&projectile, at: startIndex, world: &world, weapon: weapon,
                                      explosions: &explosions, destroyed: &destroyed, events: &events)
                    return
                }
                // Plain projectile vs mine: disarms the hardware (no blast).
                world.mines.remove(at: mineIndex)
                decrementActiveCount(&world, ownerEntityID: mine.ownerEntityID, weaponID: "mine")
                events.append(.projectileDestroyed(entityID: projectile.entityID,
                                                   position: projectile.positionSubunits))
                if projectile.penetrationRemaining < 1 {
                    removeProjectile(&world, entityID: projectile.entityID, destroyed: &destroyed)
                    return
                }
                projectile.penetrationRemaining -= 1
                travelled += 1
            }
            if let i = world.projectiles.firstIndex(where: { $0.entityID == projectile.entityID }) {
                world.projectiles[i] = projectile
            } else {
                return
            }
        }
        if let i = world.projectiles.firstIndex(where: { $0.entityID == projectile.entityID }) {
            world.projectiles[i] = projectile
        }
    }

    /// Earliest hit along the remaining segment, or nil for free flight.
    /// Water, ice, foliage, and pickups are pass-over (§7.3, §8.5).
    private static func earliestHit(
        _ world: WorldState, projectile: ProjectileState,
        from: Vec2i, remaining: Int, half: Int
    ) -> SweepHit? {
        var best: (t: Int, order: Int, id: Int, hit: SweepHit)?
        func consider(_ t: Int, _ order: Int, _ id: Int, _ hit: SweepHit) {
            if best == nil || (t, order, id) < (best!.t, best!.order, best!.id) {
                best = (t, order, id, hit)
            }
        }
        let vector = projectile.direction.vector
        let arena = world.arena

        // Arena boundary: the projectile CENTER leaving the arena despawns it.
        do {
            var t = remaining + 1
            if vector.x > 0 { t = arena.widthSubunits - from.x }
            if vector.x < 0 { t = from.x }
            if vector.y > 0 { t = arena.heightSubunits - from.y }
            if vector.y < 0 { t = from.y }
            if t <= remaining { consider(max(0, t), 0, 0, .boundary(t: max(0, t))) }
        }

        // Terrain quadrants (brick/steel block shots; §7.3).
        if let (t, qx, qy) = firstSolidQuadrant(world.terrain, from: from, vector: vector,
                                                remaining: remaining, half: half) {
            consider(t, 1, qy * 1000 + qx, .terrain(t: t, qx: qx, qy: qy))
        }

        // Enemy tanks (allied tanks are pass-through: allied damage is
        // disabled, D-010; own tank never collides with its own shot).
        let footprint = SpatialUnits.standardTankFootprintSubunits
        for (index, tank) in world.tanks.enumerated()
        where tank.teamID != projectile.teamID {
            let p = tank.positionSubunits
            if let t = boxEntry(from: from, vector: vector, remaining: remaining, half: half,
                                minX: p.x, minY: p.y, maxX: p.x + footprint, maxY: p.y + footprint) {
                consider(t, 2, tank.entityID, .tank(t: t, index: index))
            }
        }

        // Base structure.
        if let base = world.base {
            let p = base.topLeftSubunits
            if let t = boxEntry(from: from, vector: vector, remaining: remaining, half: half,
                                minX: p.x, minY: p.y,
                                maxX: p.x + base.sizeSubunits, maxY: p.y + base.sizeSubunits) {
                consider(t, 3, 0, .base(t: t))
            }
        }

        // Mine hardware.
        for (index, mine) in world.mines.enumerated() {
            let mineHalf = 256
            let p = mine.positionSubunits
            if let t = boxEntry(from: from, vector: vector, remaining: remaining, half: half,
                                minX: p.x - mineHalf, minY: p.y - mineHalf,
                                maxX: p.x + mineHalf, maxY: p.y + mineHalf) {
                consider(t, 4, mine.entityID, .mine(t: t, index: index))
            }
        }
        return best?.hit
    }

    /// Entry distance of the projectile's box into a target box, or nil.
    private static func boxEntry(
        from: Vec2i, vector: Vec2i, remaining: Int, half: Int,
        minX: Int, minY: Int, maxX: Int, maxY: Int
    ) -> Int? {
        // Expand the target by the projectile half-extent (Minkowski sum).
        let eMinX = minX - half, eMaxX = maxX + half
        let eMinY = minY - half, eMaxY = maxY + half
        // Cross-axis must overlap for an axis-aligned sweep.
        if vector.x != 0 {
            guard from.y > eMinY && from.y < eMaxY else { return nil }
            let t = vector.x > 0 ? eMinX - from.x : from.x - eMaxX
            if t < 0 { return from.x > eMinX && from.x < eMaxX ? 0 : nil }
            return t <= remaining ? t : nil
        } else {
            guard from.x > eMinX && from.x < eMaxX else { return nil }
            let t = vector.y > 0 ? eMinY - from.y : from.y - eMaxY
            if t < 0 { return from.y > eMinY && from.y < eMaxY ? 0 : nil }
            return t <= remaining ? t : nil
        }
    }

    /// First shot-blocking quadrant along the sweep (discrete point sampling
    /// is prohibited; this walks quadrant boundaries analytically).
    private static func firstSolidQuadrant(
        _ terrain: TerrainGrid, from: Vec2i, vector: Vec2i, remaining: Int, half: Int
    ) -> (t: Int, qx: Int, qy: Int)? {
        let quadrant = SpatialUnits.subunitsPerQuadrant
        for t in quadrantBoundarySteps(from: from, vector: vector, remaining: remaining, half: half) {
            let p = from + vector * t
            let minX = p.x - half + (vector.x > 0 ? 2 * half : 0)
            let minY = p.y - half + (vector.y > 0 ? 2 * half : 0)
            // Leading edge sample band across the cross axis.
            let (loX, hiX) = vector.x != 0 ? (minX, minX) : (p.x - half, p.x + half - 1)
            let (loY, hiY) = vector.y != 0 ? (minY, minY) : (p.y - half, p.y + half - 1)
            var qy = loY / quadrant
            while qy <= hiY / quadrant {
                var qx = loX / quadrant
                while qx <= hiX / quadrant {
                    if solidQuadrant(terrain, qx: qx, qy: qy) { return (t, qx, qy) }
                    qx += 1
                }
                qy += 1
            }
        }
        return nil
    }

    /// Distances at which the projectile's leading edge crosses into a new
    /// quadrant layer (plus t=0 for immediate contact).
    private static func quadrantBoundarySteps(
        from: Vec2i, vector: Vec2i, remaining: Int, half: Int
    ) -> [Int] {
        let quadrant = SpatialUnits.subunitsPerQuadrant
        var steps = [0]
        let leading = vector.x != 0
            ? (vector.x > 0 ? from.x + half : from.x - half)
            : (vector.y > 0 ? from.y + half : from.y - half)
        let sign = (vector.x + vector.y) > 0
        var next = sign
            ? ((leading / quadrant) + 1) * quadrant - leading
            : leading - (leading / quadrant) * quadrant + (leading % quadrant == 0 ? quadrant : 0)
        if next == 0 { next = quadrant }
        var t = next
        while t <= remaining {
            steps.append(t)
            t += quadrant
        }
        return steps
    }

    private static func solidQuadrant(_ terrain: TerrainGrid, qx: Int, qy: Int) -> Bool {
        let cx = qx / 2, cy = qy / 2
        guard terrain.isInside(cellX: cx, cellY: cy) else { return false }
        let cell = terrain[cx, cy]
        guard cell.kind == .brick || cell.kind == .steel else { return false }
        let bit = (qy % 2) * 2 + (qx % 2)
        return cell.quadrantMask & (1 << bit) != 0
    }

    // MARK: - Damage application

    /// Destroys quadrant layers at the impact point. Layer i falls when the
    /// material's damage value exceeds i (brick 1 = front layer, 2 = full
    /// cell depth; steel 0 = indestructible to this weapon).
    ///
    /// Blast width (reference-heritage): the destroyed strip spans the FULL
    /// cross-axis width of every cell the projectile's box touches — a shot
    /// carves a cell-wide notch, and a second aligned shot removes the back
    /// layer entirely, so no unhittable slivers linger beside the drill
    /// line. Only the quadrants the projectile's own box pierces consume
    /// `penetration_count`; collateral strip quadrants do not. Returns the
    /// pierced-quadrant count.
    private static func applyTerrainDamage(
        _ world: inout WorldState, entryQuadrant: (qx: Int, qy: Int), direction: Direction,
        crossCenter: Vec2i, half: Int, brickDamage: Int, steelDamage: Int,
        events: inout [DomainEvent]
    ) -> Int {
        let quadrant = SpatialUnits.subunitsPerQuadrant
        var piercedCount = 0
        var changedCells = Set<Int>()
        let maxLayers = max(brickDamage, steelDamage)
        for layer in 0..<max(1, maxLayers) {
            let (lqx, lqy): (Int, Int)
            switch direction {
            case .right: (lqx, lqy) = (entryQuadrant.qx + layer, entryQuadrant.qy)
            case .left: (lqx, lqy) = (entryQuadrant.qx - layer, entryQuadrant.qy)
            case .down: (lqx, lqy) = (entryQuadrant.qx, entryQuadrant.qy + layer)
            case .up: (lqx, lqy) = (entryQuadrant.qx, entryQuadrant.qy - layer)
            }
            // Pierced band: quadrants the projectile box itself spans.
            let horizontal = direction.vector.x != 0
            let pierceLo = (horizontal ? crossCenter.y - half : crossCenter.x - half) / quadrant
            let pierceHi = (horizontal ? crossCenter.y + half - 1 : crossCenter.x + half - 1) / quadrant
            // Strip: widen to the full width of every touched cell.
            let stripLo = (pierceLo / 2) * 2
            let stripHi = (pierceHi / 2) * 2 + 1
            for cross in stripLo...stripHi {
                let (qx, qy) = horizontal ? (lqx, cross) : (cross, lqy)
                guard solidQuadrant(world.terrain, qx: qx, qy: qy) else { continue }
                let cx = qx / 2, cy = qy / 2
                let kind = world.terrain[cx, cy].kind
                let damage = kind == .brick ? brickDamage : steelDamage
                guard damage > layer else { continue }
                var cell = world.terrain[cx, cy]
                cell.quadrantMask &= ~(1 << ((qy % 2) * 2 + (qx % 2)))
                if cell.quadrantMask == 0 { cell = TerrainCell(kind: .ground) }
                world.terrain[cx, cy] = cell
                if (pierceLo...pierceHi).contains(cross) { piercedCount += 1 }
                changedCells.insert(cy * world.arena.cellsWide + cx)
            }
        }
        for key in changedCells.sorted() {
            let cx = key % world.arena.cellsWide, cy = key / world.arena.cellsWide
            events.append(.terrainChanged(cellX: cx, cellY: cy,
                                          quadrantMask: world.terrain[cx, cy].quadrantMask))
        }
        return piercedCount
    }

    /// Shield-aware damage (owner-directed resistance model): a shield
    /// absorbs non-explosive damage point by point; explosion-class sources
    /// (explosion shells, mines, the bomb pickup) shatter the whole shield
    /// in one blow. Armor is only touched once the shield is gone.
    static func applyTankDamage(
        _ world: inout WorldState, tankIndex: Int, damage: Int,
        sourceWeaponID: String, events: inout [DomainEvent]
    ) {
        guard damage > 0 else { return }
        let entityID = world.tanks[tankIndex].entityID
        if world.tanks[tankIndex].shieldHP > 0 {
            let shatters = ["explosion", "mine", "bomb"].contains(sourceWeaponID)
            world.tanks[tankIndex].shieldHP = shatters
                ? 0 : max(0, world.tanks[tankIndex].shieldHP - damage)
            events.append(.tankShieldHit(entityID: entityID,
                                         remaining: world.tanks[tankIndex].shieldHP))
            return
        }
        world.tanks[tankIndex].armor -= damage
        events.append(.tankDamaged(entityID: entityID, damage: damage,
                                   sourceWeaponID: sourceWeaponID))
    }

    private static func applyBaseHit(
        _ world: inout WorldState, damage: Int, sourceIsAllied: Bool,
        weapons: WeaponRuleset, events: inout [DomainEvent]
    ) {
        guard var base = world.base else { return }
        if base.shieldRemainingTicks > 0 { return } // shield deflects (§8.5)
        if sourceIsAllied && !weapons.alliedBaseDamage { return } // ADR-0005
        base.durability = max(0, base.durability - damage)
        world.base = base
        events.append(.baseDamaged(damage: damage, remaining: base.durability))
    }

    // MARK: - Projectile vs projectile

    private static func resolveProjectileVsProjectile(
        _ world: inout WorldState, segments: [Int: (from: Vec2i, to: Vec2i)],
        weapons: WeaponRuleset,
        explosions: inout [Explosion], destroyed: inout Set<Int>,
        events: inout [DomainEvent]
    ) {
        let half = weapons.projectileHalfExtentSubunits
        func sweptBox(_ p: ProjectileState) -> (Int, Int, Int, Int) {
            let s = segments[p.entityID] ?? (p.positionSubunits, p.positionSubunits)
            return (min(s.from.x, s.to.x) - half, min(s.from.y, s.to.y) - half,
                    max(s.from.x, s.to.x) + half, max(s.from.y, s.to.y) + half)
        }
        let list = world.projectiles
        for i in list.indices {
            for j in list.indices where j > i {
                let a = list[i], b = list[j]
                guard !destroyed.contains(a.entityID), !destroyed.contains(b.entityID),
                      a.teamID != b.teamID else { continue }
                let boxA = sweptBox(a), boxB = sweptBox(b)
                guard boxA.0 < boxB.2 && boxA.2 > boxB.0 && boxA.1 < boxB.3 && boxA.3 > boxB.1
                else { continue }
                // Durability comparison (§8.4): higher survives, equal → both.
                if a.durability <= b.durability { destroyPvP(&world, a, weapons: weapons, explosions: &explosions, destroyed: &destroyed, events: &events) }
                if b.durability <= a.durability { destroyPvP(&world, b, weapons: weapons, explosions: &explosions, destroyed: &destroyed, events: &events) }
            }
        }
    }

    private static func destroyPvP(
        _ world: inout WorldState, _ p: ProjectileState, weapons: WeaponRuleset,
        explosions: inout [Explosion], destroyed: inout Set<Int>, events: inout [DomainEvent]
    ) {
        guard !destroyed.contains(p.entityID) else { return }
        events.append(.projectileDestroyed(entityID: p.entityID, position: p.positionSubunits))
        if let weapon = weapons.weapon(p.weaponID), weapon.family == .explosion {
            explosions.append(Explosion(from: p, weapon: weapon))
        }
        removeProjectile(&world, entityID: p.entityID, destroyed: &destroyed)
    }

    // MARK: - Mines and fire hazards

    private static func resolveMineTriggers(
        _ world: inout WorldState, weapons: WeaponRuleset,
        explosions: inout [Explosion], events: inout [DomainEvent]
    ) {
        guard let mineWeapon = weapons.weapon("mine") else { return }
        let footprint = SpatialUnits.standardTankFootprintSubunits
        var triggered: [Int] = []
        var removedByMoon: [Int] = []
        for mine in world.mines where mine.phase == .armed {
            for tank in world.tanks where tank.teamID != mine.teamID {
                let p = tank.positionSubunits
                // ShieldOfMoon sweeps enemy level-0 mines on contact (§8.6).
                if tank.equipmentID == "shield_of_moon" && mine.level == 0 {
                    let half = weapons.mineHalfExtentSubunits
                    if p.x < mine.positionSubunits.x + half && p.x + footprint > mine.positionSubunits.x - half
                        && p.y < mine.positionSubunits.y + half && p.y + footprint > mine.positionSubunits.y - half {
                        removedByMoon.append(mine.entityID)
                        break
                    }
                    continue
                }
                // AntiSkid crosses enemy mines of level 0–2 safely (§8.6).
                if tank.equipmentID == "anti_skid" && mine.level <= 2 { continue }
                let clampedX = max(p.x, min(mine.positionSubunits.x, p.x + footprint))
                let clampedY = max(p.y, min(mine.positionSubunits.y, p.y + footprint))
                let dx = mine.positionSubunits.x - clampedX, dy = mine.positionSubunits.y - clampedY
                let r = mine.triggerRadiusSubunits
                if dx * dx + dy * dy <= r * r {
                    triggered.append(mine.entityID)
                    break
                }
            }
        }
        for id in removedByMoon.sorted() {
            if let mine = world.mines.first(where: { $0.entityID == id }) {
                world.mines.removeAll { $0.entityID == id }
                decrementActiveCount(&world, ownerEntityID: mine.ownerEntityID, weaponID: "mine")
                events.append(.projectileDestroyed(entityID: id, position: mine.positionSubunits))
            }
        }
        for id in triggered.sorted() {
            if let mine = world.mines.first(where: { $0.entityID == id }) {
                world.mines.removeAll { $0.entityID == id }
                decrementActiveCount(&world, ownerEntityID: mine.ownerEntityID, weaponID: "mine")
                events.append(.mineTriggered(entityID: id, position: mine.positionSubunits))
                explosions.append(Explosion(fromMine: mine, weapon: mineWeapon))
            }
        }
    }

    private static func resolveFireHazardDamage(
        _ world: inout WorldState, weapons: WeaponRuleset, events: inout [DomainEvent]
    ) {
        let cell = SpatialUnits.subunitsPerCell
        let footprint = SpatialUnits.standardTankFootprintSubunits
        for hazard in world.fireHazards {
            guard hazard.lifetimeRemainingTicks > 0 else { continue }
            for tankIndex in world.tanks.indices {
                let tank = world.tanks[tankIndex]
                switch hazard.filter { // §8.7
                case .both: break
                case .alliedOnly: if tank.teamID != hazard.teamID { continue }
                case .enemyOnly: if tank.teamID == hazard.teamID { continue }
                }
                if tank.spawnProtectionTicks > 0 { continue }
                // One burn cadence per TANK across all patches: overlapping
                // flames never multiply damage (documented; status timer is
                // authoritative state and decrements in step 2).
                if tank.statusEffects["burn_immunity"] != nil { continue }
                let p = tank.positionSubunits
                let hx = hazard.positionSubunits.x - cell / 2, hy = hazard.positionSubunits.y - cell / 2
                guard p.x < hx + cell && p.x + footprint > hx
                    && p.y < hy + cell && p.y + footprint > hy else { continue }
                world.tanks[tankIndex].statusEffects["burn_immunity"] = weapons.fireDamageIntervalTicks
                applyTankDamage(&world, tankIndex: tankIndex, damage: hazard.damagePerTouch,
                                sourceWeaponID: "fire", events: &events)
            }
        }
    }

    // MARK: - Explosions (breadth-first chains, §8.5)

    private static func resolveExplosions(
        _ world: inout WorldState, queue initialWave: [Explosion], weapons: WeaponRuleset,
        destroyedProjectiles: inout Set<Int>, events: inout [DomainEvent]
    ) {
        guard let mineWeapon = weapons.weapon("mine") else { return }
        var wave = initialWave
        var waveNumber = 0
        while !wave.isEmpty && waveNumber < weapons.chainDetonationWaveCap {
            var nextWave: [Explosion] = []
            for explosion in wave {
                events.append(.explosion(position: explosion.center, radiusSubunits: explosion.radius))
                applyExplosion(&world, explosion, weapons: weapons, nextWave: &nextWave,
                               mineWeapon: mineWeapon, destroyedProjectiles: &destroyedProjectiles,
                               events: &events)
            }
            wave = nextWave
            waveNumber += 1
        }
    }

    private static func applyExplosion(
        _ world: inout WorldState, _ explosion: Explosion, weapons: WeaponRuleset,
        nextWave: inout [Explosion], mineWeapon: WeaponDefinition,
        destroyedProjectiles: inout Set<Int>, events: inout [DomainEvent]
    ) {
        let r = explosion.radius
        guard r > 0 else { return }
        let footprint = SpatialUnits.standardTankFootprintSubunits

        func circleTouchesBox(_ minX: Int, _ minY: Int, _ maxX: Int, _ maxY: Int) -> Bool {
            let cx = max(minX, min(explosion.center.x, maxX))
            let cy = max(minY, min(explosion.center.y, maxY))
            let dx = explosion.center.x - cx, dy = explosion.center.y - cy
            return dx * dx + dy * dy <= r * r
        }

        // Tanks: enemy only (allied damage disabled, D-010); protection deflects.
        for i in world.tanks.indices {
            let tank = world.tanks[i]
            guard tank.teamID != explosion.teamID, tank.spawnProtectionTicks == 0,
                  tank.statusEffects["invincible"] == nil else { continue }
            let p = tank.positionSubunits
            if circleTouchesBox(p.x, p.y, p.x + footprint, p.y + footprint) {
                applyTankDamage(&world, tankIndex: i, damage: explosion.tankDamage,
                                sourceWeaponID: "explosion", events: &events)
            }
        }

        // Terrain: quadrants whose center lies within the radius.
        let quadrant = SpatialUnits.subunitsPerQuadrant
        let loQX = max(0, (explosion.center.x - r) / quadrant)
        let hiQX = min(world.arena.cellsWide * 2 - 1, (explosion.center.x + r) / quadrant)
        let loQY = max(0, (explosion.center.y - r) / quadrant)
        let hiQY = min(world.arena.cellsHigh * 2 - 1, (explosion.center.y + r) / quadrant)
        var changedCells = Set<Int>()
        for qy in loQY...hiQY {
            for qx in loQX...hiQX where solidQuadrant(world.terrain, qx: qx, qy: qy) {
                let centerX = qx * quadrant + quadrant / 2, centerY = qy * quadrant + quadrant / 2
                let dx = explosion.center.x - centerX, dy = explosion.center.y - centerY
                guard dx * dx + dy * dy <= r * r else { continue }
                let cx = qx / 2, cy = qy / 2
                let damage = world.terrain[cx, cy].kind == .brick ? explosion.brickDamage : explosion.steelDamage
                guard damage > 0 else { continue }
                var cell = world.terrain[cx, cy]
                cell.quadrantMask &= ~(1 << ((qy % 2) * 2 + (qx % 2)))
                if cell.quadrantMask == 0 { cell = TerrainCell(kind: .ground) }
                world.terrain[cx, cy] = cell
                changedCells.insert(cy * world.arena.cellsWide + cx)
            }
        }
        for key in changedCells.sorted() {
            let cx = key % world.arena.cellsWide, cy = key / world.arena.cellsWide
            events.append(.terrainChanged(cellX: cx, cellY: cy,
                                          quadrantMask: world.terrain[cx, cy].quadrantMask))
        }

        // Base.
        if let base = world.base {
            let p = base.topLeftSubunits
            if circleTouchesBox(p.x, p.y, p.x + base.sizeSubunits, p.y + base.sizeSubunits) {
                applyBaseHit(&world, damage: explosion.tankDamage,
                             sourceIsAllied: explosion.teamID == base.teamID,
                             weapons: weapons, events: &events)
            }
        }

        // Projectiles caught in the blast are destroyed (explosion vs projectile).
        for p in world.projectiles where !destroyedProjectiles.contains(p.entityID) {
            let half = weapons.projectileHalfExtentSubunits
            let pos = p.positionSubunits
            if circleTouchesBox(pos.x - half, pos.y - half, pos.x + half, pos.y + half) {
                events.append(.projectileDestroyed(entityID: p.entityID, position: pos))
                if let weapon = weapons.weapon(p.weaponID), weapon.family == .explosion {
                    nextWave.append(Explosion(from: p, weapon: weapon))
                }
                removeProjectile(&world, entityID: p.entityID, destroyed: &destroyedProjectiles)
            }
        }

        // Chain detonation: mines with level ≤ the explosion's power level,
        // collected into the NEXT wave in ascending entity order (§8.5).
        let candidates = world.mines
            .filter { $0.level <= explosion.powerLevel }
            .filter { mine in
                let dx = explosion.center.x - mine.positionSubunits.x
                let dy = explosion.center.y - mine.positionSubunits.y
                return dx * dx + dy * dy <= r * r
            }
            .sorted { $0.entityID < $1.entityID }
        for mine in candidates {
            world.mines.removeAll { $0.entityID == mine.entityID }
            decrementActiveCount(&world, ownerEntityID: mine.ownerEntityID, weaponID: "mine")
            events.append(.mineTriggered(entityID: mine.entityID, position: mine.positionSubunits))
            nextWave.append(Explosion(fromMine: mine, weapon: mineWeapon))
        }
    }

    // MARK: - Step 12: cleanup

    private static func destroyProjectile(
        _ projectile: inout ProjectileState, at index: Int, world: inout WorldState,
        weapon: WeaponDefinition, explosions: inout [Explosion],
        destroyed: inout Set<Int>, events: inout [DomainEvent]
    ) {
        events.append(.projectileDestroyed(entityID: projectile.entityID,
                                           position: projectile.positionSubunits))
        if weapon.family == .explosion {
            explosions.append(Explosion(from: projectile, weapon: weapon))
        }
        removeProjectile(&world, entityID: projectile.entityID, destroyed: &destroyed)
    }

    private static func removeProjectile(
        _ world: inout WorldState, entityID: Int, destroyed: inout Set<Int>
    ) {
        guard !destroyed.contains(entityID) else { return }
        destroyed.insert(entityID)
        if let p = world.projectiles.first(where: { $0.entityID == entityID }) {
            decrementActiveCount(&world, ownerEntityID: p.ownerEntityID, weaponID: p.weaponID)
        }
    }

    private static func decrementActiveCount(
        _ world: inout WorldState, ownerEntityID: Int, weaponID: String
    ) {
        for i in world.tanks.indices where world.tanks[i].entityID == ownerEntityID {
            let current = world.tanks[i].activeProjectileCounts[weaponID, default: 0]
            world.tanks[i].activeProjectileCounts[weaponID] = current > 1 ? current - 1 : nil
        }
    }

    private static func cleanup(
        _ world: inout WorldState, destroyedProjectiles: Set<Int>,
        weapons: WeaponRuleset, events: inout [DomainEvent]
    ) {
        world.projectiles.removeAll { destroyedProjectiles.contains($0.entityID) }
        for hazard in world.fireHazards where hazard.lifetimeRemainingTicks <= 0 {
            decrementActiveCount(&world, ownerEntityID: findFireOwner(world, hazard) ?? -1, weaponID: "fire")
        }
        world.fireHazards.removeAll { $0.lifetimeRemainingTicks <= 0 }

        // 11. Pickup collection (after movement and damage, §9.3).
        Stage.processPickups(&world, weapons: weapons, events: &events)

        // 12. Deaths: score, drops, and player lifecycle, then removal.
        let deadTanks = world.tanks.filter { $0.armor <= 0 }
        for tank in deadTanks {
            events.append(.tankDestroyed(entityID: tank.entityID, position: tank.positionSubunits))
        }
        Stage.processDeaths(&world, deadTanks: deadTanks, events: &events)
        for tank in deadTanks { world.removeTank(entityID: tank.entityID) }
    }

    private static func findFireOwner(_ world: WorldState, _ hazard: FireHazardState) -> Int? {
        guard let owner = hazard.ownerPlayerID else { return nil }
        return world.player(owner)?.tankEntityID
    }
}
