/// FNV-1a 64-bit over a canonical field walk of the world. Dictionary keys
/// are sorted before hashing — Swift dictionary order is never treated as
/// deterministic (§14.3). Periodic checksums are required in development,
/// test, and golden-replay configurations (ADR-0003).
public struct StateChecksum {
    private var hash: UInt64 = 0xCBF2_9CE4_8422_2325

    public init() {}

    public mutating func mix(_ value: Int) { mix(UInt64(bitPattern: Int64(value))) }

    public mutating func mix(_ value: UInt64) {
        var v = value
        for _ in 0..<8 {
            hash = (hash ^ (v & 0xFF)) &* 0x0000_0100_0000_01B3
            v >>= 8
        }
    }

    public mutating func mix(_ value: String) {
        for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        mix(UInt64(0xFF)) // terminator so ("a","b") != ("ab","")
    }

    public mutating func mix(_ value: Bool) { mix(value ? 1 : 0) }
    public mutating func mix(_ value: Int?) { mix(value ?? -1) }

    public var value: UInt64 { hash }
}

extension WorldState {
    /// Canonical checksum of the complete authoritative state.
    public func checksum() -> UInt64 {
        var c = StateChecksum()
        c.mix(tick)
        c.mix(arena.cellsWide)
        c.mix(arena.cellsHigh)
        for cell in terrain.cells {
            c.mix(cell.kind.rawValue)
            c.mix(cell.quadrantMask)
        }
        for p in players { // already sorted by playerID
            c.mix(p.playerID.rawValue)
            c.mix(p.active)
            c.mix(p.lives)
            c.mix(p.score)
            c.mix(p.tankEntityID)
            c.mix(p.lifeState.rawValue)
            for (k, v) in p.specialAmmoByWeapon.sorted(by: { $0.key < $1.key }) {
                c.mix(k); c.mix(v)
            }
            c.mix(p.respawnCountdownTicks)
            c.mix(p.retainedSpeedLevel); c.mix(p.retainedPowerLevel)
            c.mix(p.retainedEquipmentID ?? ""); c.mix(p.retainedSpecialWeaponID)
        }
        for t in tanks { // already sorted by entityID
            c.mix(t.entityID)
            c.mix(t.teamID)
            c.mix(t.ownerPlayerID?.rawValue)
            c.mix(t.archetypeID)
            c.mix(t.positionSubunits.x)
            c.mix(t.positionSubunits.y)
            c.mix(t.facing.rawValue)
            c.mix(t.movementIntent?.rawValue)
            c.mix(t.bufferedDirection?.rawValue)
            c.mix(t.bufferedDirectionRemainingTicks)
            c.mix(t.slideDirection?.rawValue)
            c.mix(t.slideMomentumSubunits)
            c.mix(t.movementAccumulator)
            c.mix(t.armor)
            c.mix(t.maxArmor)
            c.mix(t.speedLevel)
            c.mix(t.powerLevel)
            c.mix(t.specialWeaponID)
            c.mix(t.equipmentID ?? "")
            for (k, v) in t.statusEffects.sorted(by: { $0.key < $1.key }) { c.mix(k); c.mix(v) }
            for (k, v) in t.fireCooldowns.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                c.mix(k.rawValue); c.mix(v)
            }
            for (k, v) in t.activeProjectileCounts.sorted(by: { $0.key < $1.key }) { c.mix(k); c.mix(v) }
            c.mix(t.spawnProtectionTicks)
        }
        c.mix(projectiles.count)
        for p in projectiles { // sorted by entityID
            c.mix(p.entityID); c.mix(p.weaponID); c.mix(p.ownerEntityID)
            c.mix(p.ownerPlayerID?.rawValue); c.mix(p.teamID); c.mix(p.powerLevel)
            c.mix(p.positionSubunits.x); c.mix(p.positionSubunits.y)
            c.mix(p.direction.rawValue); c.mix(p.speedSubunitsPerTick)
            c.mix(p.lifetimeRemainingTicks); c.mix(p.penetrationRemaining); c.mix(p.durability)
        }
        c.mix(mines.count)
        for m in mines {
            c.mix(m.entityID); c.mix(m.level); c.mix(m.ownerEntityID)
            c.mix(m.ownerPlayerID?.rawValue); c.mix(m.teamID)
            c.mix(m.positionSubunits.x); c.mix(m.positionSubunits.y)
            c.mix(m.phase.rawValue); c.mix(m.phaseTicksRemaining)
            c.mix(m.triggerRadiusSubunits); c.mix(m.onWater)
        }
        c.mix(fireHazards.count)
        for h in fireHazards {
            c.mix(h.entityID); c.mix(h.ownerPlayerID?.rawValue); c.mix(h.teamID)
            c.mix(h.filter.rawValue)
            c.mix(h.positionSubunits.x); c.mix(h.positionSubunits.y)
            c.mix(h.lifetimeRemainingTicks); c.mix(h.damagePerTouch)
        }
        if let base {
            c.mix(base.teamID)
            c.mix(base.topLeftSubunits.x); c.mix(base.topLeftSubunits.y)
            c.mix(base.durability); c.mix(base.maxDurability); c.mix(base.shieldRemainingTicks)
        } else {
            c.mix(-1)
        }
        c.mix(pickups.count)
        for p in pickups {
            c.mix(p.entityID); c.mix(p.pickupID)
            c.mix(p.positionSubunits.x); c.mix(p.positionSubunits.y)
            c.mix(p.lifetimeRemainingTicks); c.mix(p.graceTicksRemaining)
        }
        c.mix(spawnTelegraphs.count)
        for t in spawnTelegraphs {
            c.mix(t.entityID); c.mix(t.archetypeID); c.mix(t.spawnPointIndex)
            c.mix(t.positionSubunits.x); c.mix(t.positionSubunits.y)
            c.mix(t.ticksRemaining); c.mix(t.deferTicks)
        }
        if let stage {
            c.mix(stage.phase.rawValue)
            c.mix(stage.spawnQueue.count)
            for id in stage.spawnQueue { c.mix(id) }
            c.mix(stage.maxAliveEnemies); c.mix(stage.enemyStartDelayTicks)
            for p in stage.spawnPointsCells { c.mix(p.x); c.mix(p.y) }
            c.mix(stage.nextSpawnPointIndex); c.mix(stage.telegraphTicks)
            c.mix(stage.playerRespawnCell.x); c.mix(stage.playerRespawnCell.y)
            for id in stage.dropTable { c.mix(id) }
            c.mix(stage.dropChancePercent)
        } else {
            c.mix(-1)
        }
        c.mix(rng.movement.state); c.mix(rng.movement.draws)
        c.mix(rng.spawn.state); c.mix(rng.spawn.draws)
        c.mix(rng.drops.state); c.mix(rng.drops.draws)
        c.mix(rng.ai.state); c.mix(rng.ai.draws)
        c.mix(nextEntityID)
        return c.value
    }
}
