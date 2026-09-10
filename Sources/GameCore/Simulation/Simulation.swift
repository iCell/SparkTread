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
        weapons: WeaponRuleset = .provisional,
        pickups: PickupRuleset = .provisional
    ) -> [DomainEvent] {
        var events: [DomainEvent] = []

        // A decided stage freezes gameplay; restart builds a fresh world.
        if let stage = world.stage, stage.phase != .playing {
            world.tick += 1
            return []
        }

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
        var landings: [Int] = []
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
                if status == "airborne", remaining <= 1 { landings.append(tank.entityID) }
            }
        }
        // Mine launch landings (§8.6, ADR-0016): the tank lands at the
        // nearest legal footprint to its nominal target by deterministic
        // ring scan (terrain, other tanks, the base), in place when no cell
        // within the scan is free, then is slowed for the level's ticks.
        for id in landings {
            guard let index = world.tanks.firstIndex(where: { $0.entityID == id }) else { continue }
            var tank = world.tanks[index]
            let target = tank.landingSubunits ?? tank.positionSubunits
            tank.landingSubunits = nil
            world.tanks[index] = tank
            let field = ObstacleField(world: world, excludingTank: id)
            let cell = SpatialUnits.subunitsPerCell, footprint = SpatialUnits.standardTankFootprintSubunits
            let inset = ruleset.collisionInsetSubunits
            let anchor = Vec2i(x: (target.x + cell / 2) / cell, y: (target.y + cell / 2) / cell)
            var landed = tank.positionSubunits
            for candidate in RingScan.cells(around: anchor, maxRadius: 4) {
                let p = Vec2i(x: candidate.x * cell, y: candidate.y * cell)
                if !field.blocksTank(minX: p.x + inset, minY: p.y + inset,
                                     maxX: p.x + footprint - inset, maxY: p.y + footprint - inset) {
                    landed = p
                    break
                }
            }
            tank.positionSubunits = landed
            tank.movementAccumulator = 0
            world.tanks[index] = tank
            events.append(.tankLanded(entityID: id, ownerPlayerID: tank.ownerPlayerID, position: landed))
        }
        if var base = world.base {
            if base.burnCooldownTicks > 0 { base.burnCooldownTicks -= 1 }
            var expired = false
            if base.shieldRemainingTicks > 0 {
                base.shieldRemainingTicks -= 1
                expired = base.shieldRemainingTicks == 0
            }
            world.base = base
            if expired {
                events.append(.baseShieldChanged(active: false))
                // Shovel expiry (§6.6, ADR-0010): the hardened fort ring is
                // restored from the activation record, skipping occupied cells.
                Stage.restoreBaseFortRing(&world, weapons: weapons, rules: pickups, events: &events)
            }
        }

        // 3. AI intents from the pre-movement world query (EnemyBrain).
        let aiFire = Stage.computeIntents(&world, ruleset: ruleset)

        // 4. Respawn requests (player death lifecycle, §6.5).
        Stage.processRespawns(&world, events: &events)

        // 5. Facing, alignment assistance, and movement (ascending entityID;
        // documented ID priority for tank-vs-tank resolution, §7.1).
        for index in world.tanks.indices {
            var tank = world.tanks[index]
            if tank.statusEffects["frozen"] != nil { continue } // held in place
            if tank.statusEffects["airborne"] != nil { continue } // in flight (§8.6): uncontrollable
            let field = ObstacleField(world: world, excludingTank: tank.entityID)
            resolveTurnAndMovement(&tank, field: field, ruleset: ruleset, events: &events)
            world.tanks[index] = tank
        }

        // 6–12. Combat (fire, spawning, advancement, collisions, pickups,
        // deaths — Stage handles pickups/deaths inside the combat pass).
        Combat.run(&world, firePressed: firePressed, aiFire: aiFire,
                   movement: ruleset, weapons: weapons, pickups: pickups, events: &events)

        // 12b. Hidden treasures whose covering brick fell this tick (§11).
        Stage.revealHiddenPickups(&world, rules: pickups, events: &events)

        // 13. EnemyDirector: telegraphs and finite spawns.
        Stage.runDirector(&world, events: &events)

        // 14. Objective/win/loss, after all damage and deaths (§6.7).
        Stage.resolveObjective(&world, events: &events)
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
        /// The moving tank's traversal profile (ADR-0016). A tank whose
        /// footprint already overlaps water — it lost AmphiTank mid-crossing
        /// — keeps the amphibious profile so it can finish leaving instead
        /// of being wedged for ever.
        let profile: TraversalProfile

        init(world: WorldState, excludingTank excluded: Int) {
            terrain = world.terrain
            var boxes: [(Int, Int, Int, Int)] = []
            let footprint = SpatialUnits.standardTankFootprintSubunits
            var profile = TraversalProfile.normal
            for other in world.tanks {
                if other.entityID == excluded {
                    profile = TraversalProfile(equipmentID: other.equipmentID)
                    let p = other.positionSubunits
                    if profile != .amphibious,
                       world.terrain.blocksTank(minX: p.x + 64, minY: p.y + 64, maxX: p.x + footprint - 64,
                                                maxY: p.y + footprint - 64, profile: .normal),
                       !world.terrain.blocksTank(minX: p.x + 64, minY: p.y + 64, maxX: p.x + footprint - 64,
                                                 maxY: p.y + footprint - 64, profile: .amphibious) {
                        profile = .amphibious // embedded in water: may leave
                    }
                    continue
                }
                // Airborne tanks (mine launch, §8.6) are suspended from all interactions.
                if other.statusEffects["airborne"] != nil { continue }
                let p = other.positionSubunits
                boxes.append((p.x, p.y, p.x + footprint, p.y + footprint))
            }
            if let base = world.base {
                let p = base.topLeftSubunits
                boxes.append((p.x, p.y, p.x + base.sizeSubunits, p.y + base.sizeSubunits))
            }
            self.boxes = boxes
            self.profile = profile
        }

        func blocksTank(minX: Int, minY: Int, maxX: Int, maxY: Int) -> Bool {
            if terrain.blocksTank(minX: minX, minY: minY, maxX: maxX, maxY: maxY, profile: profile) { return true }
            for box in boxes
            where minX < box.maxX && maxX > box.minX && minY < box.maxY && maxY > box.minY {
                return true
            }
            return false
        }
    }

    // MARK: - Movement (step 5)

    /// Per-tick travel in whole subunits from the integer accumulator
    /// (§7.1), at the tank's speed level, halved-by-percent while slowed.
    private static func consumeTravel(_ tank: inout TankState, ruleset: MovementRuleset) -> Int {
        var increment = tank.ownerPlayerID != nil
            ? ruleset.accumulatorIncrement(speedLevel: tank.speedLevel)
            : ruleset.enemyAccumulatorIncrement(speedLevel: tank.speedLevel)
        if tank.statusEffects["slowed"] != nil { increment = increment * ruleset.slowedSpeedPercent / 100 }
        tank.movementAccumulator += increment
        let wholeSubunits = tank.movementAccumulator / MovementRuleset.accumulatorUnitsPerSubunit
        tank.movementAccumulator %= MovementRuleset.accumulatorUnitsPerSubunit
        return wholeSubunits
    }

    /// The tank's centre cell is ice and its equipment does not grip.
    private static func slidesOnIce(_ tank: TankState, field: ObstacleField) -> Bool {
        guard TraversalProfile(equipmentID: tank.equipmentID) != .traction else { return false }
        let footprint = SpatialUnits.standardTankFootprintSubunits, cell = SpatialUnits.subunitsPerCell
        let cx = (tank.positionSubunits.x + footprint / 2) / cell, cy = (tank.positionSubunits.y + footprint / 2) / cell
        return field.terrain.isInside(cellX: cx, cellY: cy) && field.terrain[cx, cy].kind == .ice
    }

    private static func resolveTurnAndMovement(
        _ tank: inout TankState, field: ObstacleField,
        ruleset: MovementRuleset, events: inout [DomainEvent]
    ) {
        // Ice inertia (§7.3, ADR-0016). `slideDirection` remembers the last
        // travel direction while the centre is on ice; releasing input or
        // changing direction there converts it into a slide of
        // `iceSlideDistanceSubunits`, during which input only turns the
        // facing ("turning friction") — except the slide direction itself,
        // which cancels the slide and drives on. Off ice, nothing slides.
        let onIce = ruleset.iceSlideDistanceSubunits > 0 && slidesOnIce(tank, field: field)
        if !onIce {
            tank.slideDirection = nil
            tank.slideMomentumSubunits = 0
        } else {
            let intent = tank.movementIntent
            if tank.slideMomentumSubunits > 0, let sliding = tank.slideDirection {
                if intent == sliding {
                    tank.slideMomentumSubunits = 0 // driving on in the slide direction
                } else {
                    if let intent, intent != tank.facing {
                        tank.facing = intent // turns, but keeps sliding
                        tank.bufferedDirection = nil
                        tank.bufferedDirectionRemainingTicks = 0
                        events.append(.tankTurned(entityID: tank.entityID, facing: intent))
                    }
                    slide(&tank, direction: sliding, field: field, ruleset: ruleset)
                    return
                }
            } else if let last = tank.slideDirection, intent == nil || intent != last {
                // Release or direction change with momentum: start sliding.
                tank.slideMomentumSubunits = ruleset.iceSlideDistanceSubunits
                if let intent, intent != tank.facing {
                    tank.facing = intent
                    tank.bufferedDirection = nil
                    tank.bufferedDirectionRemainingTicks = 0
                    events.append(.tankTurned(entityID: tank.entityID, facing: intent))
                }
                slide(&tank, direction: last, field: field, ruleset: ruleset)
                return
            }
        }

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

        let wholeSubunits = consumeTravel(&tank, ruleset: ruleset)
        guard wholeSubunits > 0 else { return }

        let travelDirection = tank.facing
        let moved = sweptMove(&tank, direction: travelDirection, distance: wholeSubunits,
                              field: field, ruleset: ruleset)
        if moved < wholeSubunits {
            // Blocked: drop the unused distance so pressing into a wall does
            // not bank speed (documented, deterministic).
            tank.movementAccumulator = 0
        }
        if onIce, moved > 0 { tank.slideDirection = travelDirection } // momentum to spend later
    }

    /// One tick of sliding: the tank's normal per-tick travel along the
    /// slide direction, bounded by the remaining momentum; a block ends the
    /// slide flush against the obstacle.
    private static func slide(_ tank: inout TankState, direction: Direction, field: ObstacleField,
                              ruleset: MovementRuleset) {
        let step = min(tank.slideMomentumSubunits, consumeTravel(&tank, ruleset: ruleset))
        guard step > 0 else { return }
        let moved = sweptMove(&tank, direction: direction, distance: step, field: field, ruleset: ruleset)
        tank.slideMomentumSubunits = moved < step ? 0 : tank.slideMomentumSubunits - moved
        if moved < step { tank.movementAccumulator = 0 }
        if tank.slideMomentumSubunits == 0 { tank.slideDirection = nil }
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
        // The vector is blocked here. Buffer-and-roll ONLY when a junction
        // exists within buffered travel (the pre-turn assist case);
        // otherwise turn in place immediately — a tank beside a wall must
        // still be able to FACE that wall (owner-reported; reference feel).
        let canKeepRolling = probeIsFree(position: tank.positionSubunits, direction: tank.facing,
                                         field: field, ruleset: ruleset)
        if !canKeepRolling || !junctionWithinBufferTravel(tank, to: desired, field: field, ruleset: ruleset) {
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

    /// Whether some lane within the tank's buffered travel distance ahead
    /// would make the perpendicular turn legal — i.e., a junction is coming
    /// up. Deterministic spatial lookahead; scans half-cell lanes reachable
    /// through free path within `turnBufferTicks` of travel plus the assist
    /// window.
    private static func junctionWithinBufferTravel(
        _ tank: TankState, to desired: Direction, field: ObstacleField, ruleset: MovementRuleset
    ) -> Bool {
        let lane = SpatialUnits.subunitsPerQuadrant
        let perTick = (tank.ownerPlayerID != nil
            ? ruleset.accumulatorIncrement(speedLevel: tank.speedLevel)
            : ruleset.enemyAccumulatorIncrement(speedLevel: tank.speedLevel))
            / MovementRuleset.accumulatorUnitsPerSubunit
        let reach = perTick * ruleset.turnBufferTicks + ruleset.alignmentAssistWindowSubunits
        let travelAxisIsX = tank.facing.vector.x != 0
        let coordinate = travelAxisIsX ? tank.positionSubunits.x : tank.positionSubunits.y
        let sign = tank.facing.vector.x + tank.facing.vector.y // ±1
        // First lane strictly ahead (the current lane was already rejected
        // by the snap-assisted check).
        var next = sign > 0
            ? ((coordinate / lane) + 1) * lane
            : (coordinate % lane == 0 ? coordinate - lane : (coordinate / lane) * lane)
        while (next - coordinate) * sign <= reach && next >= 0 {
            let distance = (next - coordinate) * sign
            var candidate = tank.positionSubunits
            if travelAxisIsX { candidate.x = next } else { candidate.y = next }
            if probeIsFree(position: tank.positionSubunits, direction: tank.facing,
                           field: field, ruleset: ruleset, distance: distance),
               probeIsFree(position: candidate, direction: desired,
                           field: field, ruleset: ruleset, distance: turnProbeDistance(ruleset)) {
                return true
            }
            next += sign * lane
        }
        return false
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
        if leavesArena(from: position, to: target, arena: field.terrain.arena) { return false }
        let box = sweptBox(from: position, to: target, ruleset: ruleset)
        return !field.blocksTank(minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY)
    }

    /// Arena-boundary contract (R15-03): the NOMINAL footprint stays inside
    /// the arena — the collision inset applies to obstacles only, so a tank
    /// on an open edge (no solid border) cannot poke `inset` subunits past
    /// the boundary and fail the world invariants.
    private static func leavesArena(from: Vec2i, to: Vec2i, arena: ArenaSpecification) -> Bool {
        let footprint = SpatialUnits.standardTankFootprintSubunits
        let minX = min(from.x, to.x), minY = min(from.y, to.y)
        let maxX = max(from.x, to.x) + footprint, maxY = max(from.y, to.y) + footprint
        return minX < 0 || minY < 0 || maxX > arena.widthSubunits || maxY > arena.heightSubunits
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
            if leavesArena(from: start, to: candidate, arena: field.terrain.arena)
                || field.blocksTank(minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY) {
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
