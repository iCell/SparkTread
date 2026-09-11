/// Combat phases of the tick (§13.6 steps 6–12) and the §8.5 collision
/// matrix. Every category has explicit, documented semantics — an unlisted
/// collision is a defect, not an implicit no-op. Deterministic throughout:
/// all projectile contacts of a tick (world contacts AND projectile-versus-
/// projectile contacts) resolve from ONE queue in global time order within
/// the tick, ties broken by category then ascending entity IDs (§7.4
/// parametric-entry contract); breadth-first chain detonation capped at
/// `chainDetonationWaveCap`.
///
/// Scoped limitation (documented, not a defect of the queue): blasts are
/// resolved AFTER the contact queue of the tick. An explosion created by an
/// early contact therefore cannot intercept another projectile before that
/// projectile's own later world contact within the same tick; projectiles
/// caught by a blast are those inside its radius at the end of the queue.
enum Combat {
    // MARK: - Entry point

    static func run(
        _ world: inout WorldState,
        firePressed: [PlayerID: (normal: Bool, special: Bool)],
        aiFire: [Int: (normal: Bool, special: Bool)] = [:],
        movement: MovementRuleset,
        weapons: WeaponRuleset,
        pickups: PickupRuleset = .provisional,
        events: inout [DomainEvent]
    ) {
        // 6–7. Fire requests, then spawns. Spawned projectiles do not
        // advance in step 8 of the same tick (§13.6 clarification).
        let spawnedThisTick = processFireRequests(
            &world, firePressed: firePressed, aiFire: aiFire, weapons: weapons, events: &events)

        // 8. Advance projectiles and continuous hazards. A projectile spawned
        // this tick keeps its muzzle position (zero motion) and takes part in
        // projectile-versus-projectile contact only as a stationary box.
        var motions: [Int: Motion] = [:]
        for i in world.projectiles.indices {
            var p = world.projectiles[i]
            if spawnedThisTick.contains(p.entityID) {
                motions[p.entityID] = Motion(from: p.positionSubunits, vector: p.direction.vector, distance: 0)
                continue
            }
            guard let weapon = weapons.weapon(p.weaponID) else { continue }
            p.speedSubunitsPerTick = min(
                p.speedSubunitsPerTick + weapon.level(weapon.accelerationSubunitsPerTick2, p.powerLevel),
                weapon.level(weapon.maxSpeedSubunitsPerTick, p.powerLevel))
            let from = p.positionSubunits
            p.lifetimeRemainingTicks -= 1
            motions[p.entityID] = Motion(from: from, vector: p.direction.vector,
                                         distance: p.speedSubunitsPerTick)
            p.positionSubunits = from + p.direction.vector * p.speedSubunitsPerTick // provisional endpoint
            world.projectiles[i] = p
        }
        for i in world.fireHazards.indices { world.fireHazards[i].lifetimeRemainingTicks -= 1 }
        spreadFoliageFire(&world, weapons: weapons)
        for i in world.mines.indices where world.mines[i].phase == .arming {
            world.mines[i].phaseTicksRemaining -= 1
            if world.mines[i].phaseTicksRemaining <= 0 { world.mines[i].phase = .armed }
        }

        // 9–10. Collision candidates and resolution in global time order.
        var explosionQueue: [Explosion] = []
        var destroyedProjectiles = Set<Int>()
        resolveContacts(&world, motions: motions, weapons: weapons,
                        explosions: &explosionQueue, destroyed: &destroyedProjectiles, events: &events)
        var launches: [(tankID: Int, level: Int)] = []
        resolveMineTriggers(&world, weapons: weapons, explosions: &explosionQueue, launches: &launches, events: &events)
        resolveFireHazardDamage(&world, weapons: weapons, events: &events)
        resolveExplosions(&world, queue: explosionQueue, weapons: weapons,
                          destroyedProjectiles: &destroyedProjectiles, events: &events)
        applyMineLaunches(&world, launches: launches, weapons: weapons, events: &events)

        // Lifetime expiry: explosion-family projectiles detonate; others
        // fade. Expiry goes through the same exactly-once removal path as an
        // impact so the owner's active-count slot is released.
        var expiryExplosions: [Explosion] = []
        for p in world.projectiles
        where !destroyedProjectiles.contains(p.entityID) && p.lifetimeRemainingTicks <= 0 {
            events.append(.projectileDestroyed(entityID: p.entityID, weaponID: p.weaponID,
                                               position: p.positionSubunits, impact: .expired))
            if let weapon = weapons.weapon(p.weaponID), weapon.family == .explosion {
                expiryExplosions.append(Explosion(from: p, weapon: weapon))
            }
            removeProjectile(&world, entityID: p.entityID, destroyed: &destroyedProjectiles)
        }
        if !expiryExplosions.isEmpty {
            resolveExplosions(&world, queue: expiryExplosions, weapons: weapons,
                              destroyedProjectiles: &destroyedProjectiles, events: &events)
        }

        // 11–12. Pickups, deaths, cleanup, and active-count bookkeeping.
        cleanup(&world, destroyedProjectiles: destroyedProjectiles, weapons: weapons,
                pickups: pickups, events: &events)
    }

    // MARK: - Damage policy

    /// Protection deflects every damage source: spawn protection and timed
    /// invincibility (§6.5, §9.4). One predicate so projectiles, blasts,
    /// flames, and the bomb pickup cannot disagree.
    static func isProtected(_ tank: TankState) -> Bool {
        tank.spawnProtectionTicks > 0 || tank.statusEffects["invincible"] != nil
    }

    /// A tank killed earlier in the tick is no longer a target.
    static func isAlive(_ tank: TankState) -> Bool { tank.armor > 0 }

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
            guard isAlive(tank), tank.statusEffects["airborne"] == nil else { continue } // no fire in flight
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
                // A depleted special gun falls back to the normal round for
                // players (owner decision, ADR-0010): the trigger never goes
                // dead. The fallback shares the normal channel's cooldown and
                // active cap and costs no ammunition.
                let depleted: Bool
                if let owner = tank.ownerPlayerID {
                    let ammo = world.player(owner)?.specialAmmoByWeapon[weapon.id, default: 0] ?? 0
                    depleted = ammo < weapon.ammoCost
                } else {
                    depleted = false
                }
                if depleted, let normalWeapon = weapons.weapon("normal") {
                    fire(&world, tankIndex: index, weapon: normalWeapon, channel: .normal,
                         weapons: weapons, spawned: &spawned, events: &events)
                } else {
                    fire(&world, tankIndex: index, weapon: weapon, channel: .special,
                         weapons: weapons, spawned: &spawned, events: &events)
                }
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
        let cap = weapon.level(weapon.maxActive, power)
        let activeCount = tank.activeProjectileCounts[weapon.id, default: 0]
        // Projectiles at their active cap wait silently (the weapon is
        // "busy"); flame volleys use whole-volley admission below, which
        // dry-fires so the rejection is observable.
        if weapon.family != .fire { guard activeCount < cap else { return } }

        /// Every dry-fire path applies the channel cooldown (§12.4: a held
        /// button must not emit a dry-fire per tick) and spends nothing.
        func dryFire() {
            events.append(.dryFire(entityID: tank.entityID, ownerPlayerID: tank.ownerPlayerID,
                                   weaponID: weapon.id))
            tank.fireCooldowns[channel] = weapon.level(weapon.cooldownTicks, power)
            world.tanks[tankIndex] = tank
        }

        // Ammunition lives on the owning player (§6.4); AI tanks are exempt.
        if channel == .special, let owner = tank.ownerPlayerID {
            let ammo = world.player(owner)?.specialAmmoByWeapon[weapon.id, default: 0] ?? 0
            guard ammo >= weapon.ammoCost else { dryFire(); return }
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
                dryFire()
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
            events.append(.minePlaced(entityID: id, ownerPlayerID: tank.ownerPlayerID,
                                      level: power, position: mineCenter))
        case .fire:
            // A flame wall as wide as the tank (the two cross-axis cells the
            // 2-cell footprint spans, symmetric about the tank's center
            // line), marching three cells forward. Each column advances
            // independently; walls and water stop it (fire-hazard-vs-terrain,
            // §8.5). The base admits ONE contact patch per column — that
            // patch is how the objective burns (fire is an ADR-0005 damage
            // source) — and the column stops there: flames never pass
            // through the structure to its far side.
            let filter: FireTeamFilter = .enemyOnly // campaign player default (§8.7)
            let horizontal = tank.facing.vector.x != 0
            let crossTopLeft = horizontal ? tank.positionSubunits.y : tank.positionSubunits.x
            let crossCells = [crossTopLeft / cell, (crossTopLeft + footprint - 1) / cell]
            var patches: [(cx: Int, cy: Int)] = []
            for cross in Set(crossCells).sorted() {
                for step in 1...3 {
                    let along = (horizontal ? center.x : center.y)
                        + (tank.facing.vector.x + tank.facing.vector.y) * (footprint / 2 + cell / 2 + (step - 1) * cell)
                    let (cx, cy) = horizontal ? (along / cell, cross) : (cross, along / cell)
                    guard world.terrain.isInside(cellX: cx, cellY: cy) else { break }
                    let kind = world.terrain[cx, cy].kind
                    if kind.isWall || kind == .water { break }
                    patches.append((cx, cy))
                    if cellTouchesBase(world, cellX: cx, cellY: cy) { break }
                }
            }
            // Muzzle flush against a wall or water: nothing to ignite (a
            // flush base still receives its contact patch). A volley is
            // admitted whole or not at all (the per-patch count must never
            // exceed the cap).
            guard !patches.isEmpty, activeCount + patches.count <= cap else {
                dryFire()
                return
            }
            for (cx, cy) in patches {
                let patchCenter = Vec2i(x: cx * cell + cell / 2, y: cy * cell + cell / 2)
                let id = world.claimEntityID()
                let lifetime = weapon.level(weapon.lifetimeTicks, power)
                world.fireHazards.append(FireHazardState(
                    entityID: id, ownerEntityID: tank.entityID, ownerPlayerID: tank.ownerPlayerID,
                    teamID: tank.teamID, filter: filter, positionSubunits: patchCenter,
                    lifetimeRemainingTicks: lifetime,
                    damagePerTouch: weapon.level(weapon.tankDamage, power),
                    spreadsAtTicks: foliageSpreadTick(world, cellX: cx, cellY: cy, lifetime: lifetime, weapons: weapons)))
                spawned.insert(id)
            }
            // Active-count bookkeeping is per PATCH (cleanup decrements one
            // per expired patch); the shared +1 below completes the total.
            tank.activeProjectileCounts[weapon.id, default: 0] += patches.count - 1
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
        events.append(.weaponFired(entityID: tank.entityID, ownerPlayerID: tank.ownerPlayerID,
                                   weaponID: weapon.id, channel: channel,
                                   position: tank.positionSubunits, facing: tank.facing))
    }

    private static func minePlacement(
        _ world: WorldState, center: Vec2i, tank: TankState, weapons: WeaponRuleset
    ) -> (onWater: Bool, ())? {
        let cell = SpatialUnits.subunitsPerCell
        let cx = center.x / cell, cy = center.y / cell
        guard world.terrain.isInside(cellX: cx, cellY: cy) else { return nil }
        let kind = world.terrain[cx, cy].kind
        if kind.isWall || kind == .base { return nil }
        if cellTouchesBase(world, cellX: cx, cellY: cy) { return nil }
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

    /// The base is an entity, not terrain: geometry decides whether a cell
    /// is part of the objective.
    static func cellTouchesBase(_ world: WorldState, cellX: Int, cellY: Int) -> Bool {
        guard let base = world.base else { return false }
        let cell = SpatialUnits.subunitsPerCell
        let minX = cellX * cell, minY = cellY * cell
        let p = base.topLeftSubunits
        return minX < p.x + base.sizeSubunits && minX + cell > p.x
            && minY < p.y + base.sizeSubunits && minY + cell > p.y
    }

    // MARK: - Steps 9–10: the global contact queue

    /// Uniform motion of one projectile within the tick.
    private struct Motion {
        let from: Vec2i
        let vector: Vec2i
        let distance: Int
        func position(at travelled: Int) -> Vec2i { from + vector * travelled }
        var velocity: Vec2i { vector * distance }
    }

    /// Exact rational time within the tick (0…1), compared by
    /// cross-multiplication so ordering never touches floating point.
    private struct Fraction: Comparable {
        let num: Int
        let den: Int // > 0
        init(_ num: Int, _ den: Int) {
            precondition(den != 0)
            if den < 0 { self.num = -num; self.den = -den } else { self.num = num; self.den = den }
        }
        static let zero = Fraction(0, 1)
        static let one = Fraction(1, 1)
        static func < (a: Fraction, b: Fraction) -> Bool { a.num * b.den < b.num * a.den }
        static func == (a: Fraction, b: Fraction) -> Bool { a.num * b.den == b.num * a.den }
    }

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

    /// What a projectile meets along its remaining segment. Targets are
    /// named by entity ID (indices shift as mines are removed mid-tick).
    private enum SweepHit {
        case boundary
        case terrain(qx: Int, qy: Int)
        case tank(entityID: Int)
        case base
        case mine(entityID: Int)
    }

    /// Category order for ties at the same time: boundary → terrain → tank
    /// → base → mine → projectile-versus-projectile (documented).
    private struct WorldCandidate {
        let time: Fraction
        let order: Int
        let targetID: Int
        let entryDistance: Int // from the projectile's current progress
        let hit: SweepHit
    }

    private struct PairCandidate: Equatable {
        let a: Int
        let b: Int
        let time: Fraction
    }

    private struct ContactKey {
        let time: Fraction
        let order: Int
        let primaryID: Int
        let secondaryID: Int
        func isEarlier(than other: ContactKey) -> Bool {
            if time != other.time { return time < other.time }
            if order != other.order { return order < other.order }
            if primaryID != other.primaryID { return primaryID < other.primaryID }
            return secondaryID < other.secondaryID
        }
    }

    private static func resolveContacts(
        _ world: inout WorldState, motions: [Int: Motion], weapons: WeaponRuleset,
        explosions: inout [Explosion], destroyed: inout Set<Int>,
        events: inout [DomainEvent]
    ) {
        let half = weapons.projectileHalfExtentSubunits
        let mineHalf = weapons.mineHalfExtentSubunits
        let ids = world.projectiles.map(\.entityID) // ascending by invariant
        var progress: [Int: Int] = [:]
        for id in ids { progress[id] = 0 }

        // Projectile-versus-projectile: the true first-overlap time of two
        // uniformly moving boxes. Motion is uniform, so these never change
        // while the tick resolves; a pair simply drops when a member dies.
        var pairs: [PairCandidate] = []
        for (i, a) in world.projectiles.enumerated() {
            for b in world.projectiles[(i + 1)...] where a.teamID != b.teamID {
                guard let ma = motions[a.entityID], let mb = motions[b.entityID],
                      let t = firstOverlapTime(ma, mb, half: half) else { continue }
                pairs.append(PairCandidate(a: a.entityID, b: b.entityID, time: t))
            }
        }

        var candidates: [Int: WorldCandidate] = [:]
        for id in ids {
            candidates[id] = worldCandidate(world, projectileID: id, motions: motions,
                                            progress: progress[id]!, half: half, mineHalf: mineHalf)
        }

        while true {
            // The globally earliest contact (iteration over the sorted id
            // list; the key is total so the choice is unique).
            var bestKey: ContactKey?
            var bestWorld: Int?
            var bestPair: PairCandidate?
            for id in ids where !destroyed.contains(id) {
                guard let c = candidates[id] else { continue }
                let key = ContactKey(time: c.time, order: c.order, primaryID: id, secondaryID: c.targetID)
                if bestKey == nil || key.isEarlier(than: bestKey!) {
                    bestKey = key; bestWorld = id; bestPair = nil
                }
            }
            for pair in pairs where !destroyed.contains(pair.a) && !destroyed.contains(pair.b) {
                let key = ContactKey(time: pair.time, order: 5, primaryID: pair.a, secondaryID: pair.b)
                if bestKey == nil || key.isEarlier(than: bestKey!) {
                    bestKey = key; bestWorld = nil; bestPair = pair
                }
            }
            guard bestKey != nil else { break }

            if let pair = bestPair {
                resolvePair(&world, pair, motions: motions, weapons: weapons,
                            explosions: &explosions, destroyed: &destroyed, events: &events)
                pairs.removeAll { $0 == pair }
                continue
            }
            guard let id = bestWorld, let candidate = candidates[id] else { break }
            let outcome = applyWorldContact(
                &world, projectileID: id, candidate: candidate, motion: motions[id]!,
                progress: &progress, weapons: weapons, explosions: &explosions,
                destroyed: &destroyed, events: &events)
            if outcome.stale {
                candidates[id] = worldCandidate(world, projectileID: id, motions: motions,
                                                progress: progress[id]!, half: half, mineHalf: mineHalf)
                continue
            }
            // Re-derive what changed: the projectile itself, and any other
            // projectile whose named target vanished (a destroyed quadrant,
            // a removed mine). Removing an obstacle can only delay a hit,
            // so untouched candidates stay valid.
            candidates[id] = destroyed.contains(id) ? nil
                : worldCandidate(world, projectileID: id, motions: motions,
                                 progress: progress[id]!, half: half, mineHalf: mineHalf)
            if outcome.terrainChanged || outcome.removedMineID != nil || outcome.killedTankID != nil {
                for other in ids where other != id && !destroyed.contains(other) {
                    guard let c = candidates[other] else { continue }
                    let stale: Bool
                    switch c.hit {
                    case .terrain(let qx, let qy): stale = !solidQuadrant(world.terrain, qx: qx, qy: qy)
                    case .mine(let mineID): stale = mineID == outcome.removedMineID
                    case .tank(let tankID): stale = tankID == outcome.killedTankID
                    default: stale = false
                    }
                    if stale {
                        candidates[other] = worldCandidate(world, projectileID: other, motions: motions,
                                                           progress: progress[other]!, half: half,
                                                           mineHalf: mineHalf)
                    }
                }
            }
        }

        // Survivors commit their full displacement (a penetrating contact
        // must not cost the remaining travel of the tick).
        for i in world.projectiles.indices where !destroyed.contains(world.projectiles[i].entityID) {
            if let m = motions[world.projectiles[i].entityID], m.distance > 0 {
                world.projectiles[i].positionSubunits = m.position(at: m.distance)
            }
        }
    }

    /// First time in (0…1) at which two uniformly moving projectile boxes
    /// overlap, or nil. Per-axis interval intersection of the relative
    /// motion; strict overlap (touching edges do not collide), matching the
    /// box conventions of the world sweep.
    private static func firstOverlapTime(_ a: Motion, _ b: Motion, half: Int) -> Fraction? {
        let bound = 2 * half
        let r0 = Vec2i(x: b.from.x - a.from.x, y: b.from.y - a.from.y)
        let rv = Vec2i(x: b.velocity.x - a.velocity.x, y: b.velocity.y - a.velocity.y)
        func axis(_ r0: Int, _ rv: Int) -> (Fraction, Fraction)? {
            if rv == 0 { return abs(r0) < bound ? (.zero, .one) : nil }
            let t1 = Fraction(-bound - r0, rv), t2 = Fraction(bound - r0, rv)
            return t1 < t2 ? (t1, t2) : (t2, t1)
        }
        guard let x = axis(r0.x, rv.x), let y = axis(r0.y, rv.y) else { return nil }
        let lo = max(max(x.0, y.0), .zero)
        let hi = min(min(x.1, y.1), .one)
        return lo < hi ? lo : nil
    }

    private static func worldCandidate(
        _ world: WorldState, projectileID: Int, motions: [Int: Motion], progress: Int,
        half: Int, mineHalf: Int
    ) -> WorldCandidate? {
        guard let motion = motions[projectileID], motion.distance > 0, progress <= motion.distance,
              let projectile = world.projectiles.first(where: { $0.entityID == projectileID })
        else { return nil }
        guard let found = earliestHit(world, projectile: projectile,
                                      from: motion.position(at: progress),
                                      remaining: motion.distance - progress,
                                      half: half, mineHalf: mineHalf)
        else { return nil }
        return WorldCandidate(time: Fraction(progress + found.t, motion.distance),
                              order: found.order, targetID: found.id,
                              entryDistance: found.t, hit: found.hit)
    }

    private struct ContactOutcome {
        var terrainChanged = false
        var removedMineID: Int?
        var killedTankID: Int?
        /// The cached target no longer exists (a tank killed or a mine
        /// removed by an earlier contact this tick): nothing was applied and
        /// the projectile's candidate must be re-derived.
        var stale = false
    }

    /// Applies one world contact for a projectile at its entry point.
    private static func applyWorldContact(
        _ world: inout WorldState, projectileID: Int, candidate: WorldCandidate, motion: Motion,
        progress: inout [Int: Int], weapons: WeaponRuleset,
        explosions: inout [Explosion], destroyed: inout Set<Int>,
        events: inout [DomainEvent]
    ) -> ContactOutcome {
        var outcome = ContactOutcome()
        guard let index = world.projectiles.firstIndex(where: { $0.entityID == projectileID }),
              let weapon = weapons.weapon(world.projectiles[index].weaponID) else { return outcome }
        var projectile = world.projectiles[index]
        let travelled = progress[projectileID]! + candidate.entryDistance
        projectile.positionSubunits = motion.position(at: travelled)
        let half = weapons.projectileHalfExtentSubunits

        func destroy(_ impact: ImpactTarget) {
            world.projectiles[index] = projectile
            events.append(.projectileDestroyed(entityID: projectile.entityID, weaponID: projectile.weaponID,
                                               position: projectile.positionSubunits, impact: impact))
            if weapon.family == .explosion {
                explosions.append(Explosion(from: projectile, weapon: weapon))
            }
            removeProjectile(&world, entityID: projectile.entityID, destroyed: &destroyed)
        }
        func survive(_ impact: ImpactTarget) {
            events.append(.projectileHit(entityID: projectile.entityID, weaponID: projectile.weaponID,
                                         position: projectile.positionSubunits, impact: impact))
            progress[projectileID] = travelled + 1 // step past the contact
            world.projectiles[index] = projectile
        }

        // A cached target that vanished since the candidate was derived is
        // not a contact: report stale, apply nothing.
        switch candidate.hit {
        case .terrain(let qx, let qy) where !solidQuadrant(world.terrain, qx: qx, qy: qy):
            outcome.stale = true; return outcome
        case .tank(let tankID) where !(world.tanks.first { $0.entityID == tankID }.map(isAlive) ?? false):
            outcome.stale = true; return outcome
        case .mine(let mineID) where !world.mines.contains { $0.entityID == mineID }:
            outcome.stale = true; return outcome
        default: break
        }

        switch candidate.hit {
        case .boundary:
            destroy(.boundary)

        case .terrain(let qx, let qy):
            let material: ImpactTarget = world.terrain[qx / 2, qy / 2].kind.isSteelFamily ? .steel : .brick
            let destroyedCount = applyTerrainDamage(
                &world, entryQuadrant: (qx, qy), direction: projectile.direction,
                crossCenter: projectile.positionSubunits, half: half,
                brickDamage: weapon.level(weapon.brickDamage, projectile.powerLevel),
                steelDamage: weapon.level(weapon.steelDamage, projectile.powerLevel),
                events: &events)
            outcome.terrainChanged = destroyedCount > 0
            // Owner rule: the AP shell cuts a whole corridor, so brick it
            // actually broke through costs no penetration (GAME_RULES §17.1).
            // A round that only cracked white brick broke nothing and stops.
            let freeCut = weapon.cutsThroughBrick && material == .brick // kind read before damage
            if destroyedCount == 0 || (!freeCut && projectile.penetrationRemaining < destroyedCount) {
                destroy(material)
            } else {
                if !freeCut { projectile.penetrationRemaining -= destroyedCount }
                survive(material)
            }

        case .tank(let tankID):
            guard let tankIndex = world.tanks.firstIndex(where: { $0.entityID == tankID }) else { break }
            let target = world.tanks[tankIndex]
            if isProtected(target) {
                // Deflection (§8.5): destroyed without damage or detonation.
                world.projectiles[index] = projectile
                events.append(.projectileDestroyed(entityID: projectile.entityID, weaponID: projectile.weaponID,
                                                   position: projectile.positionSubunits, impact: .deflected))
                removeProjectile(&world, entityID: projectile.entityID, destroyed: &destroyed)
                break
            }
            if weapon.family == .explosion {
                // Explosive shells deal ALL their damage through the blast —
                // no separate contact damage (no double-dipping).
                destroy(.tank)
                break
            }
            applyTankDamage(&world, tankIndex: tankIndex,
                            damage: weapon.level(weapon.tankDamage, projectile.powerLevel),
                            sourceWeaponID: weapon.id, events: &events)
            if !isAlive(world.tanks[tankIndex]) { outcome.killedTankID = tankID }
            if projectile.penetrationRemaining < 1 {
                destroy(.tank)
            } else {
                projectile.penetrationRemaining -= 1
                // Each distinct target is penetrated once (§8.4).
                projectile.hitTankIDs = (projectile.hitTankIDs + [tankID]).sorted()
                survive(.tank)
            }

        case .base:
            // Explosive shells apply their damage once, via the blast, just
            // as they do on tank contact.
            if weapon.family != .explosion {
                applyBaseHit(&world, damage: weapon.level(weapon.tankDamage, projectile.powerLevel),
                             sourceIsAllied: projectile.teamID == world.base?.teamID,
                             weapons: weapons, events: &events)
            }
            destroy(.base)

        case .mine(let mineID):
            guard let mineIndex = world.mines.firstIndex(where: { $0.entityID == mineID }) else { break }
            let mine = world.mines[mineIndex]
            if weapon.family == .explosion {
                // Detonating on contact; the area blast chains qualified
                // mines breadth-first (§8.5).
                destroy(.mine)
                break
            }
            // Plain projectile vs mine: disarms the hardware (no blast).
            world.mines.remove(at: mineIndex)
            decrementActiveCount(&world, ownerEntityID: mine.ownerEntityID, weaponID: "mine")
            events.append(.mineRemoved(entityID: mineID, position: mine.positionSubunits))
            outcome.removedMineID = mineID
            if projectile.penetrationRemaining < 1 {
                destroy(.mine)
            } else {
                projectile.penetrationRemaining -= 1
                survive(.mine)
            }
        }
        return outcome
    }

    private static func resolvePair(
        _ world: inout WorldState, _ pair: PairCandidate, motions: [Int: Motion],
        weapons: WeaponRuleset, explosions: inout [Explosion], destroyed: inout Set<Int>,
        events: inout [DomainEvent]
    ) {
        guard let ia = world.projectiles.firstIndex(where: { $0.entityID == pair.a }),
              let ib = world.projectiles.firstIndex(where: { $0.entityID == pair.b }),
              let ma = motions[pair.a], let mb = motions[pair.b] else { return }
        // Positions at the contact time (integer travel, floor).
        world.projectiles[ia].positionSubunits = ma.position(at: ma.distance * pair.time.num / pair.time.den)
        world.projectiles[ib].positionSubunits = mb.position(at: mb.distance * pair.time.num / pair.time.den)
        let a = world.projectiles[ia], b = world.projectiles[ib]
        // Durability comparison (§8.4): higher survives, equal → both.
        if a.durability <= b.durability {
            destroyPvP(&world, a, weapons: weapons, explosions: &explosions, destroyed: &destroyed, events: &events)
        }
        if b.durability <= a.durability {
            destroyPvP(&world, b, weapons: weapons, explosions: &explosions, destroyed: &destroyed, events: &events)
        }
    }

    private static func destroyPvP(
        _ world: inout WorldState, _ p: ProjectileState, weapons: WeaponRuleset,
        explosions: inout [Explosion], destroyed: inout Set<Int>, events: inout [DomainEvent]
    ) {
        guard !destroyed.contains(p.entityID) else { return }
        events.append(.projectileDestroyed(entityID: p.entityID, weaponID: p.weaponID,
                                           position: p.positionSubunits, impact: .projectile))
        if let weapon = weapons.weapon(p.weaponID), weapon.family == .explosion {
            explosions.append(Explosion(from: p, weapon: weapon))
        }
        removeProjectile(&world, entityID: p.entityID, destroyed: &destroyed)
    }

    /// Earliest hit along the remaining segment, or nil for free flight.
    /// Water, ice, foliage, and pickups are pass-over (§7.3, §8.5). Tanks
    /// already penetrated by this shell and tanks killed earlier in the tick
    /// are not targets.
    private static func earliestHit(
        _ world: WorldState, projectile: ProjectileState,
        from: Vec2i, remaining: Int, half: Int, mineHalf: Int
    ) -> (t: Int, order: Int, id: Int, hit: SweepHit)? {
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
            if t <= remaining { consider(max(0, t), 0, 0, .boundary) }
        }

        // Terrain quadrants (brick/steel block shots; §7.3).
        if let (t, qx, qy) = firstSolidQuadrant(world.terrain, from: from, vector: vector,
                                                remaining: remaining, half: half) {
            consider(t, 1, qy * 1000 + qx, .terrain(qx: qx, qy: qy))
        }

        // Enemy tanks (allied tanks are pass-through: allied damage is
        // disabled, D-010; own tank never collides with its own shot).
        let footprint = SpatialUnits.standardTankFootprintSubunits
        for tank in world.tanks
        where tank.teamID != projectile.teamID && isAlive(tank)
            && tank.statusEffects["airborne"] == nil // in flight: untargetable (§8.6)
            && !projectile.hitTankIDs.contains(tank.entityID) {
            let p = tank.positionSubunits
            if let t = boxEntry(from: from, vector: vector, remaining: remaining, half: half,
                                minX: p.x, minY: p.y, maxX: p.x + footprint, maxY: p.y + footprint) {
                consider(t, 2, tank.entityID, .tank(entityID: tank.entityID))
            }
        }

        // Base structure.
        if let base = world.base {
            let p = base.topLeftSubunits
            if let t = boxEntry(from: from, vector: vector, remaining: remaining, half: half,
                                minX: p.x, minY: p.y,
                                maxX: p.x + base.sizeSubunits, maxY: p.y + base.sizeSubunits) {
                consider(t, 3, 0, .base)
            }
        }

        // Mine hardware (the ruleset's hardware extent, as placement and
        // Moon contact use).
        for mine in world.mines {
            let p = mine.positionSubunits
            if let t = boxEntry(from: from, vector: vector, remaining: remaining, half: half,
                                minX: p.x - mineHalf, minY: p.y - mineHalf,
                                maxX: p.x + mineHalf, maxY: p.y + mineHalf) {
                consider(t, 4, mine.entityID, .mine(entityID: mine.entityID))
            }
        }
        return best
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
            // The quadrant the leading edge ENTERS: for a positive direction
            // the edge is the box's max (exclusive), which lies in the
            // quadrant ahead; for a negative direction the edge is the box's
            // min (inclusive), and the quadrant entered at a boundary is the
            // one just below it — hence the -1 (a mirrored shot must meet a
            // wall at the same distance, not one quadrant later).
            let leadX = vector.x > 0 ? p.x + half : p.x - half - 1
            let leadY = vector.y > 0 ? p.y + half : p.y - half - 1
            // Leading edge sample band across the cross axis.
            let (loX, hiX) = vector.x != 0 ? (leadX, leadX) : (p.x - half, p.x + half - 1)
            let (loY, hiY) = vector.y != 0 ? (leadY, leadY) : (p.y - half, p.y + half - 1)
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
        guard qx >= 0, qy >= 0 else { return false }
        let cx = qx / 2, cy = qy / 2
        guard terrain.isInside(cellX: cx, cellY: cy) else { return false }
        let cell = terrain[cx, cy]
        guard cell.kind.isWall else { return false }
        let bit = (qy % 2) * 2 + (qx % 2)
        return cell.quadrantMask & (1 << bit) != 0
    }

    // MARK: - Damage application

    /// Applies one round's worth of damage to a single wall quadrant.
    /// Red brick and grey steel lose the quadrant outright; white brick
    /// needs two rounds per quadrant (owner rule, GAME_RULES §3.5) — the
    /// first cracks it, the second removes it; white steel never yields.
    /// Emptied cells normalize to ground so pickup legality and hidden
    /// treasures keep agreeing with "final quadrant destroyed".
    /// Returns what happened to the quadrant.
    @discardableResult
    static func damageQuadrant(_ world: inout WorldState, cellX: Int, cellY: Int, bit: Int) -> WallDamage {
        var cell = world.terrain[cellX, cellY]
        let flag = 1 << bit
        guard cell.quadrantMask & flag != 0, !cell.kind.isIndestructibleWall else { return .none }
        if cell.kind.roundsPerQuadrant > 1, cell.crackMask & flag == 0 {
            cell.crackMask |= flag
            world.terrain[cellX, cellY] = cell
            return .cracked
        }
        cell.quadrantMask &= ~flag
        cell.crackMask &= ~flag
        if cell.quadrantMask == 0 { cell = TerrainCell(kind: .ground) }
        world.terrain[cellX, cellY] = cell
        return .removed
    }

    /// Destroys quadrant layers at the impact point. Layer i falls when the
    /// material's damage value exceeds i (brick 1 = front layer, 2 = full
    /// cell depth; steel 0 = indestructible to this weapon).
    ///
    /// Blast width (reference-heritage): every shot carves a TANK-WIDE notch
    /// — 2 cells / 4 quadrants across the cross-axis, centered on the
    /// projectile path and snapped to the nearest cell seam. This matches
    /// the reference (a 16px bullet swath for a 32px tank on 16px cells,
    /// always two shots to drill a passable hole) and keeps the result
    /// independent of sub-cell tank alignment — an off-lane shot must not
    /// leave half-height slivers (owner report). Only the quadrants the
    /// projectile's own box pierces consume `penetration_count`; collateral
    /// strip quadrants do not. Returns the pierced-quadrant count.
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
            let crossPos = horizontal ? crossCenter.y : crossCenter.x
            let pierceLo = (crossPos - half) / quadrant
            let pierceHi = (crossPos + half - 1) / quadrant
            // Strip: a fixed tank-wide swath (2 cells / 4 quadrants) around
            // the nearest cell seam to the projectile path.
            let cell = SpatialUnits.subunitsPerCell
            let seamQuadrant = (crossPos + cell / 2) / cell * 2
            let stripLo = seamQuadrant - 2
            let stripHi = seamQuadrant + 1
            for cross in stripLo...stripHi {
                let (qx, qy) = horizontal ? (lqx, cross) : (cross, lqy)
                guard solidQuadrant(world.terrain, qx: qx, qy: qy) else { continue }
                let cx = qx / 2, cy = qy / 2
                let kind = world.terrain[cx, cy].kind
                let damage = kind.isBrickFamily ? brickDamage : steelDamage
                guard damage > layer else { continue }
                let result = damageQuadrant(&world, cellX: cx, cellY: cy,
                                            bit: (qy % 2) * 2 + (qx % 2))
                guard result != .none else { continue }
                if result == .removed, (pierceLo...pierceHi).contains(cross) { piercedCount += 1 }
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
    /// in one blow. Armor is only touched once the shield is gone. Protected
    /// (spawning / invincible) and already-dead tanks take nothing and emit
    /// nothing. Returns whether the hit landed.
    @discardableResult
    static func applyTankDamage(
        _ world: inout WorldState, tankIndex: Int, damage: Int,
        sourceWeaponID: String, events: inout [DomainEvent]
    ) -> Bool {
        guard damage > 0 else { return false }
        let tank = world.tanks[tankIndex]
        guard isAlive(tank), !isProtected(tank) else { return false }
        if tank.shieldHP > 0 {
            let shatters = ["explosion", "mine", "bomb"].contains(sourceWeaponID)
            world.tanks[tankIndex].shieldHP = shatters ? 0 : max(0, tank.shieldHP - damage)
            events.append(.tankShieldHit(entityID: tank.entityID, ownerPlayerID: tank.ownerPlayerID,
                                         remaining: world.tanks[tankIndex].shieldHP,
                                         position: tank.positionSubunits))
            return true
        }
        world.tanks[tankIndex].armor -= damage
        events.append(.tankDamaged(entityID: tank.entityID, ownerPlayerID: tank.ownerPlayerID,
                                   damage: damage, sourceWeaponID: sourceWeaponID,
                                   position: tank.positionSubunits))
        return true
    }

    /// Returns whether the hit landed (shield and the ADR-0005 flag deflect).
    @discardableResult
    static func applyBaseHit(
        _ world: inout WorldState, damage: Int, sourceIsAllied: Bool,
        weapons: WeaponRuleset, events: inout [DomainEvent]
    ) -> Bool {
        guard var base = world.base, damage > 0, base.durability > 0 else { return false }
        if base.shieldRemainingTicks > 0 { return false } // shield deflects (§8.5)
        if sourceIsAllied && !weapons.alliedBaseDamage { return false } // ADR-0005
        base.durability = max(0, base.durability - damage)
        world.base = base
        events.append(.baseDamaged(damage: damage, remaining: base.durability, allied: sourceIsAllied))
        return true
    }

    // MARK: - Mines and fire hazards

    private static func resolveMineTriggers(
        _ world: inout WorldState, weapons: WeaponRuleset,
        explosions: inout [Explosion], launches: inout [(tankID: Int, level: Int)], events: inout [DomainEvent]
    ) {
        guard let mineWeapon = weapons.weapon("mine") else { return }
        let footprint = SpatialUnits.standardTankFootprintSubunits
        var triggered: [Int] = []
        var triggeringTank: [Int: Int] = [:] // mine → the tank that set it off
        var removedByMoon: [Int] = []
        for mine in world.mines where mine.phase == .armed {
            for tank in world.tanks where tank.teamID != mine.teamID && isAlive(tank)
                && tank.statusEffects["airborne"] == nil {
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
                    triggeringTank[mine.entityID] = tank.entityID
                    break
                }
            }
        }
        for id in removedByMoon.sorted() {
            if let mine = world.mines.first(where: { $0.entityID == id }) {
                world.mines.removeAll { $0.entityID == id }
                decrementActiveCount(&world, ownerEntityID: mine.ownerEntityID, weaponID: "mine")
                events.append(.mineRemoved(entityID: id, position: mine.positionSubunits))
            }
        }
        for id in triggered.sorted() {
            if let mine = world.mines.first(where: { $0.entityID == id }) {
                world.mines.removeAll { $0.entityID == id }
                decrementActiveCount(&world, ownerEntityID: mine.ownerEntityID, weaponID: "mine")
                events.append(.mineTriggered(entityID: id, position: mine.positionSubunits))
                explosions.append(Explosion(fromMine: mine, weapon: mineWeapon))
                if let tankID = triggeringTank[id] { launches.append((tankID, mine.level)) }
            }
        }
    }

    /// Mine launch/flight (§8.6, ADR-0016), applied after the blast: a
    /// triggering tank that survived (or deflected) the blast and does not
    /// carry Memory of Sea is thrown along its travel direction (its
    /// movement intent, else its facing) by the level's distance and goes
    /// airborne for the level's ticks; it lands when the status expires
    /// (Simulation step 2). Level 0 and a disabled ruleset launch nothing.
    private static func applyMineLaunches(
        _ world: inout WorldState, launches: [(tankID: Int, level: Int)], weapons: WeaponRuleset,
        events: inout [DomainEvent]
    ) {
        guard weapons.mineLaunchEnabled else { return }
        let footprint = SpatialUnits.standardTankFootprintSubunits
        for (tankID, level) in launches.sorted(by: { $0.tankID < $1.tankID }) {
            guard let index = world.tanks.firstIndex(where: { $0.entityID == tankID }) else { continue }
            var tank = world.tanks[index]
            guard isAlive(tank), tank.statusEffects["airborne"] == nil,
                  tank.equipmentID != "memory_of_sea" else { continue }
            let clamped = max(0, min(3, level))
            let distance = weapons.mineLaunchDistanceSubunits[clamped]
            let ticks = weapons.mineAirborneTicks[clamped]
            guard distance > 0, ticks > 0 else { continue }
            let direction = tank.movementIntent ?? tank.facing
            let from = tank.positionSubunits
            let nominal = from + direction.vector * distance
            let target = Vec2i(x: max(0, min(world.arena.widthSubunits - footprint, nominal.x)),
                               y: max(0, min(world.arena.heightSubunits - footprint, nominal.y)))
            tank.statusEffects["airborne"] = ticks
            // The slow (§8.6) is one status set now: it has no effect while
            // airborne (no movement) and runs on for the level's ticks
            // after landing — no extra state to carry into the landing.
            let slow = weapons.mineSlowTicks[clamped]
            if slow > 0 { tank.statusEffects["slowed"] = ticks + slow }
            tank.landingSubunits = target
            tank.movementIntent = nil
            tank.bufferedDirection = nil
            tank.bufferedDirectionRemainingTicks = 0
            tank.slideDirection = nil
            tank.slideMomentumSubunits = 0
            world.tanks[index] = tank
            events.append(.tankLaunched(entityID: tankID, ownerPlayerID: tank.ownerPlayerID, from: from, to: target))
        }
    }

    /// The tick at which a flame placed on `cell` spreads (ADR-0017): its
    /// lifetime minus the spread delay, when the cell is foliage and the
    /// rule is on; nil otherwise.
    static func foliageSpreadTick(_ world: WorldState, cellX: Int, cellY: Int, lifetime: Int,
                                  weapons: WeaponRuleset) -> Int? {
        guard weapons.foliageSpreadDelayTicks > 0, world.terrain.isInside(cellX: cellX, cellY: cellY),
              world.terrain[cellX, cellY].kind == .foliage else { return nil }
        let at = lifetime - weapons.foliageSpreadDelayTicks
        return at > 0 ? at : nil
    }

    /// Foliage fire (ADR-0017, owner rule: "火焰弹打到草坪的时候，应该需要把相邻的草坪
    /// 都点着"): a flame whose remaining lifetime reaches its spread tick
    /// ignites the four neighbouring foliage cells that hold no flame yet —
    /// ownerless patches (sentinel −1: no active-count slot, so the
    /// wildfire never blocks the shooter's next volley) that keep the
    /// parent's team, filter, damage and full lifetime and spread on in
    /// turn. Deterministic: parents ascending by entity id, neighbours in
    /// up/right/down/left order.
    private static func spreadFoliageFire(_ world: inout WorldState, weapons: WeaponRuleset) {
        guard weapons.foliageSpreadDelayTicks > 0 else { return }
        let cell = SpatialUnits.subunitsPerCell
        var occupied = Set<Int>()
        let width = world.arena.cellsWide
        for h in world.fireHazards { occupied.insert((h.positionSubunits.y / cell) * width + h.positionSubunits.x / cell) }
        var born: [FireHazardState] = []
        for i in world.fireHazards.indices {
            let parent = world.fireHazards[i]
            guard let at = parent.spreadsAtTicks, parent.lifetimeRemainingTicks == at else { continue }
            world.fireHazards[i].spreadsAtTicks = nil
            let cx = parent.positionSubunits.x / cell, cy = parent.positionSubunits.y / cell
            let lifetime = parent.lifetimeRemainingTicks + weapons.foliageSpreadDelayTicks
            for (dx, dy) in [(0, -1), (1, 0), (0, 1), (-1, 0)] {
                let nx = cx + dx, ny = cy + dy
                guard world.terrain.isInside(cellX: nx, cellY: ny), world.terrain[nx, ny].kind == .foliage,
                      occupied.insert(ny * width + nx).inserted else { continue }
                born.append(FireHazardState(
                    entityID: world.claimEntityID(), ownerEntityID: -1, ownerPlayerID: parent.ownerPlayerID,
                    teamID: parent.teamID, filter: parent.filter,
                    positionSubunits: Vec2i(x: nx * cell + cell / 2, y: ny * cell + cell / 2),
                    lifetimeRemainingTicks: lifetime, damagePerTouch: parent.damagePerTouch,
                    spreadsAtTicks: foliageSpreadTick(world, cellX: nx, cellY: ny, lifetime: lifetime, weapons: weapons)))
            }
        }
        world.fireHazards.append(contentsOf: born)
    }

    private static func resolveFireHazardDamage(
        _ world: inout WorldState, weapons: WeaponRuleset, events: inout [DomainEvent]
    ) {
        let cell = SpatialUnits.subunitsPerCell
        let footprint = SpatialUnits.standardTankFootprintSubunits
        for hazard in world.fireHazards {
            guard hazard.lifetimeRemainingTicks > 0 else { continue }
            let hx = hazard.positionSubunits.x - cell / 2, hy = hazard.positionSubunits.y - cell / 2
            for tankIndex in world.tanks.indices {
                let tank = world.tanks[tankIndex]
                switch hazard.filter { // §8.7
                case .both: break
                case .alliedOnly: if tank.teamID != hazard.teamID { continue }
                case .enemyOnly: if tank.teamID == hazard.teamID { continue }
                }
                guard isAlive(tank), !isProtected(tank), tank.statusEffects["airborne"] == nil else { continue }
                // One burn cadence per TANK across all patches: overlapping
                // flames never multiply damage (documented; status timer is
                // authoritative state and decrements in step 2).
                if tank.statusEffects["burn_immunity"] != nil { continue }
                let p = tank.positionSubunits
                guard p.x < hx + cell && p.x + footprint > hx
                    && p.y < hy + cell && p.y + footprint > hy else { continue }
                world.tanks[tankIndex].statusEffects["burn_immunity"] = weapons.fireDamageIntervalTicks
                applyTankDamage(&world, tankIndex: tankIndex, damage: hazard.damagePerTouch,
                                sourceWeaponID: "fire", events: &events)
            }
            // The objective burns too (fire is an allied damage source under
            // ADR-0005): one burn per interval across overlapping patches.
            // A deflected contact (shield, Casual flag) consumes no cadence.
            if let base = world.base, base.burnCooldownTicks == 0 {
                let b = base.topLeftSubunits
                if hx < b.x + base.sizeSubunits && hx + cell > b.x
                    && hy < b.y + base.sizeSubunits && hy + cell > b.y,
                   applyBaseHit(&world, damage: hazard.damagePerTouch,
                                sourceIsAllied: hazard.teamID == base.teamID,
                                weapons: weapons, events: &events) {
                    world.base?.burnCooldownTicks = weapons.fireDamageIntervalTicks
                }
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

        // Tanks: enemy only (allied damage disabled, D-010); protection
        // deflects inside applyTankDamage.
        for i in world.tanks.indices where world.tanks[i].teamID != explosion.teamID
            && world.tanks[i].statusEffects["airborne"] == nil {
            let p = world.tanks[i].positionSubunits
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
                let damage = world.terrain[cx, cy].kind.isBrickFamily ? explosion.brickDamage : explosion.steelDamage
                guard damage > 0 else { continue }
                guard damageQuadrant(&world, cellX: cx, cellY: cy,
                                     bit: (qy % 2) * 2 + (qx % 2)) != .none else { continue }
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
                events.append(.projectileDestroyed(entityID: p.entityID, weaponID: p.weaponID,
                                                   position: pos, impact: .explosion))
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

    /// The one exactly-once removal path: marks the projectile destroyed and
    /// releases its owner's active-count slot. Entity removal follows in
    /// `cleanup`.
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
        weapons: WeaponRuleset, pickups: PickupRuleset, events: inout [DomainEvent]
    ) {
        world.projectiles.removeAll { destroyedProjectiles.contains($0.entityID) }
        for hazard in world.fireHazards where hazard.lifetimeRemainingTicks <= 0 {
            decrementActiveCount(&world, ownerEntityID: hazard.ownerEntityID, weaponID: "fire")
            // Ice does not react to fire (owner, 2026-09-11 — this reverses
            // the earlier "fire melts ice" rule; GAME_RULES §17.1).
            let cell = SpatialUnits.subunitsPerCell
            let cx = hazard.positionSubunits.x / cell, cy = hazard.positionSubunits.y / cell
            // Foliage a flame burns out on is gone (ADR-0017, owner rule).
            if weapons.foliageBurnsAway, world.terrain.isInside(cellX: cx, cellY: cy),
               world.terrain[cx, cy].kind == .foliage {
                world.terrain[cx, cy] = TerrainCell(kind: .ground)
                events.append(.terrainChanged(cellX: cx, cellY: cy, quadrantMask: 0))
            }
        }
        world.fireHazards.removeAll { $0.lifetimeRemainingTicks <= 0 }

        // 11. Pickup collection (after movement and damage, §9.3).
        Stage.processPickups(&world, weapons: weapons, rules: pickups, events: &events)

        // 12. Deaths: score, drops, and player lifecycle, then removal.
        let deadTanks = world.tanks.filter { $0.armor <= 0 }
        for tank in deadTanks {
            events.append(.tankDestroyed(entityID: tank.entityID, ownerPlayerID: tank.ownerPlayerID,
                                         position: tank.positionSubunits))
        }
        Stage.processDeaths(&world, deadTanks: deadTanks, rules: pickups, events: &events)
        for tank in deadTanks { world.removeTank(entityID: tank.entityID) }
    }
}
