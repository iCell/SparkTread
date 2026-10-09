/// FNV-1a 64-bit over a canonical field walk of the world. Dictionary keys
/// are sorted before hashing — Swift dictionary order is never treated as
/// deterministic.
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
        mix(UInt64(0xFF))
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
        func mixCell(_ cell: TerrainCell) {
            c.mix(cell.kind.rawValue)
            c.mix(cell.quadrantMask | (cell.crackMask << 4) | (cell.surface.rawValue << 8))
            c.mix(cell.ignitedAtTick)
            c.mix(cell.hasSpread)
        }
        for cell in terrain.cells { mixCell(cell) }
        for p in players {
            c.mix(p.playerID.rawValue)
            c.mix(p.active)
            c.mix(p.lives)
            c.mix(p.score)
            c.mix(p.tankEntityID)
            c.mix(p.lifeState.rawValue)
            for (k, v) in p.specialAmmoByWeapon.sorted(by: { $0.key < $1.key }) { c.mix(k); c.mix(v) }
            c.mix(p.respawnCountdownTicks)
            c.mix(p.retainedSpeedLevel); c.mix(p.retainedPowerLevel)
            c.mix(p.retainedEquipmentID ?? ""); c.mix(p.retainedSpecialWeaponID)
            c.mix(p.hitStreak); c.mix(p.maxHits); c.mix(p.comboStreak); c.mix(p.maxCombos); c.mix(p.lastComboKillTick)
        }
        for t in tanks {
            c.mix(t.entityID); c.mix(t.teamID); c.mix(t.ownerPlayerID?.rawValue); c.mix(t.archetypeID)
            c.mix(t.positionSubunits.x); c.mix(t.positionSubunits.y)
            c.mix(t.facing.rawValue); c.mix(t.movementIntent?.rawValue)
            c.mix(t.bufferedDirection?.rawValue); c.mix(t.bufferedDirectionRemainingTicks)
            c.mix(t.slideDirection?.rawValue); c.mix(t.slideMomentumSubunits); c.mix(t.slideIncrement)
            c.mix(t.movementAccumulator)
            c.mix(t.armor); c.mix(t.maxArmor); c.mix(t.shieldHP)
            c.mix(t.speedLevel); c.mix(t.powerLevel); c.mix(t.specialWeaponID); c.mix(t.equipmentID ?? "")
            for (k, v) in t.statusEffects.sorted(by: { $0.key < $1.key }) { c.mix(k); c.mix(v) }
            for (k, v) in t.fireCooldowns.sorted(by: { $0.key.rawValue < $1.key.rawValue }) { c.mix(k.rawValue); c.mix(v) }
            for (k, v) in t.activeProjectileCounts.sorted(by: { $0.key < $1.key }) { c.mix(k); c.mix(v) }
            c.mix(t.spawnProtectionTicks)
            c.mix(t.carriedPickup?.pickupID ?? ""); c.mix(t.carriedPickup?.critical ?? false)
            c.mix(t.leavingWater); c.mix(t.nextFireDamageTick)
            c.mix(t.normalFireBufferTicks); c.mix(t.specialHeldLastTick); c.mix(t.dryFireFeedbackTicks)
            c.mix(t.killedBy?.playerID?.rawValue); c.mix(t.killedBy?.byBomb ?? false)
        }
        c.mix(projectiles.count)
        for p in projectiles {
            c.mix(p.entityID); c.mix(p.weaponID); c.mix(p.ownerEntityID)
            c.mix(p.ownerPlayerID?.rawValue); c.mix(p.teamID); c.mix(p.powerLevel)
            c.mix(p.positionSubunits.x); c.mix(p.positionSubunits.y)
            c.mix(p.direction.rawValue); c.mix(p.velocity60); c.mix(p.travelRemainder)
            c.mix(p.lifetimeRemainingTicks)
            c.mix(p.launchOriginSubunits?.x); c.mix(p.launchOriginSubunits?.y)
            c.mix(p.damagedEnemy)
        }
        c.mix(fireHazards.count)
        for h in fireHazards {
            c.mix(h.entityID); c.mix(h.cell.x); c.mix(h.cell.y); c.mix(h.color.rawValue)
            c.mix(h.sourceKey); c.mix(h.ownerPlayerID?.rawValue); c.mix(h.createdTick); c.mix(h.lifetimeRemainingTicks)
        }
        if let base {
            c.mix(base.teamID)
            c.mix(base.topLeftSubunits.x); c.mix(base.topLeftSubunits.y)
            c.mix(base.durability); c.mix(base.maxDurability); c.mix(base.shieldRemainingTicks)
            c.mix(base.fortRecord.count)
            for record in base.fortRecord {
                c.mix(record.cell.x); c.mix(record.cell.y); mixCell(record.original); c.mix(record.hardenedMask)
            }
            c.mix(base.nextFireDamageTick)
        } else {
            c.mix(-1)
        }
        c.mix(pickups.count)
        for p in pickups {
            c.mix(p.entityID); c.mix(p.pickupID); c.mix(p.cell.x); c.mix(p.cell.y)
            c.mix(p.lifetimeRemainingTicks); c.mix(p.graceTicksRemaining); c.mix(p.critical)
        }
        c.mix(spawnTelegraphs.count)
        for t in spawnTelegraphs {
            c.mix(t.entityID); c.mix(t.archetypeID); c.mix(t.spawnPointIndex)
            c.mix(t.positionSubunits.x); c.mix(t.positionSubunits.y)
            c.mix(t.ticksRemaining); c.mix(t.deferTicks)
            c.mix(t.carriedPickup?.pickupID ?? ""); c.mix(t.carriedPickup?.critical ?? false)
        }
        if let stage {
            c.mix(stage.phase.rawValue)
            c.mix(stage.spawnQueue.count)
            for id in stage.spawnQueue { c.mix(id) }
            c.mix(stage.maxAliveEnemies); c.mix(stage.enemyStartDelayTicks)
            for p in stage.spawnPointsCells { c.mix(p.x); c.mix(p.y) }
            c.mix(stage.nextSpawnPointIndex); c.mix(stage.telegraphTicks)
            c.mix(stage.firstWaveStarted); c.mix(stage.spawnCooldownTicks)
            c.mix(stage.playerRespawnCell.x); c.mix(stage.playerRespawnCell.y)
            c.mix(stage.clearBonus.tally); c.mix(stage.clearBonus.reward)
            let b = stage.enemyBehavior
            c.mix(b.decisionIntervalTicks); c.mix(b.baseFocusPercent); c.mix(b.wanderPercent)
            c.mix(b.fireWindowPercent); c.mix(b.courseCommitPercent); c.mix(b.fireCyclePercent)
            c.mix(stage.directorPhases.count)
            for phase in stage.directorPhases {
                c.mix(phase.id); c.mix(phase.afterSpawned); c.mix(phase.reinforcements.count)
                for id in phase.reinforcements { c.mix(id) }
                c.mix(phase.maxAliveEnemies); c.mix(phase.repairsBase)
            }
            c.mix(stage.directorPhasesFired); c.mix(stage.directorSpawned)
            for id in stage.dropTable { c.mix(id) }
            c.mix(stage.dropChancePercent)
            c.mix(stage.carriedPickupQueue.count)
            for carried in stage.carriedPickupQueue { c.mix(carried?.pickupID ?? ""); c.mix(carried?.critical ?? false) }
            c.mix(stage.hiddenPickups.count)
            for h in stage.hiddenPickups { c.mix(h.cell.x); c.mix(h.cell.y); c.mix(h.pickupID); c.mix(h.critical) }
            c.mix(stage.pendingPickups.count)
            for p in stage.pendingPickups { c.mix(p.requestID); c.mix(p.requestTick); c.mix(p.pickupID); c.mix(p.critical) }
            c.mix(stage.nextPickupRequestID)
            c.mix(stage.fortTemplate.count)
            for f in stage.fortTemplate { c.mix(f.x); c.mix(f.y) }
            for k in stage.fortTemplateKinds { c.mix(k.rawValue) }
            c.mix(stage.brickDropChancePermille); c.mix(stage.brickDropCap); c.mix(stage.brickDropsGranted)
            c.mix(stage.baseShieldDurationPercent)
            c.mix(stage.clearedBrickCells.count)
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
