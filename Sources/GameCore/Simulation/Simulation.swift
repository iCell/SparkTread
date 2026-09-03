/// The fixed-tick simulation kernel. One call advances exactly one 1/60 s
/// tick through the §13.6 top-level order. M1 implements steps 1, 2, 5, 15
/// and 17; the remaining steps are explicit no-op placeholders so later
/// milestones extend, not reorder (reordering requires an ADR).
public enum Simulation {
    /// Advances the world by one tick. `commands` are this tick's external
    /// inputs (at most one per player; a missing command is neutral input,
    /// ADR-0002). Returns the ordered domain events of the tick.
    @discardableResult
    public static func step(
        _ world: inout WorldState,
        commands: [PlayerCommand],
        ruleset: MovementRuleset = .provisional,
        weapons: WeaponRuleset = .provisional
    ) -> [DomainEvent] {
        var events: [DomainEvent] = []

        // 1. Consume player commands: validate and map to held intents.
        var heldDirection: [PlayerID: Direction?] = [:]
        var firePressed: [PlayerID: (normal: Bool, special: Bool)] = [:]
        for command in commands {
            guard command.targetTick == world.tick,
                  let player = world.player(command.playerID), player.active else { continue }
            heldDirection[command.playerID] = command.moveDirection
            firePressed[command.playerID] = (command.normalFirePressed, command.specialFirePressed)
        }
        world.withTanksInEntityOrder { tank in
            if let owner = tank.ownerPlayerID {
                tank.movementIntent = heldDirection[owner] ?? nil
            }
        }

        // 2. Timers and status effects.
        world.withTanksInEntityOrder { tank in
            if tank.spawnProtectionTicks > 0 { tank.spawnProtectionTicks -= 1 }
            if tank.bufferedDirectionRemainingTicks > 0 {
                tank.bufferedDirectionRemainingTicks -= 1
                if tank.bufferedDirectionRemainingTicks == 0 { tank.bufferedDirection = nil }
            }
            for (channel, remaining) in tank.fireCooldowns.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                tank.fireCooldowns[channel] = remaining > 1 ? remaining - 1 : nil
            }
            for (status, remaining) in tank.statusEffects.sorted(by: { $0.key < $1.key }) {
                tank.statusEffects[status] = remaining > 1 ? remaining - 1 : nil
            }
        }
        if var base = world.base, base.shieldRemainingTicks > 0 {
            base.shieldRemainingTicks -= 1
            if base.shieldRemainingTicks == 0 { events.append(.baseShieldChanged(active: false)) }
            world.base = base
        }

        // 3. AI intents — no AI until M3.
        // 4. Session requests — none handled yet.

        // 5. Facing, alignment assistance, and movement (ascending entityID;
        // documented ID priority for tank-vs-tank resolution, §7.1).
        for index in world.tanks.indices {
            var tank = world.tanks[index]
            let field = ObstacleField(world: world, excludingTank: tank.entityID)
            resolveTurnAndMovement(&tank, field: field, ruleset: ruleset, events: &events)
            world.tanks[index] = tank
        }

        // 6–12. Combat (fire, spawning, advancement, collisions, deaths).
        Combat.run(&world, firePressed: firePressed, movement: ruleset,
                   weapons: weapons, events: &events)

        // 13–14. Director and objectives — M3.
        // 15. Ordered domain events are the return value.
        // 16. The value-type WorldState IS the snapshot source.
        // 17. Checksum is computed by the caller's cadence via `checksum()`.
        world.tick += 1
        return events
    }

    /// Everything solid for TANK movement: terrain plus other tanks and the
    /// base (mines and fire hazards never block movement).
    struct ObstacleField {
        let terrain: TerrainGrid
        let boxes: [(minX: Int, minY: Int, maxX: Int, maxY: Int)]

        init(world: WorldState, excludingTank excluded: Int) {
            terrain = world.terrain
            var boxes: [(Int, Int, Int, Int)] = []
            let footprint = SpatialUnits.standardTankFootprintSubunits
            for other in world.tanks where other.entityID != excluded {
                let p = other.positionSubunits
                boxes.append((p.x, p.y, p.x + footprint, p.y + footprint))
            }
            if let base = world.base {
                let p = base.topLeftSubunits
                boxes.append((p.x, p.y, p.x + base.sizeSubunits, p.y + base.sizeSubunits))
            }
            self.boxes = boxes
        }

        func blocksTank(minX: Int, minY: Int, maxX: Int, maxY: Int) -> Bool {
            if terrain.blocksTank(minX: minX, minY: minY, maxX: maxX, maxY: maxY) { return true }
            for box in boxes
            where minX < box.maxX && maxX > box.minX && minY < box.maxY && maxY > box.minY {
                return true
            }
            return false
        }
    }

    // MARK: - Movement (step 5)

    private static func resolveTurnAndMovement(
        _ tank: inout TankState, field: ObstacleField,
        ruleset: MovementRuleset, events: inout [DomainEvent]
    ) {
        // A held direction is the live turn candidate; otherwise a still-live
        // buffered direction keeps trying (§6.3 — a tap shortly before a
        // legal turn executes when alignment arrives).
        if let desired = tank.movementIntent, desired != tank.facing {
            attemptTurn(&tank, to: desired, live: true, field: field, ruleset: ruleset, events: &events)
        } else if let buffered = tank.bufferedDirection, tank.bufferedDirectionRemainingTicks > 0,
                  buffered != tank.facing {
            attemptTurn(&tank, to: buffered, live: false, field: field, ruleset: ruleset, events: &events)
        }

        // Advance while a direction is held, or while a buffered turn is
        // still pending — a tap shortly before a junction keeps the tank
        // rolling to the turn point even after full release (§6.3).
        let moving = tank.movementIntent != nil
            || (tank.bufferedDirection != nil && tank.bufferedDirectionRemainingTicks > 0)
        guard moving else { return }

        tank.movementAccumulator += ruleset.accumulatorIncrement(speedLevel: tank.speedLevel)
        let wholeSubunits = tank.movementAccumulator / MovementRuleset.accumulatorUnitsPerSubunit
        tank.movementAccumulator %= MovementRuleset.accumulatorUnitsPerSubunit
        guard wholeSubunits > 0 else { return }

        let travelDirection = tank.facing
        let moved = sweptMove(&tank, direction: travelDirection, distance: wholeSubunits,
                              field: field, ruleset: ruleset)
        if moved < wholeSubunits {
            // Blocked: drop the unused distance so pressing into a wall does
            // not bank speed (documented, deterministic).
            tank.movementAccumulator = 0
        }
    }

    /// Attempts a facing change with alignment assistance (§6.3, §7.1).
    /// Outcomes, in priority order:
    /// 1. Same-axis change (reversal): always turns — no alignment needed.
    /// 2. Perpendicular with a legal (possibly snap-assisted) new vector:
    ///    snap within the assist window and turn.
    /// 3. Perpendicular, new vector blocked, but the tank also cannot keep
    ///    rolling along its current facing: turn in place without snap, so a
    ///    tank at a dead end can still face (and later shoot) the wall.
    /// 4. Otherwise: buffer the request and keep rolling toward alignment.
    private static func attemptTurn(
        _ tank: inout TankState, to desired: Direction, live: Bool, field: ObstacleField,
        ruleset: MovementRuleset, events: inout [DomainEvent]
    ) {
        func turn() {
            tank.facing = desired
            tank.bufferedDirection = nil
            tank.bufferedDirectionRemainingTicks = 0
            events.append(.tankTurned(entityID: tank.entityID, facing: desired))
        }
        if !tank.facing.isPerpendicular(to: desired) {
            turn()
            return
        }
        if snapAssistedVectorIsFree(&tank, to: desired, field: field, ruleset: ruleset) {
            turn()
            return
        }
        let canKeepRolling = probeIsFree(position: tank.positionSubunits, direction: tank.facing,
                                         field: field, ruleset: ruleset)
        if !canKeepRolling {
            turn()
            return
        }
        if live {
            // Only a live press (re)arms the window; a buffered retry that
            // still fails just keeps its remaining ticks.
            tank.bufferedDirection = desired
            tank.bufferedDirectionRemainingTicks = ruleset.turnBufferTicks
        }
    }

    /// Perpendicular-turn legality with lane alignment (reference-heritage
    /// movement): tanks travel on half-cell lanes (multiples of 512 subunits;
    /// 2-cell corridors need full-cell lanes of 1024). Turning snaps the
    /// travel-axis coordinate to the nearest legal lane within the assist
    /// window — the nudge is swept, never through collision, and never
    /// changes tactical speed (§6.3). Candidates are tried in a fixed,
    /// documented order: half-cell lane, then full-cell lane. Mutates the
    /// position only when returning true.
    private static func snapAssistedVectorIsFree(
        _ tank: inout TankState, to desired: Direction, field: ObstacleField,
        ruleset: MovementRuleset
    ) -> Bool {
        let travelAxisIsX = (tank.facing == .left || tank.facing == .right)
        let coordinate = travelAxisIsX ? tank.positionSubunits.x : tank.positionSubunits.y

        func nearestLane(_ granularity: Int) -> Int {
            ((coordinate + granularity / 2) / granularity) * granularity
        }
        var candidates = [nearestLane(SpatialUnits.subunitsPerQuadrant)]
        let fullCell = nearestLane(SpatialUnits.subunitsPerCell)
        if fullCell != candidates[0] { candidates.append(fullCell) }

        for lane in candidates {
            let offset = lane - coordinate
            guard abs(offset) <= ruleset.alignmentAssistWindowSubunits else { continue }
            var candidate = tank.positionSubunits
            if travelAxisIsX { candidate.x = lane } else { candidate.y = lane }
            if offset != 0 {
                let nudgeDirection: Direction = travelAxisIsX
                    ? (offset > 0 ? .right : .left)
                    : (offset > 0 ? .down : .up)
                var probe = tank
                guard sweptMove(&probe, direction: nudgeDirection, distance: abs(offset),
                                field: field, ruleset: ruleset) == abs(offset) else { continue }
            }
            guard probeIsFree(position: candidate, direction: desired,
                              field: field, ruleset: ruleset,
                              distance: turnProbeDistance(ruleset)) else { continue }
            tank.positionSubunits = candidate
            return true
        }
        return false
    }

    /// Whether `distance` subunits of travel in `direction` from `position`
    /// are free (swept box; the current occupancy is legal by invariant).
    private static func probeIsFree(
        position: Vec2i, direction: Direction, field: ObstacleField, ruleset: MovementRuleset,
        distance: Int = 1
    ) -> Bool {
        let target = position + direction.vector * distance
        let box = sweptBox(from: position, to: target, ruleset: ruleset)
        return !field.blocksTank(minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY)
    }

    /// A turn is only "collision-free" (§7.1) when the tank can actually
    /// travel past the collision-inset slack in the new direction — a
    /// 1-subunit probe would call a flush wall "free" because the inset
    /// leaves up to 2×inset subunits of slack in front of it.
    private static func turnProbeDistance(_ ruleset: MovementRuleset) -> Int {
        2 * ruleset.collisionInsetSubunits + 1
    }

    /// Swept axis-aligned movement: advances up to `distance` subunits along
    /// `direction`, stopping flush against the first blocking geometry.
    /// Returns the distance actually moved. Deterministic: pure integer math.
    @discardableResult
    private static func sweptMove(
        _ tank: inout TankState, direction: Direction, distance: Int,
        field: ObstacleField, ruleset: MovementRuleset
    ) -> Int {
        precondition(distance >= 0)
        guard distance > 0 else { return 0 }
        let start = tank.positionSubunits
        let vector = direction.vector
        // Binary-search-free approach: test the whole swept box; when it
        // blocks, clamp per-quadrant granularity by stepping the largest
        // free prefix using halving. Distances are ≤ 1023/tick, so the
        // halving loop is at most ~10 iterations — deterministic and cheap.
        var lo = 0
        var hi = distance
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let candidate = Vec2i(x: start.x + vector.x * mid, y: start.y + vector.y * mid)
            let box = sweptBox(from: start, to: candidate, ruleset: ruleset)
            if field.blocksTank(minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY) {
                hi = mid - 1
            } else {
                lo = mid
            }
        }
        tank.positionSubunits = Vec2i(x: start.x + vector.x * lo, y: start.y + vector.y * lo)
        return lo
    }

    private static func collisionBox(
        position: Vec2i, ruleset: MovementRuleset
    ) -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
        let inset = ruleset.collisionInsetSubunits
        let footprint = SpatialUnits.standardTankFootprintSubunits
        return (position.x + inset, position.y + inset,
                position.x + footprint - inset, position.y + footprint - inset)
    }

    private static func sweptBox(
        from: Vec2i, to: Vec2i, ruleset: MovementRuleset
    ) -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
        let a = collisionBox(position: from, ruleset: ruleset)
        let b = collisionBox(position: to, ruleset: ruleset)
        return (min(a.minX, b.minX), min(a.minY, b.minY), max(a.maxX, b.maxX), max(a.maxY, b.maxY))
    }
}
