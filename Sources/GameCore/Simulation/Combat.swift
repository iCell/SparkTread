/// Firing and projectile contacts (GAME_RULES §5–§6, §12 steps 4–5).
/// Every contact of a tick — shell against shell, wall, base, boundary or
/// tank — resolves from ONE queue in time order within the tick; ties go
/// shell-shell → wall/base/boundary → tank, then shell id, then target.
/// Explosions resolve immediately inside the queue against a fresh wall
/// snapshot; later contacts whose target vanished are re-derived.
enum Combat {
    // MARK: - Entry point

    static func run(
        _ world: inout WorldState,
        specialInput: [Int: Simulation.SpecialInput],
        aiFire: [Int: (normal: Bool, special: Bool)],
        weapons: WeaponRuleset,
        events: inout [DomainEvent]
    ) {
        let spawned = processFire(&world, specialInput: specialInput, aiFire: aiFire,
                                  weapons: weapons, events: &events)

        // Advance: W ← clamp(W + a, 0, 60·vmax); travel W / 3 600 000;
        // lifetime − 1. New shells stay at the muzzle this tick.
        var motions: [Int: Motion] = [:]
        for i in world.projectiles.indices {
            var p = world.projectiles[i]
            if spawned.contains(p.entityID) {
                motions[p.entityID] = Motion(from: p.positionSubunits, vector: p.direction.vector, distance: 0)
                continue
            }
            p.launchOriginSubunits = nil
            guard let weapon = weapons.weapon(p.weaponID) else { continue }
            p.velocity60 = max(0, min(60 * weapon.maxSpeedMilliSubunitsPerSecond,
                                      p.velocity60 + weapon.accelerationMilliSubunitsPerSecond2))
            let travel = p.travelRemainder + p.velocity60
            let distance = travel / WeaponDefinition.travelUnitsPerSubunit
            p.travelRemainder = travel % WeaponDefinition.travelUnitsPerSubunit
            p.lifetimeRemainingTicks -= 1
            motions[p.entityID] = Motion(from: p.positionSubunits, vector: p.direction.vector, distance: distance)
            world.projectiles[i] = p
        }

        var destroyed = Set<Int>()
        resolveContacts(&world, motions: motions, weapons: weapons, destroyed: &destroyed, events: &events)

        // Lifetime expiry after every contact, ascending id.
        for p in world.projectiles where !destroyed.contains(p.entityID) && p.lifetimeRemainingTicks <= 0 {
            guard let weapon = weapons.weapon(p.weaponID) else { continue }
            terminate(&world, projectileID: p.entityID, weapon: weapon, impact: .expired,
                      effect: .open(center: p.positionSubunits), weapons: weapons,
                      destroyed: &destroyed, events: &events)
        }
        world.projectiles.removeAll { destroyed.contains($0.entityID) }
    }

    // MARK: - Damage policy

    /// Spawn protection and invincibility deflect every damage source.
    static func isProtected(_ tank: TankState) -> Bool {
        tank.spawnProtectionTicks > 0 || tank.statusEffects["invincible"] != nil
    }

    static func isAlive(_ tank: TankState) -> Bool { tank.armor > 0 }

    /// Who dealt a hit, for shields, kill attribution and statistics.
    struct DamageSource {
        var weaponID: String
        var ownerPlayerID: PlayerID?
        var explosive: Bool
    }

    /// Shield-aware damage (§6.2): non-explosive damage chips the shield,
    /// a blast shatters it; neither overflows into armor. Protected and dead
    /// tanks take nothing. A player tank that takes damage breaks its
    /// MaxHits streak. Returns whether the hit landed.
    @discardableResult
    static func applyTankDamage(_ world: inout WorldState, tankIndex: Int, damage: Int,
                                source: DamageSource, events: inout [DomainEvent]) -> Bool {
        guard damage > 0 else { return false }
        let tank = world.tanks[tankIndex]
        guard isAlive(tank), !isProtected(tank) else { return false }
        if tank.shieldHP > 0 {
            world.tanks[tankIndex].shieldHP = source.explosive ? 0 : max(0, tank.shieldHP - damage)
            events.append(.tankShieldHit(entityID: tank.entityID, ownerPlayerID: tank.ownerPlayerID,
                                         remaining: world.tanks[tankIndex].shieldHP,
                                         position: tank.positionSubunits))
        } else {
            world.tanks[tankIndex].armor -= damage
            if world.tanks[tankIndex].armor <= 0 {
                world.tanks[tankIndex].killedBy = KillAttribution(playerID: source.ownerPlayerID)
            }
            events.append(.tankDamaged(entityID: tank.entityID, ownerPlayerID: tank.ownerPlayerID,
                                       damage: damage, sourceWeaponID: source.weaponID,
                                       position: tank.positionSubunits))
        }
        if let owner = tank.ownerPlayerID { world.withPlayer(owner) { $0.hitStreak = 0 } }
        return true
    }

    /// One point off the base (§11.1); the shield and the difficulty's
    /// allied-damage flag deflect. `sourceTeam` nil = stage environment.
    @discardableResult
    static func applyBaseHit(_ world: inout WorldState, sourceTeam: Int?, weapons: WeaponRuleset,
                             events: inout [DomainEvent]) -> Bool {
        guard var base = world.base, base.durability > 0, base.shieldRemainingTicks == 0 else { return false }
        let allied = sourceTeam == base.teamID
        if allied && !weapons.alliedBaseDamage { return false }
        base.durability -= 1
        world.base = base
        events.append(.baseDamaged(damage: 1, remaining: base.durability, allied: allied))
        return true
    }

    // MARK: - Step 4: firing

    enum FireAttempt { case fired, cooldown, capFull }

    private static func processFire(
        _ world: inout WorldState, specialInput: [Int: Simulation.SpecialInput],
        aiFire: [Int: (normal: Bool, special: Bool)], weapons: WeaponRuleset,
        events: inout [DomainEvent]
    ) -> Set<Int> {
        var spawned = Set<Int>()
        guard let normalWeapon = weapons.weapon("normal") else { return spawned }
        for index in world.tanks.indices {
            let tank = world.tanks[index]
            guard isAlive(tank), tank.statusEffects["frozen"] == nil else { continue }
            if let owner = tank.ownerPlayerID {
                let input = specialInput[tank.entityID] ?? Simulation.SpecialInput(held: false, edge: false)
                let ammo = world.player(owner)?.specialAmmoByWeapon[tank.specialWeaponID, default: 0] ?? 0
                if let special = weapons.weapon(tank.specialWeaponID), special.fireChannel == .special, ammo >= 1 {
                    if input.held {
                        let result = attemptFire(&world, tankIndex: index, weapon: special, channel: .special,
                                                 spawned: &spawned, events: &events)
                        if result == .capFull, world.tanks[index].dryFireFeedbackTicks == 0 {
                            world.tanks[index].dryFireFeedbackTicks = weapons.dryFireFeedbackIntervalTicks
                            events.append(.dryFire(entityID: tank.entityID, ownerPlayerID: owner, weaponID: special.id))
                        }
                    }
                } else if input.edge {
                    // Depleted special: a press edge requests one normal round.
                    world.tanks[index].normalFireBufferTicks = weapons.normalFireBufferTicks
                }
                if world.tanks[index].normalFireBufferTicks > 0,
                   attemptFire(&world, tankIndex: index, weapon: normalWeapon, channel: .normal,
                               spawned: &spawned, events: &events) == .fired {
                    world.tanks[index].normalFireBufferTicks = 0
                }
            } else {
                guard tank.spawnProtectionTicks == 0, let press = aiFire[tank.entityID] else { continue }
                if press.normal {
                    attemptFire(&world, tankIndex: index, weapon: normalWeapon, channel: .normal,
                                spawned: &spawned, events: &events)
                }
                if press.special, let special = weapons.weapon(tank.specialWeaponID) {
                    attemptFire(&world, tankIndex: index, weapon: special, channel: .special,
                                spawned: &spawned, events: &events)
                }
            }
        }
        return spawned
    }

    /// A failed attempt spends nothing and starts no cooldown (§5.1).
    @discardableResult
    private static func attemptFire(
        _ world: inout WorldState, tankIndex: Int, weapon: WeaponDefinition, channel: FireChannel,
        spawned: inout Set<Int>, events: inout [DomainEvent]
    ) -> FireAttempt {
        var tank = world.tanks[tankIndex]
        guard tank.fireCooldowns[channel, default: 0] == 0 else { return .cooldown }
        guard tank.activeProjectileCounts[weapon.id, default: 0] < weapon.level(weapon.maxActive, tank.powerLevel)
        else { return .capFull }
        let half = SpatialUnits.standardTankFootprintSubunits / 2
        let center = tank.positionSubunits + Vec2i(x: half, y: half)
        let muzzle = center + tank.facing.vector * SpatialUnits.subunitsPerCell
        let id = world.claimEntityID()
        world.projectiles.append(ProjectileState(
            entityID: id, weaponID: weapon.id, ownerEntityID: tank.entityID,
            ownerPlayerID: tank.ownerPlayerID, teamID: tank.teamID, powerLevel: tank.powerLevel,
            positionSubunits: muzzle, direction: tank.facing,
            velocity60: 60 * weapon.initialSpeedMilliSubunitsPerSecond,
            lifetimeRemainingTicks: weapon.lifetimeTicks, launchOriginSubunits: center))
        spawned.insert(id)
        tank.fireCooldowns[channel] = weapon.level(weapon.cooldownTicks, tank.powerLevel)
        tank.activeProjectileCounts[weapon.id, default: 0] += 1
        world.tanks[tankIndex] = tank
        if channel == .special, let owner = tank.ownerPlayerID {
            world.withPlayer(owner) { $0.specialAmmoByWeapon[weapon.id, default: 0] -= 1 }
        }
        events.append(.weaponFired(entityID: tank.entityID, ownerPlayerID: tank.ownerPlayerID,
                                   weaponID: weapon.id, channel: channel,
                                   position: tank.positionSubunits, facing: tank.facing))
        return .fired
    }

    // MARK: - Step 5: the contact queue

    private struct Motion {
        let from: Vec2i
        let vector: Vec2i
        let distance: Int
        func position(at travelled: Int) -> Vec2i { from + vector * travelled }
        var velocity: Vec2i { vector * distance }
    }

    /// Exact rational time within the tick, compared by cross-multiplication.
    struct Fraction: Comparable {
        let num: Int
        let den: Int
        init(_ num: Int, _ den: Int) {
            precondition(den != 0)
            if den < 0 { self.num = -num; self.den = -den } else { self.num = num; self.den = den }
        }
        static let zero = Fraction(0, 1)
        static let one = Fraction(1, 1)
        static func < (a: Fraction, b: Fraction) -> Bool { a.num * b.den < b.num * a.den }
        static func == (a: Fraction, b: Fraction) -> Bool { a.num * b.den == b.num * a.den }
    }

    enum SweepHit: Equatable {
        case boundary
        case terrain(qx: Int, qy: Int)
        case base
        case tank(entityID: Int)
    }

    private struct WorldCandidate {
        let time: Fraction
        let order: Int
        let targetKey: Int
        /// Projectile center at the contact.
        let position: Vec2i
        let travelled: Int
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
        let secondaryKey: Int
        func isEarlier(than other: ContactKey) -> Bool {
            if time != other.time { return time < other.time }
            if order != other.order { return order < other.order }
            if primaryID != other.primaryID { return primaryID < other.primaryID }
            return secondaryKey < other.secondaryKey
        }
    }

    private static func resolveContacts(
        _ world: inout WorldState, motions: [Int: Motion], weapons: WeaponRuleset,
        destroyed: inout Set<Int>, events: inout [DomainEvent]
    ) {
        let half = weapons.projectileHalfExtentSubunits
        let ids = world.projectiles.map(\.entityID)

        var pairs: [PairCandidate] = []
        for (i, a) in world.projectiles.enumerated() {
            for b in world.projectiles[(i + 1)...] where a.teamID != b.teamID {
                guard let ma = motions[a.entityID], let mb = motions[b.entityID],
                      let t = firstOverlapTime(ma, mb, half: half) else { continue }
                pairs.append(PairCandidate(a: a.entityID, b: b.entityID, time: t))
            }
        }

        var candidates: [Int: WorldCandidate] = [:]
        for id in ids { candidates[id] = worldCandidate(world, projectileID: id, motions: motions, half: half) }

        while true {
            var bestKey: ContactKey?
            var bestWorld: Int?
            var bestPair: PairCandidate?
            for id in ids where !destroyed.contains(id) {
                guard let c = candidates[id] else { continue }
                let key = ContactKey(time: c.time, order: c.order, primaryID: id, secondaryKey: c.targetKey)
                if bestKey == nil || key.isEarlier(than: bestKey!) { bestKey = key; bestWorld = id; bestPair = nil }
            }
            for pair in pairs where !destroyed.contains(pair.a) && !destroyed.contains(pair.b) {
                let key = ContactKey(time: pair.time, order: 0, primaryID: pair.a, secondaryKey: pair.b)
                if bestKey == nil || key.isEarlier(than: bestKey!) { bestKey = key; bestWorld = nil; bestPair = pair }
            }
            guard bestKey != nil else { break }

            if let pair = bestPair {
                pairs.removeAll { $0 == pair }
                // §6.1 strength (owner 2026-09-15): normal and rapid shells are
                // light and never survive a meeting; AP and explosion shells
                // fly on through light shells and end, with their effect, on
                // another heavy one; a fire shell bursts into flame on any shell.
                func family(_ id: Int) -> WeaponFamily? {
                    world.projectiles.first { $0.entityID == id }.flatMap { weapons.weapon($0.weaponID)?.family }
                }
                func isLight(_ family: WeaponFamily?) -> Bool { family == .normal || family == .rapid }
                let families = (a: family(pair.a), b: family(pair.b))
                for (id, own, other) in [(pair.a, families.a, families.b), (pair.b, families.b, families.a)] {
                    let ends = own == .fire || isLight(own) || !isLight(other)
                    guard ends, let index = world.projectiles.firstIndex(where: { $0.entityID == id }),
                          let m = motions[id], let weapon = weapons.weapon(world.projectiles[index].weaponID) else { continue }
                    let meeting = m.position(at: m.distance * pair.time.num / pair.time.den)
                    world.projectiles[index].positionSubunits = meeting
                    terminate(&world, projectileID: id, weapon: weapon, impact: .projectile,
                              effect: isLight(own) ? .none : .open(center: meeting),
                              weapons: weapons, destroyed: &destroyed, events: &events)
                }
                revalidate(&world, ids: ids, motions: motions, half: half, destroyed: destroyed, candidates: &candidates)
                continue
            }
            guard let id = bestWorld, let candidate = candidates[id] else { break }
            if !targetStillExists(world, candidate.hit) {
                candidates[id] = worldCandidate(world, projectileID: id, motions: motions, half: half)
                continue
            }
            applyWorldContact(&world, projectileID: id, candidate: candidate, weapons: weapons,
                              destroyed: &destroyed, events: &events)
            candidates[id] = nil
            revalidate(&world, ids: ids, motions: motions, half: half, destroyed: destroyed, candidates: &candidates)
        }

        // Survivors commit their full displacement.
        for i in world.projectiles.indices where !destroyed.contains(world.projectiles[i].entityID) {
            if let m = motions[world.projectiles[i].entityID], m.distance > 0 {
                world.projectiles[i].positionSubunits = m.position(at: m.distance)
            }
        }
    }

    /// Re-derives the candidates whose target vanished (a destroyed quadrant,
    /// a killed tank). Removing obstacles only delays a hit, so untouched
    /// candidates stay valid.
    private static func revalidate(_ world: inout WorldState, ids: [Int], motions: [Int: Motion], half: Int,
                                   destroyed: Set<Int>, candidates: inout [Int: WorldCandidate]) {
        for other in ids where !destroyed.contains(other) {
            guard let c = candidates[other], !targetStillExists(world, c.hit) else { continue }
            candidates[other] = worldCandidate(world, projectileID: other, motions: motions, half: half)
        }
    }

    private static func targetStillExists(_ world: WorldState, _ hit: SweepHit) -> Bool {
        switch hit {
        case .terrain(let qx, let qy): return world.terrain.solidWallQuadrant(qx: qx, qy: qy)
        case .tank(let id): return world.tank(entityID: id).map(isAlive) ?? false
        case .base, .boundary: return true
        }
    }

    /// First overlap time in [0, 1) of two uniformly moving shell boxes.
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

    private static func worldCandidate(_ world: WorldState, projectileID: Int, motions: [Int: Motion],
                                       half: Int) -> WorldCandidate? {
        guard let motion = motions[projectileID],
              let projectile = world.projectiles.first(where: { $0.entityID == projectileID }) else { return nil }
        let vector = projectile.direction.vector
        if motion.distance == 0 {
            // Spawn tick: the launch segment from the shooter's centre finds a
            // muzzle buried in a wall or the base (time 0, §5.4); otherwise
            // only what already overlaps the muzzle box counts.
            if let origin = projectile.launchOriginSubunits,
               let found = earliestHit(world, projectile: projectile, from: origin, vector: vector,
                                       remaining: SpatialUnits.subunitsPerCell, half: half, includeTanks: false),
               found.t < SpatialUnits.subunitsPerCell {
                return WorldCandidate(time: .zero, order: found.order, targetKey: found.key,
                                      position: origin + vector * found.t, travelled: 0, hit: found.hit)
            }
            guard let found = earliestHit(world, projectile: projectile, from: motion.from, vector: vector,
                                          remaining: 0, half: half, includeTanks: true) else { return nil }
            return WorldCandidate(time: .zero, order: found.order, targetKey: found.key,
                                  position: motion.from, travelled: 0, hit: found.hit)
        }
        guard let found = earliestHit(world, projectile: projectile, from: motion.from, vector: vector,
                                      remaining: motion.distance, half: half, includeTanks: true) else { return nil }
        return WorldCandidate(time: Fraction(found.t, motion.distance), order: found.order, targetKey: found.key,
                              position: motion.position(at: found.t), travelled: found.t, hit: found.hit)
    }

    /// What a shell's effect needs about where it ended.
    enum TerminalEffect {
        case none
        /// Open ground: the blast centre / flame anchor is the shell centre.
        case open(center: Vec2i)
        /// A solid contact: the blast centre is the nearest point of the
        /// contact rectangle; flames stay on the incident side of `face`.
        case solid(center: Vec2i, rect: Rect, face: Int?, direction: Direction)
    }

    struct Rect { let minX: Int; let minY: Int; let maxX: Int; let maxY: Int }

    private static func applyWorldContact(
        _ world: inout WorldState, projectileID: Int, candidate: WorldCandidate, weapons: WeaponRuleset,
        destroyed: inout Set<Int>, events: inout [DomainEvent]
    ) {
        guard let index = world.projectiles.firstIndex(where: { $0.entityID == projectileID }),
              let weapon = weapons.weapon(world.projectiles[index].weaponID) else { return }
        world.projectiles[index].positionSubunits = candidate.position
        let projectile = world.projectiles[index]
        let quadrant = SpatialUnits.subunitsPerQuadrant
        let direction = projectile.direction

        switch candidate.hit {
        case .boundary:
            let clamped = Vec2i(x: max(0, min(world.arena.widthSubunits, candidate.position.x)),
                                y: max(0, min(world.arena.heightSubunits, candidate.position.y)))
            terminate(&world, projectileID: projectileID, weapon: weapon, impact: .boundary,
                      effect: .open(center: clamped), weapons: weapons, destroyed: &destroyed, events: &events)

        case .terrain(let qx, let qy):
            let kind = world.terrain[qx / 2, qy / 2].kind
            if weapon.level(weapon.stripDepthQuadrants, projectile.powerLevel) > 0 {
                applyStrip(&world, contact: (qx, qy), direction: direction, center: candidate.position,
                           power: projectile.powerLevel, weapon: weapon, owner: projectile.ownerPlayerID,
                           events: &events)
            }
            let rect = Rect(minX: qx * quadrant, minY: qy * quadrant, maxX: (qx + 1) * quadrant, maxY: (qy + 1) * quadrant)
            terminate(&world, projectileID: projectileID, weapon: weapon, impact: kind.isSteelFamily ? .steel : .brick,
                      effect: .solid(center: candidate.position, rect: rect, face: face(of: rect, facing: direction),
                                     direction: direction),
                      weapons: weapons, destroyed: &destroyed, events: &events)

        case .base:
            guard let base = world.base else { return }
            if weapon.family != .fire && weapon.family != .explosion {
                applyBaseHit(&world, sourceTeam: projectile.teamID, weapons: weapons, events: &events)
            }
            let p = base.topLeftSubunits
            let rect = Rect(minX: p.x, minY: p.y, maxX: p.x + base.sizeSubunits, maxY: p.y + base.sizeSubunits)
            terminate(&world, projectileID: projectileID, weapon: weapon, impact: .base,
                      effect: .solid(center: candidate.position, rect: rect, face: face(of: rect, facing: direction),
                                     direction: direction),
                      weapons: weapons, destroyed: &destroyed, events: &events)

        case .tank(let tankID):
            guard let tankIndex = world.tanks.firstIndex(where: { $0.entityID == tankID }) else { return }
            let target = world.tanks[tankIndex]
            let protected = isProtected(target)
            if !protected, weapon.family != .fire, weapon.family != .explosion {
                let landed = applyTankDamage(&world, tankIndex: tankIndex,
                                             damage: weapon.level(weapon.tankDamage, projectile.powerLevel),
                                             source: DamageSource(weaponID: weapon.id, ownerPlayerID: projectile.ownerPlayerID,
                                                                  explosive: false),
                                             events: &events)
                if landed { noteEnemyDamaged(&world, projectileID: projectileID, weapon: weapon, targetTeam: target.teamID) }
            }
            let p = target.positionSubunits
            let footprint = SpatialUnits.standardTankFootprintSubunits
            let rect = Rect(minX: p.x, minY: p.y, maxX: p.x + footprint, maxY: p.y + footprint)
            terminate(&world, projectileID: projectileID, weapon: weapon, impact: protected ? .deflected : .tank,
                      effect: .solid(center: candidate.position, rect: rect, face: nil, direction: direction),
                      weapons: weapons, destroyed: &destroyed, events: &events)
        }
    }

    /// The coordinate of the rectangle face that meets a shell travelling
    /// in `direction`.
    private static func face(of rect: Rect, facing direction: Direction) -> Int {
        switch direction {
        case .right: rect.minX
        case .left: rect.maxX
        case .down: rect.minY
        case .up: rect.maxY
        }
    }

    /// Ends a shell exactly once: its blast or flame (per `effect`), the
    /// destruction event, the owner's slot, and the MaxHits bookkeeping.
    static func terminate(
        _ world: inout WorldState, projectileID: Int, weapon: WeaponDefinition, impact: ImpactTarget,
        effect: TerminalEffect, weapons: WeaponRuleset, destroyed: inout Set<Int>, events: inout [DomainEvent]
    ) {
        guard !destroyed.contains(projectileID),
              let projectile = world.projectiles.first(where: { $0.entityID == projectileID }) else { return }
        switch (weapon.family, effect) {
        case (.explosion, .open(let center)):
            explode(&world, projectileID: projectileID, weapon: weapon, center: center, weapons: weapons, events: &events)
        case (.explosion, .solid(let shellCenter, let rect, _, _)):
            let center = Vec2i(x: max(rect.minX, min(shellCenter.x, rect.maxX)),
                               y: max(rect.minY, min(shellCenter.y, rect.maxY)))
            explode(&world, projectileID: projectileID, weapon: weapon, center: center, weapons: weapons, events: &events)
        case (.fire, .open(let center)):
            Fire.landFlame(&world, at: center, halfPlane: nil, projectile: projectile, weapons: weapons, events: &events)
        case (.fire, .solid(let center, _, let face, let direction)):
            Fire.landFlame(&world, at: center, halfPlane: face.map { (direction, $0) }, projectile: projectile,
                           weapons: weapons, events: &events)
        default:
            break
        }
        let final = world.projectiles.first(where: { $0.entityID == projectileID }) ?? projectile
        events.append(.projectileDestroyed(entityID: projectileID, weaponID: projectile.weaponID,
                                           position: projectile.positionSubunits, impact: impact))
        destroyed.insert(projectileID)
        for i in world.tanks.indices where world.tanks[i].entityID == projectile.ownerEntityID {
            let current = world.tanks[i].activeProjectileCounts[projectile.weaponID, default: 0]
            world.tanks[i].activeProjectileCounts[projectile.weaponID] = current > 1 ? current - 1 : nil
        }
        if let owner = projectile.ownerPlayerID, weapon.family != .fire, !final.damagedEnemy {
            world.withPlayer(owner) { $0.hitStreak = 0 } // a qualifying shell ended without a hit
        }
    }

    /// §13 MaxHits: the first time a player's shell damages an enemy.
    private static func noteEnemyDamaged(_ world: inout WorldState, projectileID: Int, weapon: WeaponDefinition,
                                         targetTeam: Int) {
        guard weapon.family != .fire, targetTeam != 1,
              let index = world.projectiles.firstIndex(where: { $0.entityID == projectileID }),
              !world.projectiles[index].damagedEnemy,
              let owner = world.projectiles[index].ownerPlayerID else { return }
        world.projectiles[index].damagedEnemy = true
        world.withPlayer(owner) {
            $0.hitStreak += 1
            $0.maxHits = max($0.maxHits, $0.hitStreak)
        }
    }

    // MARK: - Sweeps

    /// Earliest contact along a segment. Order: 1 = boundary/terrain/base,
    /// 2 = tank; the key breaks ties inside an order (boundary −1, base 0,
    /// terrain by quadrant (y, x), tank by entity id).
    private static func earliestHit(
        _ world: WorldState, projectile: ProjectileState, from: Vec2i, vector: Vec2i,
        remaining: Int, half: Int, includeTanks: Bool
    ) -> (t: Int, order: Int, key: Int, hit: SweepHit)? {
        var best: (t: Int, order: Int, key: Int, hit: SweepHit)?
        func consider(_ t: Int, _ order: Int, _ key: Int, _ hit: SweepHit) {
            if best == nil || (t, order, key) < (best!.t, best!.order, best!.key) { best = (t, order, key, hit) }
        }
        let arena = world.arena
        do {
            var t = remaining + 1
            if vector.x > 0 { t = arena.widthSubunits - from.x }
            if vector.x < 0 { t = from.x }
            if vector.y > 0 { t = arena.heightSubunits - from.y }
            if vector.y < 0 { t = from.y }
            if t <= remaining { consider(max(0, t), 1, -1, .boundary) }
        }
        if let (t, qx, qy) = firstSolidQuadrant(world.terrain, from: from, vector: vector, remaining: remaining, half: half) {
            consider(t, 1, 1 + qy * 4096 + qx, .terrain(qx: qx, qy: qy))
        }
        if let base = world.base {
            let p = base.topLeftSubunits
            if let t = boxEntry(from: from, vector: vector, remaining: remaining, half: half,
                                minX: p.x, minY: p.y, maxX: p.x + base.sizeSubunits, maxY: p.y + base.sizeSubunits) {
                consider(t, 1, 0, .base)
            }
        }
        if includeTanks {
            let footprint = SpatialUnits.standardTankFootprintSubunits
            for tank in world.tanks where tank.teamID != projectile.teamID && isAlive(tank) {
                let p = tank.positionSubunits
                if let t = boxEntry(from: from, vector: vector, remaining: remaining, half: half,
                                    minX: p.x, minY: p.y, maxX: p.x + footprint, maxY: p.y + footprint) {
                    consider(t, 2, tank.entityID, .tank(entityID: tank.entityID))
                }
            }
        }
        return best
    }

    /// Entry distance of the shell box into a target box, or nil.
    private static func boxEntry(
        from: Vec2i, vector: Vec2i, remaining: Int, half: Int,
        minX: Int, minY: Int, maxX: Int, maxY: Int
    ) -> Int? {
        let eMinX = minX - half, eMaxX = maxX + half
        let eMinY = minY - half, eMaxY = maxY + half
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

    /// First wall quadrant the shell's leading edge enters, walking quadrant
    /// boundaries analytically; simultaneous quadrants resolve by (y, x).
    static func firstSolidQuadrant(
        _ terrain: TerrainGrid, from: Vec2i, vector: Vec2i, remaining: Int, half: Int
    ) -> (t: Int, qx: Int, qy: Int)? {
        let quadrant = SpatialUnits.subunitsPerQuadrant
        for t in quadrantBoundarySteps(from: from, vector: vector, remaining: remaining, half: half) {
            let p = from + vector * t
            let leadX = vector.x > 0 ? p.x + half : p.x - half - 1
            let leadY = vector.y > 0 ? p.y + half : p.y - half - 1
            let (loX, hiX) = vector.x != 0 ? (leadX, leadX) : (p.x - half, p.x + half - 1)
            let (loY, hiY) = vector.y != 0 ? (leadY, leadY) : (p.y - half, p.y + half - 1)
            // At t = 0 the whole box counts: a muzzle box already inside a wall.
            let (scanLoX, scanHiX, scanLoY, scanHiY) = t == 0
                ? (p.x - half, p.x + half - 1, p.y - half, p.y + half - 1) : (loX, hiX, loY, hiY)
            var qy = floorDiv(scanLoY, quadrant)
            while qy <= floorDiv(scanHiY, quadrant) {
                var qx = floorDiv(scanLoX, quadrant)
                while qx <= floorDiv(scanHiX, quadrant) {
                    if terrain.solidWallQuadrant(qx: qx, qy: qy) { return (t, qx, qy) }
                    qx += 1
                }
                qy += 1
            }
        }
        return nil
    }

    private static func quadrantBoundarySteps(from: Vec2i, vector: Vec2i, remaining: Int, half: Int) -> [Int] {
        let quadrant = SpatialUnits.subunitsPerQuadrant
        var steps = [0]
        let leading = vector.x != 0
            ? (vector.x > 0 ? from.x + half : from.x - half)
            : (vector.y > 0 ? from.y + half : from.y - half)
        let positive = (vector.x + vector.y) > 0
        let offset = ((leading % quadrant) + quadrant) % quadrant
        var next = positive ? quadrant - offset : (offset == 0 ? quadrant : offset)
        if next == 0 { next = quadrant }
        var t = next
        while t <= remaining {
            steps.append(t)
            t += quadrant
        }
        return steps
    }

    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        a >= 0 ? a / b : -((-a + b - 1) / b)
    }

    // MARK: - Wall damage

    /// One round against a single wall quadrant: red brick and grey steel
    /// fall, white brick cracks first, white steel never yields. An emptied
    /// cell reveals its surface.
    @discardableResult
    static func damageQuadrant(_ world: inout WorldState, cellX: Int, cellY: Int, bit: Int) -> WallDamage {
        var cell = world.terrain[cellX, cellY]
        let flag = 1 << bit
        guard cell.kind.isWall, cell.quadrantMask & flag != 0, !cell.kind.isIndestructibleWall else { return .none }
        if cell.kind.roundsPerQuadrant > 1, cell.crackMask & flag == 0 {
            cell.crackMask |= flag
            world.terrain[cellX, cellY] = cell
            return .cracked
        }
        cell.quadrantMask &= ~flag
        cell.crackMask &= ~flag
        if cell.quadrantMask == 0 { cell = cell.revealedSurface }
        world.terrain[cellX, cellY] = cell
        return .removed
    }

    /// The §3.2 damage strip: four quadrant columns centred on the nearest
    /// half-cell boundary across the flight, reaching in from the contact
    /// face by the weapon's depth. Each column takes its material from its
    /// first standing quadrant — which also picks the depth (AP cuts brick
    /// deeper than steel, R5.5) — damages it only when the weapon can, and passes
    /// only through that same material; a different material or the base
    /// stops the column. Empty quadrants spend depth.
    private static func applyStrip(
        _ world: inout WorldState, contact: (qx: Int, qy: Int), direction: Direction, center: Vec2i,
        power: Int, weapon: WeaponDefinition, owner: PlayerID?, events: inout [DomainEvent]
    ) {
        let depth = max(weapon.stripDepth(for: .brick, power: power), weapon.level(weapon.stripDepthQuadrants, power))
        let quadrant = SpatialUnits.subunitsPerQuadrant
        let horizontal = direction.vector.x != 0
        let cross = horizontal ? center.y : center.x
        let boundaryIndex = (max(0, cross) + quadrant / 2 - 1) / quadrant // nearest boundary, ties to the smaller
        let rowStart = horizontal ? contact.qx : contact.qy
        let rowStep = direction.vector.x + direction.vector.y
        var changed = Set<Int>()
        for column in (boundaryIndex - 2)...(boundaryIndex + 1) {
            var material: TerrainKind?
            for step in 0..<depth {
                let row = rowStart + rowStep * step
                let (qx, qy) = horizontal ? (row, column) : (column, row)
                if quadrantTouchesBase(world, qx: qx, qy: qy) { break }
                guard world.terrain.solidWallQuadrant(qx: qx, qy: qy) else { continue }
                let kind = world.terrain[qx / 2, qy / 2].kind
                if let material, material != kind { break }
                // The column's depth follows its first material (empty
                // quadrants in front of it count).
                if step >= weapon.stripDepth(for: kind, power: power) { break }
                material = kind
                guard weapon.damages(kind) else { break }
                let cellX = qx / 2, cellY = qy / 2
                if damageQuadrant(&world, cellX: cellX, cellY: cellY, bit: (qy % 2) * 2 + (qx % 2)) != .none {
                    changed.insert(cellY * world.arena.cellsWide + cellX)
                    // §10.5: a brick cell the PLAYER's round has just emptied
                    // is a drop candidate for step 7 — unless it belongs to the
                    // fort (nobody is paid for shooting their own walls) or
                    // covers a hidden pickup (which reveals on its own).
                    if kind.isBrickFamily, owner != nil, !world.terrain[cellX, cellY].kind.isWall {
                        noteClearedBrick(&world, Vec2i(x: cellX, y: cellY))
                    }
                }
            }
        }
        emitTerrainChanges(&world, changed, events: &events)
    }

    private static func noteClearedBrick(_ world: inout WorldState, _ cell: Vec2i) {
        guard var stage = world.stage else { return }
        if stage.fortTemplate.contains(cell) { return }
        if stage.hiddenPickups.contains(where: { cell.x >= $0.cell.x && cell.x <= $0.cell.x + 1
                                                && cell.y >= $0.cell.y && cell.y <= $0.cell.y + 1 }) { return }
        stage.clearedBrickCells.append(cell)
        world.stage = stage
    }

    static func emitTerrainChanges(_ world: inout WorldState, _ changed: Set<Int>, events: inout [DomainEvent]) {
        for key in changed.sorted() {
            let cx = key % world.arena.cellsWide, cy = key / world.arena.cellsWide
            events.append(.terrainChanged(cellX: cx, cellY: cy, quadrantMask: world.terrain[cx, cy].quadrantMask))
        }
    }

    private static func quadrantTouchesBase(_ world: WorldState, qx: Int, qy: Int) -> Bool {
        guard let base = world.base else { return false }
        let quadrant = SpatialUnits.subunitsPerQuadrant
        let p = base.topLeftSubunits
        let minX = qx * quadrant, minY = qy * quadrant
        return minX < p.x + base.sizeSubunits && minX + quadrant > p.x
            && minY < p.y + base.sizeSubunits && minY + quadrant > p.y
    }

    // MARK: - Explosions (§6.4)

    private static func explode(_ world: inout WorldState, projectileID: Int, weapon: WeaponDefinition,
                                center: Vec2i, weapons: WeaponRuleset, events: inout [DomainEvent]) {
        guard let projectile = world.projectiles.first(where: { $0.entityID == projectileID }) else { return }
        let radius = weapon.level(weapon.explosionRadiusSubunits, projectile.powerLevel)
        guard radius > 0 else { return }
        events.append(.explosion(position: center, radiusSubunits: radius))
        let snapshot = world.terrain
        let quadrant = SpatialUnits.subunitsPerQuadrant
        let footprint = SpatialUnits.standardTankFootprintSubunits

        func nearest(_ r: Rect) -> Vec2i {
            Vec2i(x: max(r.minX, min(center.x, r.maxX)), y: max(r.minY, min(center.y, r.maxY)))
        }
        func reaches(_ r: Rect, excluding target: (Int, Int)? = nil) -> Bool {
            let n = nearest(r)
            let dx = n.x - center.x, dy = n.y - center.y
            guard dx * dx + dy * dy <= radius * radius else { return false }
            return !occluded(snapshot, from: center, to: n, excluding: target)
        }

        var tankTargets: [Int] = []
        for tank in world.tanks where tank.teamID != projectile.teamID && isAlive(tank) {
            let p = tank.positionSubunits
            if reaches(Rect(minX: p.x, minY: p.y, maxX: p.x + footprint, maxY: p.y + footprint)) {
                tankTargets.append(tank.entityID)
            }
        }
        var baseHit = false
        if let base = world.base {
            let p = base.topLeftSubunits
            baseHit = reaches(Rect(minX: p.x, minY: p.y, maxX: p.x + base.sizeSubunits, maxY: p.y + base.sizeSubunits))
        }
        var brickTargets: [(Int, Int)] = []
        // A quadrant whose far edge sits exactly at the radius still qualifies
        // (distance ≤ radius), hence the extra row/column on the low side.
        let loQX = max(0, floorDiv(center.x - radius, quadrant) - 1), hiQX = min(world.arena.cellsWide * 2 - 1, (center.x + radius) / quadrant)
        let loQY = max(0, floorDiv(center.y - radius, quadrant) - 1), hiQY = min(world.arena.cellsHigh * 2 - 1, (center.y + radius) / quadrant)
        if loQX <= hiQX && loQY <= hiQY {
            for qy in loQY...hiQY {
                for qx in loQX...hiQX where snapshot.solidWallQuadrant(qx: qx, qy: qy)
                    && snapshot[qx / 2, qy / 2].kind.isBrickFamily {
                    let r = Rect(minX: qx * quadrant, minY: qy * quadrant, maxX: (qx + 1) * quadrant, maxY: (qy + 1) * quadrant)
                    if reaches(r, excluding: (qx, qy)) { brickTargets.append((qx, qy)) }
                }
            }
        }

        let damage = weapon.level(weapon.tankDamage, projectile.powerLevel)
        let source = DamageSource(weaponID: weapon.id, ownerPlayerID: projectile.ownerPlayerID, explosive: true)
        for id in tankTargets {
            guard let index = world.tanks.firstIndex(where: { $0.entityID == id }) else { continue }
            let team = world.tanks[index].teamID
            if applyTankDamage(&world, tankIndex: index, damage: damage, source: source, events: &events) {
                noteEnemyDamaged(&world, projectileID: projectileID, weapon: weapon, targetTeam: team)
            }
        }
        var changed = Set<Int>()
        for (qx, qy) in brickTargets
        where damageQuadrant(&world, cellX: qx / 2, cellY: qy / 2, bit: (qy % 2) * 2 + (qx % 2)) != .none {
            changed.insert((qy / 2) * world.arena.cellsWide + qx / 2)
        }
        emitTerrainChanges(&world, changed, events: &events)
        if baseHit { applyBaseHit(&world, sourceTeam: projectile.teamID, weapons: weapons, events: &events) }
    }

    /// Whether the segment from `a` to `b` is blocked by a standing wall
    /// quadrant of `terrain` other than `target`: it crosses a quadrant's
    /// interior, or runs a positive length along an edge shared by two
    /// standing quadrants. Grazing one wall's outer edge or touching a
    /// corner does not block.
    static func occluded(_ terrain: TerrainGrid, from a: Vec2i, to b: Vec2i, excluding target: (Int, Int)?) -> Bool {
        let q = SpatialUnits.subunitsPerQuadrant
        func solid(_ qx: Int, _ qy: Int) -> Bool {
            if let target, target.0 == qx, target.1 == qy { return false }
            return terrain.solidWallQuadrant(qx: qx, qy: qy)
        }
        let minX = min(a.x, b.x), maxX = max(a.x, b.x), minY = min(a.y, b.y), maxY = max(a.y, b.y)
        for qy in (floorDiv(minY, q) - 1)...(floorDiv(maxY, q)) {
            for qx in (floorDiv(minX, q) - 1)...(floorDiv(maxX, q)) where solid(qx, qy) {
                if segmentCrossesOpenRect(a, b, Rect(minX: qx * q, minY: qy * q, maxX: (qx + 1) * q, maxY: (qy + 1) * q)) {
                    return true
                }
            }
        }
        if a.x == b.x, a.y != b.y, a.x % q == 0 {
            let right = a.x / q
            var row = floorDiv(minY, q)
            while row * q < maxY {
                if (row + 1) * q > minY, solid(right - 1, row), solid(right, row) { return true }
                row += 1
            }
        }
        if a.y == b.y, a.x != b.x, a.y % q == 0 {
            let lower = a.y / q
            var column = floorDiv(minX, q)
            while column * q < maxX {
                if (column + 1) * q > minX, solid(column, lower - 1), solid(column, lower) { return true }
                column += 1
            }
        }
        return false
    }

    /// Whether the open segment (a, b) meets the open interior of `r`.
    private static func segmentCrossesOpenRect(_ a: Vec2i, _ b: Vec2i, _ r: Rect) -> Bool {
        var lo = Fraction.zero, hi = Fraction.one
        func clip(_ p0: Int, _ d: Int, _ low: Int, _ high: Int) -> Bool {
            if d == 0 { return p0 > low && p0 < high }
            let t1 = Fraction(low - p0, d), t2 = Fraction(high - p0, d)
            let enter = min(t1, t2), exit = max(t1, t2)
            if lo < enter { lo = enter }
            if exit < hi { hi = exit }
            return true
        }
        guard clip(a.x, b.x - a.x, r.minX, r.maxX), clip(a.y, b.y - a.y, r.minY, r.maxY) else { return false }
        return lo < hi
    }
}
