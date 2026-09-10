/// Development-fixture invariants (§18.2), checked every tick in tests and
/// debug sessions, and the admission check for any decoded world (replay,
/// suspended session): returns human-readable violations; empty means
/// healthy. Every decoded value is range-checked against its documented
/// domain before the arithmetic that depends on it — including the
/// counters the simulation itself increments (tick, entity ids, spawn
/// cursors, scores), which are admitted only with headroom. Signed bounds
/// are compared directly (no `abs`, which traps on Int.min). The maintained
/// boundary tests (`ReplayRecordingTests`) list the fields covered.
public enum WorldInvariants {
    /// Documented domains for decoded state.
    public static let maxArenaCells = 1024
    /// Counters the simulation increments: admitted only far below Int.max.
    public static let maxCounter = 1 << 50
    /// State timers may legitimately be far longer than tuning timers (a
    /// stage that never spawns uses a huge start delay); ~46 hours of ticks.
    public static let maxTicks = 10_000_000
    public static let maxArmor = 10_000
    public static let maxLives = 1_000
    public static let maxScore = 1 << 50
    public static let maxAmmo = 1_000_000
    public static let maxCount = 1_000_000
    public static let maxRadiusSubunits = 65_536

    public static func violations(in world: WorldState) -> [String] {
        var issues: [String] = []
        // Structural safety first: bounded arena dimensions (so their
        // product and the subunit extents are safe), storage that matches
        // them, and positions inside the arena — nothing below runs on a
        // world that fails these.
        let arena = world.arena
        if arena.cellsWide < 1 || arena.cellsWide > maxArenaCells
            || arena.cellsHigh < 1 || arena.cellsHigh > maxArenaCells {
            return ["arena \(arena.cellsWide)×\(arena.cellsHigh) outside 1…\(maxArenaCells)"]
        }
        if world.terrain.cells.count != arena.cellsWide * arena.cellsHigh {
            return ["terrain storage (\(world.terrain.cells.count) cells) does not match the arena \(arena.cellsWide)×\(arena.cellsHigh)"]
        }
        let width = arena.widthSubunits, height = arena.heightSubunits
        let footprint = SpatialUnits.standardTankFootprintSubunits
        func inArena(_ p: Vec2i) -> Bool { p.x >= 0 && p.x <= width && p.y >= 0 && p.y <= height }
        func ticks(_ value: Int, _ what: String) {
            if value < 0 || value > maxTicks { issues.append("\(what) \(value) outside 0…\(maxTicks)") }
        }
        if world.tick < 0 || world.tick > maxCounter { issues.append("tick \(world.tick) out of domain") }
        if world.nextEntityID < 1 || world.nextEntityID > maxCounter { issues.append("nextEntityID out of domain") }
        // Every entity id — live entities AND the ids they reference — lies
        // in the claimed domain 1..<nextEntityID before any arithmetic on
        // it (AI cadences multiply ids; a decoded Int.min/2 trapped). A
        // referenced owner need not be alive: ordnance outlives its emitter.
        func entityID(_ id: Int, _ what: String) {
            if id < 1 || id >= world.nextEntityID { issues.append("\(what) entity id \(id) outside 1..<nextEntityID") }
        }
        /// An owner reference: the same domain, or the documented "no
        /// owner" sentinel −1 (stage-authored mines, ownerless ordnance).
        func ownerID(_ id: Int, _ what: String) {
            if id != -1 { entityID(id, what) }
        }

        var seenEntityIDs = Set<Int>()
        var previousEntityID = Int.min
        for tank in world.tanks {
            let id = tank.entityID
            if !seenEntityIDs.insert(id).inserted { issues.append("duplicate entity id \(id)") }
            if id <= previousEntityID { issues.append("tanks not in ascending entity order at \(id)") }
            previousEntityID = id
            entityID(id, "tank")

            let p = tank.positionSubunits
            // Compared against bounded extents: no `p.x + footprint` on a
            // decoded coordinate.
            if p.x < 0 || p.y < 0 || p.x > width - footprint || p.y > height - footprint {
                issues.append("tank \(id) outside arena bounds at (\(p.x),\(p.y))")
            }
            if tank.maxArmor < 1 || tank.maxArmor > maxArmor { issues.append("tank \(id) max armor \(tank.maxArmor) out of domain") }
            if tank.shieldHP > maxArmor { issues.append("tank \(id) shield out of domain") }
            ticks(tank.bufferedDirectionRemainingTicks, "tank \(id) buffer ticks")
            ticks(tank.spawnProtectionTicks, "tank \(id) spawn protection")
            if tank.slideMomentumSubunits < -(1 << 20) || tank.slideMomentumSubunits > 1 << 20 {
                issues.append("tank \(id) slide momentum out of domain")
            }
            for (_, remaining) in tank.fireCooldowns where remaining < 0 || remaining > maxTicks {
                issues.append("tank \(id) fire cooldown out of domain")
            }
            for (status, remaining) in tank.statusEffects where remaining > maxTicks {
                issues.append("tank \(id) status \(status) timer out of domain")
            }
            for (weapon, count) in tank.activeProjectileCounts where count > maxCount {
                issues.append("tank \(id) \(weapon) count out of domain")
            }
            if let owner = tank.ownerPlayerID, world.player(owner) == nil {
                issues.append("tank \(id) references missing player \(owner.rawValue)")
            }
            if tank.shieldHP < 0 { issues.append("tank \(id) negative shield") }
            if tank.armor < 0 || tank.armor > tank.maxArmor {
                issues.append("tank \(id) armor \(tank.armor) outside 0...\(tank.maxArmor)")
            }
            let speedRange = tank.ownerPlayerID != nil ? 0...3 : -4...4 // §15.3
            if !speedRange.contains(tank.speedLevel) { issues.append("tank \(id) speed level \(tank.speedLevel)") }
            if !(0...3).contains(tank.powerLevel) { issues.append("tank \(id) power level \(tank.powerLevel)") }
            if tank.bufferedDirectionRemainingTicks < 0 {
                issues.append("tank \(id) negative buffer ticks")
            }
            if tank.bufferedDirection == nil && tank.bufferedDirectionRemainingTicks != 0 {
                issues.append("tank \(id) buffer ticks without buffered direction")
            }
            if tank.movementAccumulator < 0
                || tank.movementAccumulator >= MovementRuleset.accumulatorUnitsPerSubunit {
                issues.append("tank \(id) accumulator out of range: \(tank.movementAccumulator)")
            }
            if tank.spawnProtectionTicks < 0 { issues.append("tank \(id) negative spawn protection") }
            for (status, remaining) in tank.statusEffects where remaining <= 0 {
                issues.append("tank \(id) status \(status) with non-positive timer")
            }
            for (weapon, ammo) in tank.activeProjectileCounts where ammo < 0 {
                issues.append("tank \(id) negative projectile count for \(weapon)")
            }
        }

        var previousPlayerID = Int.min
        for player in world.players {
            if player.playerID.rawValue <= previousPlayerID {
                issues.append("players not in ascending id order at \(player.playerID.rawValue)")
            }
            previousPlayerID = player.playerID.rawValue
            if player.lives < 0 || player.lives > maxLives { issues.append("player \(player.playerID.rawValue) lives out of domain") }
            if player.score < 0 || player.score > maxScore { issues.append("player \(player.playerID.rawValue) score out of domain") }
            ticks(player.respawnCountdownTicks, "player \(player.playerID.rawValue) respawn countdown")
            if !(0...3).contains(player.retainedSpeedLevel) || !(0...3).contains(player.retainedPowerLevel) {
                issues.append("player \(player.playerID.rawValue) retained levels out of domain")
            }
            if let tankID = player.tankEntityID, !seenEntityIDs.contains(tankID) {
                issues.append("player \(player.playerID.rawValue) references missing tank \(tankID)")
            }
            for (weapon, ammo) in player.specialAmmoByWeapon where ammo < 0 || ammo > maxAmmo {
                issues.append("player \(player.playerID.rawValue) ammo for \(weapon) out of domain")
            }
        }

        // Combat entities (§18.2: active-projectile counts match entities
        // EXACTLY; no destroyed entity remains addressable).
        var liveByOwner: [Int: [String: Int]] = [:]
        var previousProjectileID = Int.min
        for p in world.projectiles {
            if !seenEntityIDs.insert(p.entityID).inserted { issues.append("duplicate entity id \(p.entityID)") }
            if p.entityID <= previousProjectileID { issues.append("projectiles out of order at \(p.entityID)") }
            previousProjectileID = p.entityID
            entityID(p.entityID, "projectile")
            ownerID(p.ownerEntityID, "projectile \(p.entityID) owner")
            if p.speedSubunitsPerTick < 0 || p.speedSubunitsPerTick > SpatialUnits.maxPerTickDisplacementSubunits {
                issues.append("projectile \(p.entityID) speed outside the per-tick displacement cap")
            }
            if !inArena(p.positionSubunits) { issues.append("projectile \(p.entityID) outside the arena") }
            ticks(p.lifetimeRemainingTicks, "projectile \(p.entityID) lifetime")
            if p.penetrationRemaining < 0 || p.penetrationRemaining > maxCount
                || p.durability < 0 || p.durability > maxCount || !(0...3).contains(p.powerLevel) {
                issues.append("projectile \(p.entityID) fields out of domain")
            }
            if p.hitTankIDs.count > maxCount { issues.append("projectile \(p.entityID) hit list out of domain") }
            if p.hitTankIDs != p.hitTankIDs.sorted() {
                issues.append("projectile \(p.entityID) hit list not ascending")
            }
            for hit in p.hitTankIDs.prefix(64) { entityID(hit, "projectile \(p.entityID) hit") }
            liveByOwner[p.ownerEntityID, default: [:]][p.weaponID, default: 0] += 1
        }
        for m in world.mines {
            if !seenEntityIDs.insert(m.entityID).inserted { issues.append("duplicate entity id \(m.entityID)") }
            entityID(m.entityID, "mine")
            ownerID(m.ownerEntityID, "mine \(m.entityID) owner")
            if !(0...3).contains(m.level) { issues.append("mine \(m.entityID) level \(m.level)") }
            if !inArena(m.positionSubunits) { issues.append("mine \(m.entityID) outside the arena") }
            ticks(m.phaseTicksRemaining, "mine \(m.entityID) phase ticks")
            if m.triggerRadiusSubunits < 0 || m.triggerRadiusSubunits > maxRadiusSubunits {
                issues.append("mine \(m.entityID) trigger radius out of domain")
            }
            liveByOwner[m.ownerEntityID, default: [:]]["mine", default: 0] += 1
        }
        for h in world.fireHazards {
            if !seenEntityIDs.insert(h.entityID).inserted { issues.append("duplicate entity id \(h.entityID)") }
            entityID(h.entityID, "fire hazard")
            ownerID(h.ownerEntityID, "fire hazard \(h.entityID) owner")
            if !inArena(h.positionSubunits) { issues.append("fire hazard \(h.entityID) outside the arena") }
            if h.lifetimeRemainingTicks > maxTicks || h.lifetimeRemainingTicks < -1 {
                issues.append("fire hazard \(h.entityID) lifetime out of domain")
            }
            if h.damagePerTouch < 0 || h.damagePerTouch > 99 { issues.append("fire hazard \(h.entityID) damage out of domain") }
            liveByOwner[h.ownerEntityID, default: [:]]["fire", default: 0] += 1
        }
        // Every live tank's stored counts equal its live entities over the
        // union of stored keys and live weapon IDs (missing key = 0).
        // Entities whose owner already died have no tank to reconcile.
        for tank in world.tanks {
            let live = liveByOwner[tank.entityID] ?? [:]
            let keys = Set(tank.activeProjectileCounts.keys).union(live.keys).sorted()
            for weapon in keys {
                let stored = tank.activeProjectileCounts[weapon] ?? 0
                let actual = live[weapon] ?? 0
                if stored != actual {
                    issues.append("tank \(tank.entityID) \(weapon) count \(stored) != live entities \(actual)")
                }
            }
        }
        if let base = world.base {
            if base.maxDurability < 1 || base.maxDurability > 1000 { issues.append("base max durability out of domain") }
            if base.durability < 0 || base.durability > base.maxDurability {
                issues.append("base durability \(base.durability) outside 0...\(base.maxDurability)")
            }
            let b = base.topLeftSubunits
            if b.x < 0 || b.y < 0 || b.x > width - base.sizeSubunits || b.y > height - base.sizeSubunits {
                issues.append("base outside the arena")
            }
            ticks(base.shieldRemainingTicks, "base shield")
            ticks(base.burnCooldownTicks, "base burn cooldown")
            if base.fortRingRestore.count > 12 { issues.append("fort ring record out of domain") }
        }
        for p in world.pickups {
            if !seenEntityIDs.insert(p.entityID).inserted { issues.append("duplicate entity id \(p.entityID)") }
            entityID(p.entityID, "pickup")
            if !inArena(p.positionSubunits) { issues.append("pickup \(p.entityID) outside the arena") }
            if p.lifetimeRemainingTicks > maxTicks || p.lifetimeRemainingTicks < -1 { issues.append("pickup \(p.entityID) lifetime out of domain") }
            ticks(p.graceTicksRemaining, "pickup \(p.entityID) grace")
        }
        for t in world.spawnTelegraphs {
            if !seenEntityIDs.insert(t.entityID).inserted { issues.append("duplicate entity id \(t.entityID)") }
            entityID(t.entityID, "telegraph")
            if !inArena(t.positionSubunits) { issues.append("telegraph \(t.entityID) outside the arena") }
            if t.ticksRemaining > maxTicks || t.ticksRemaining < -1 || t.deferTicks < 0 || t.deferTicks > maxTicks {
                issues.append("telegraph \(t.entityID) timers out of domain")
            }
            // Used as an index (after +1 % count) by spawn relocation.
            if t.spawnPointIndex < 0 || t.spawnPointIndex >= max(1, world.stage?.spawnPointsCells.count ?? 1) {
                issues.append("telegraph \(t.entityID) spawn point index out of range")
            }
        }
        if let stage = world.stage {
            if stage.maxAliveEnemies < 1 || stage.maxAliveEnemies > maxCount { issues.append("max_alive_enemies out of domain") }
            ticks(stage.enemyStartDelayTicks, "enemy start delay")
            ticks(stage.telegraphTicks, "telegraph ticks")
            if stage.spawnPointsCells.isEmpty { issues.append("stage has no spawn points") }
            for c in stage.spawnPointsCells + [stage.playerRespawnCell] + stage.hiddenPickups.map(\.cell)
            where c.x < 0 || c.y < 0 || c.x >= arena.cellsWide || c.y >= arena.cellsHigh {
                issues.append("stage cell (\(c.x),\(c.y)) outside the arena")
            }
            // Incremented once per scheduled enemy; admitted with headroom.
            if stage.nextSpawnPointIndex < 0 || stage.nextSpawnPointIndex > maxCount {
                issues.append("next spawn point index out of domain")
            }
            if stage.spawnQueue.count > maxCount { issues.append("spawn queue out of domain") }
            if stage.dropChancePercent < 0 || stage.dropChancePercent > 100 { issues.append("drop chance out of domain") }
            if !stage.carriedPickupQueue.isEmpty && stage.carriedPickupQueue.count != stage.spawnQueue.count {
                issues.append("carried pickup queue does not pair with the spawn queue")
            }
            // §18.2: remaining + alive + spawning stays within the expected
            // finite total (equality is checked per stage in fixture tests).
            let alive = world.tanks.filter { $0.teamID != 1 }.count
            if alive + world.spawnTelegraphs.count > stage.maxAliveEnemies {
                issues.append("alive+spawning exceeds max_alive_enemies")
            }
        }

        for (index, cell) in world.terrain.cells.enumerated() {
            if cell.quadrantMask < 0 || cell.quadrantMask > 0b1111 {
                issues.append("terrain cell \(index) invalid quadrant mask \(cell.quadrantMask)")
                break // one report is enough; the grid is uniform storage
            }
        }
        return issues
    }
}
