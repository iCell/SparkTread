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
        c.mix(rng.movement.state); c.mix(rng.movement.draws)
        c.mix(rng.spawn.state); c.mix(rng.spawn.draws)
        c.mix(rng.drops.state); c.mix(rng.drops.draws)
        c.mix(rng.ai.state); c.mix(rng.ai.draws)
        c.mix(nextEntityID)
        return c.value
    }
}
