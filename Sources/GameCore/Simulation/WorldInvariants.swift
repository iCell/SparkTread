/// Development-fixture invariants (§18.2), checked every tick in tests and
/// debug sessions. Returns human-readable violations; empty means healthy.
/// The M1 subset covers what exists today and grows per milestone.
public enum WorldInvariants {
    public static func violations(in world: WorldState) -> [String] {
        var issues: [String] = []
        if world.tick < 0 { issues.append("tick is negative: \(world.tick)") }

        var seenEntityIDs = Set<Int>()
        var previousEntityID = Int.min
        for tank in world.tanks {
            let id = tank.entityID
            if !seenEntityIDs.insert(id).inserted { issues.append("duplicate entity id \(id)") }
            if id <= previousEntityID { issues.append("tanks not in ascending entity order at \(id)") }
            previousEntityID = id
            if id >= world.nextEntityID { issues.append("entity id \(id) >= nextEntityID") }

            let p = tank.positionSubunits
            let footprint = SpatialUnits.standardTankFootprintSubunits
            if p.x < 0 || p.y < 0
                || p.x + footprint > world.arena.widthSubunits
                || p.y + footprint > world.arena.heightSubunits {
                issues.append("tank \(id) outside arena bounds at (\(p.x),\(p.y))")
            }
            if let owner = tank.ownerPlayerID, world.player(owner) == nil {
                issues.append("tank \(id) references missing player \(owner.rawValue)")
            }
            if tank.armor < 0 || tank.armor > tank.maxArmor {
                issues.append("tank \(id) armor \(tank.armor) outside 0...\(tank.maxArmor)")
            }
            if !(0...3).contains(tank.speedLevel) { issues.append("tank \(id) speed level \(tank.speedLevel)") }
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
            if player.lives < 0 { issues.append("player \(player.playerID.rawValue) negative lives") }
            if let tankID = player.tankEntityID, !seenEntityIDs.contains(tankID) {
                issues.append("player \(player.playerID.rawValue) references missing tank \(tankID)")
            }
            for (weapon, ammo) in player.specialAmmoByWeapon where ammo < 0 {
                issues.append("player \(player.playerID.rawValue) negative ammo for \(weapon)")
            }
        }

        // Combat entities (§18.2: active-projectile counts match entities;
        // no destroyed entity remains addressable).
        var projectilesByOwner: [Int: [String: Int]] = [:]
        var previousProjectileID = Int.min
        for p in world.projectiles {
            if !seenEntityIDs.insert(p.entityID).inserted { issues.append("duplicate entity id \(p.entityID)") }
            if p.entityID <= previousProjectileID { issues.append("projectiles out of order at \(p.entityID)") }
            previousProjectileID = p.entityID
            if p.speedSubunitsPerTick > SpatialUnits.maxPerTickDisplacementSubunits {
                issues.append("projectile \(p.entityID) exceeds per-tick displacement cap")
            }
            projectilesByOwner[p.ownerEntityID, default: [:]][p.weaponID, default: 0] += 1
        }
        for m in world.mines {
            if !seenEntityIDs.insert(m.entityID).inserted { issues.append("duplicate entity id \(m.entityID)") }
            if !(0...3).contains(m.level) { issues.append("mine \(m.entityID) level \(m.level)") }
            projectilesByOwner[m.ownerEntityID, default: [:]]["mine", default: 0] += 1
        }
        for h in world.fireHazards {
            if !seenEntityIDs.insert(h.entityID).inserted { issues.append("duplicate entity id \(h.entityID)") }
        }
        for tank in world.tanks {
            for (weapon, count) in tank.activeProjectileCounts.sorted(by: { $0.key < $1.key })
            where weapon != "fire" { // hazards attribute by player, checked separately
                let actual = projectilesByOwner[tank.entityID]?[weapon] ?? 0
                if actual > count {
                    issues.append("tank \(tank.entityID) \(weapon) count \(count) < live entities \(actual)")
                }
            }
        }
        if let base = world.base, base.durability < 0 || base.durability > base.maxDurability {
            issues.append("base durability \(base.durability) outside 0...\(base.maxDurability)")
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
