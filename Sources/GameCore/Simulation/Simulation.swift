/// The fixed-tick simulation kernel. One call advances exactly one 1/60 s
/// tick through the GAME_RULES §12 order:
/// 1 timers and input → 2 intents and respawns → 3 movement → 4 firing →
/// 5 flight and contacts → 6 fire → 7 deaths → 8 pickups → 9 spawning and
/// win/loss.
public enum Simulation {
    /// Player special-button state for one tick: held now, and pressed this tick.
    struct SpecialInput { var held: Bool; var edge: Bool }

    /// Advances the world by one tick. `commands` are this tick's external
    /// inputs (at most one per player; a missing command is neutral input).
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

        // 1. Timers that existed before this tick, then this tick's input.
        advanceTimers(&world, weapons: weapons, events: &events)
        Stage.updateFort(&world, events: &events)
        let specialInput = consumeCommands(&world, commands: commands, weapons: weapons)

        // 2. AI intents from the pre-movement world; player respawns.
        let aiFire = Stage.computeIntents(&world, ruleset: ruleset, weapons: weapons)
        Stage.processRespawns(&world, events: &events)

        // 3. Turning, alignment, ice, water exit and movement (ascending id).
        for index in world.tanks.indices {
            guard world.tanks[index].armor > 0, world.tanks[index].statusEffects["frozen"] == nil else { continue }
            if world.tanks[index].leavingWater {
                updateWaterExit(&world, tankIndex: index, ruleset: ruleset)
            }
            var tank = world.tanks[index]
            let field = ObstacleField(world: world, excludingTank: tank.entityID,
                                      movingWithInset: ruleset.collisionInsetSubunits)
            resolveTurnAndMovement(&tank, field: field, ruleset: ruleset, events: &events)
            world.tanks[index] = tank
        }

        // 4–5. Firing, flight, the time-ordered contact queue, expiry.
        Combat.run(&world, specialInput: specialInput, aiFire: aiFire, weapons: weapons, events: &events)

        // 6. Ground fire: spread, damage, burn-out.
        Fire.resolve(&world, weapons: weapons, events: &events)

        // 7. Deaths, score, drops; hidden pickups whose walls are gone.
        Stage.processDeaths(&world, events: &events)
        Stage.revealHiddenPickups(&world, rules: pickups, events: &events)

        // 8. Pickups (Bomb deaths settle here), then pending placements.
        Stage.processPickups(&world, weapons: weapons, rules: pickups, events: &events)
        Stage.processDeaths(&world, events: &events)
        Stage.placePendingPickups(&world, ruleset: ruleset, rules: pickups, events: &events)

        // 9. Spawning and the objective.
        Stage.runDirector(&world, ruleset: ruleset, events: &events)
        Stage.resolveObjective(&world, events: &events)
        world.tick += 1
        return events
    }

    // MARK: - Step 1

    /// Decrements every timer created before this tick. Expired flames and
    /// pickups leave before any query of this tick.
    private static func advanceTimers(_ world: inout WorldState, weapons: WeaponRuleset,
                                      events: inout [DomainEvent]) {
        for index in world.tanks.indices {
            var tank = world.tanks[index]
            if tank.spawnProtectionTicks > 0 { tank.spawnProtectionTicks -= 1 }
            if tank.bufferedDirectionRemainingTicks > 0 {
                tank.bufferedDirectionRemainingTicks -= 1
                if tank.bufferedDirectionRemainingTicks == 0 { tank.bufferedDirection = nil }
            }
            if tank.normalFireBufferTicks > 0 {
                tank.normalFireBufferTicks -= 1
                if tank.normalFireBufferTicks == 0, tank.armor > 0 {
                    // The buffered press expired unfired: one dry-fire cue.
                    events.append(.dryFire(entityID: tank.entityID, ownerPlayerID: tank.ownerPlayerID, weaponID: "normal"))
                }
            }
            if tank.dryFireFeedbackTicks > 0 { tank.dryFireFeedbackTicks -= 1 }
            for (channel, remaining) in tank.fireCooldowns.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                tank.fireCooldowns[channel] = remaining > 1 ? remaining - 1 : nil
            }
            for (status, remaining) in tank.statusEffects.sorted(by: { $0.key < $1.key }) {
                tank.statusEffects[status] = remaining > 1 ? remaining - 1 : nil
            }
            world.tanks[index] = tank
        }
        for index in world.fireHazards.indices { world.fireHazards[index].lifetimeRemainingTicks -= 1 }
        world.fireHazards.removeAll { $0.lifetimeRemainingTicks <= 0 }
        for index in world.pickups.indices {
            if !world.pickups[index].critical { world.pickups[index].lifetimeRemainingTicks -= 1 }
            if world.pickups[index].graceTicksRemaining > 0 { world.pickups[index].graceTicksRemaining -= 1 }
        }
        world.pickups.removeAll { !$0.critical && $0.lifetimeRemainingTicks <= 0 }
        if var base = world.base, base.shieldRemainingTicks > 0 {
            base.shieldRemainingTicks -= 1
            world.base = base
            if base.shieldRemainingTicks == 0 { events.append(.baseShieldChanged(active: false)) }
        }
    }

    /// Movement intents, the buffered normal press, and special-button edges.
    private static func consumeCommands(_ world: inout WorldState, commands: [PlayerCommand],
                                        weapons: WeaponRuleset) -> [Int: SpecialInput] {
        var byPlayer: [PlayerID: PlayerCommand] = [:]
        for command in commands {
            guard command.targetTick == world.tick,
                  let player = world.player(command.playerID), player.active else { continue }
            byPlayer[command.playerID] = command
        }
        var special: [Int: SpecialInput] = [:]
        for index in world.tanks.indices {
            guard let owner = world.tanks[index].ownerPlayerID else { continue }
            var tank = world.tanks[index]
            let command = byPlayer[owner]
            if command?.sessionRequest == .continue {
                // Resuming from a pause (§5.1, §15.3): buffered presses and
                // turns are dropped — nothing fires or turns late.
                tank.normalFireBufferTicks = 0
                tank.bufferedDirection = nil
                tank.bufferedDirectionRemainingTicks = 0
                tank.specialHeldLastTick = false
            }
            tank.movementIntent = command?.moveDirection
            let held = command?.specialFirePressed ?? false
            special[tank.entityID] = SpecialInput(held: held, edge: held && !tank.specialHeldLastTick)
            tank.specialHeldLastTick = held
            if command?.normalFirePressed == true { tank.normalFireBufferTicks = weapons.normalFireBufferTicks }
            world.tanks[index] = tank
        }
        return special
    }

    // MARK: - Obstacles

    /// Everything solid for TANK movement: terrain, other tanks, the base,
    /// and spawn-process reservations (GAME_RULES §9.3).
    struct ObstacleField {
        let terrain: TerrainGrid
        let boxes: [(minX: Int, minY: Int, maxX: Int, maxY: Int)]
        let profile: TraversalProfile

        /// `movingWithInset`: the field is for the excluded tank's own
        /// movement, whose collision box is inset by this much. A spawn
        /// reservation keeps tanks from ENTERING (§9.3); one the tank already
        /// stands in must not wall it in, or the tank and the blocked spawn
        /// process wait on each other forever.
        init(world: WorldState, excludingTank excluded: Int, excludingTelegraph excludedTelegraph: Int? = nil,
             movingWithInset inset: Int? = nil) {
            terrain = world.terrain
            var boxes: [(Int, Int, Int, Int)] = []
            let footprint = SpatialUnits.standardTankFootprintSubunits
            var profile = TraversalProfile.normal
            var mover: Vec2i?
            for other in world.tanks {
                if other.entityID == excluded {
                    profile = other.leavingWater ? .amphibious : TraversalProfile(equipmentID: other.equipmentID)
                    mover = other.positionSubunits
                    continue
                }
                let p = other.positionSubunits
                boxes.append((p.x, p.y, p.x + footprint, p.y + footprint))
            }
            if let base = world.base {
                let p = base.topLeftSubunits
                boxes.append((p.x, p.y, p.x + base.sizeSubunits, p.y + base.sizeSubunits))
            }
            for telegraph in world.spawnTelegraphs where telegraph.entityID != excludedTelegraph {
                let p = telegraph.positionSubunits
                if let inset, let m = mover,
                   m.x + inset < p.x + footprint, m.x + footprint - inset > p.x,
                   m.y + inset < p.y + footprint, m.y + footprint - inset > p.y {
                    continue // already inside: free to drive out
                }
                boxes.append((p.x, p.y, p.x + footprint, p.y + footprint))
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

    // MARK: - Water exit (GAME_RULES §4.4)

    /// Leaves the state when the tank is dry; places the tank on the nearest
    /// legal land when no static direction can reduce its water overlap.
    static func updateWaterExit(_ world: inout WorldState, tankIndex: Int, ruleset: MovementRuleset) {
        var tank = world.tanks[tankIndex]
        let inset = ruleset.collisionInsetSubunits
        let footprint = SpatialUnits.standardTankFootprintSubunits
        func box(_ p: Vec2i) -> (Int, Int, Int, Int) { (p.x + inset, p.y + inset, p.x + footprint - inset, p.y + footprint - inset) }
        func overlap(_ p: Vec2i) -> Int {
            let b = box(p)
            return world.terrain.waterOverlapArea(minX: b.0, minY: b.1, maxX: b.2, maxY: b.3)
        }
        let here = overlap(tank.positionSubunits)
        if here == 0 {
            tank.leavingWater = false
            world.tanks[tankIndex] = tank
            return
        }
        for direction in Direction.allCases {
            let target = tank.positionSubunits + direction.vector
            if leavesArena(from: tank.positionSubunits, to: target, arena: world.arena) { continue }
            let swept = sweptBox(from: tank.positionSubunits, to: target, ruleset: ruleset)
            if world.terrain.blocksTank(minX: swept.minX, minY: swept.minY, maxX: swept.maxX, maxY: swept.maxY,
                                        profile: .amphibious) { continue }
            if overlap(target) < here { return } // a way out exists
        }
        // Trapped: the nearest legal half-cell-lane position, by squared
        // distance then (y, x).
        let lane = SpatialUnits.subunitsPerQuadrant
        let field = ObstacleField(world: world, excludingTank: tank.entityID)
        var best: (distance: Int, y: Int, x: Int)?
        var y = 0
        while y <= world.arena.heightSubunits - footprint {
            var x = 0
            while x <= world.arena.widthSubunits - footprint {
                let dx = x - tank.positionSubunits.x, dy = y - tank.positionSubunits.y
                let distance = dx * dx + dy * dy
                if best == nil || (distance, y, x) < (best!.distance, best!.y, best!.x) {
                    let b = box(Vec2i(x: x, y: y))
                    if !world.terrain.blocksTank(minX: b.0, minY: b.1, maxX: b.2, maxY: b.3, profile: .normal),
                       !boxesBlock(field.boxes, b) {
                        best = (distance, y, x)
                    }
                }
                x += lane
            }
            y += lane
        }
        guard let best else { return } // no room anywhere: wait and retry
        tank.positionSubunits = Vec2i(x: best.x, y: best.y)
        tank.leavingWater = false
        tank.movementAccumulator = 0
        tank.slideDirection = nil
        tank.slideMomentumSubunits = 0
        tank.spawnProtectionTicks = max(tank.spawnProtectionTicks, 60)
        world.tanks[tankIndex] = tank
    }

    private static func boxesBlock(_ boxes: [(minX: Int, minY: Int, maxX: Int, maxY: Int)], _ b: (Int, Int, Int, Int)) -> Bool {
        boxes.contains { b.0 < $0.maxX && b.2 > $0.minX && b.1 < $0.maxY && b.3 > $0.minY }
    }

    // MARK: - Movement (step 3)

    private static func increment(_ tank: TankState, ruleset: MovementRuleset) -> Int {
        tank.ownerPlayerID != nil
            ? ruleset.accumulatorIncrement(speedLevel: tank.speedLevel)
            : ruleset.enemyAccumulatorIncrement(speedLevel: tank.speedLevel)
    }

    /// Whole subunits of travel this tick from the integer accumulator.
    private static func consumeTravel(_ tank: inout TankState, increment: Int) -> Int {
        tank.movementAccumulator += increment
        let whole = tank.movementAccumulator / MovementRuleset.accumulatorUnitsPerSubunit
        tank.movementAccumulator %= MovementRuleset.accumulatorUnitsPerSubunit
        return whole
    }

    /// The tank's centre cell (floored) has an ice surface and its equipment
    /// does not grip.
    private static func slidesOnIce(_ tank: TankState, terrain: TerrainGrid) -> Bool {
        guard TraversalProfile(equipmentID: tank.equipmentID) != .traction else { return false }
        let footprint = SpatialUnits.standardTankFootprintSubunits, cell = SpatialUnits.subunitsPerCell
        let cx = (tank.positionSubunits.x + footprint / 2) / cell, cy = (tank.positionSubunits.y + footprint / 2) / cell
        return terrain.isInside(cellX: cx, cellY: cy) && terrain[cx, cy].surface == .ice
    }

    private static func turnFacing(_ tank: inout TankState, to direction: Direction, events: inout [DomainEvent]) {
        guard direction != tank.facing else { return }
        tank.facing = direction
        tank.bufferedDirection = nil
        tank.bufferedDirectionRemainingTicks = 0
        events.append(.tankTurned(entityID: tank.entityID, facing: direction))
    }

    private static func endSlide(_ tank: inout TankState) {
        tank.slideDirection = nil
        tank.slideMomentumSubunits = 0
        tank.slideIncrement = 0
    }

    private static func resolveTurnAndMovement(
        _ tank: inout TankState, field: ObstacleField,
        ruleset: MovementRuleset, events: inout [DomainEvent]
    ) {
        // Ice slide (§4.3): a budget set once when a tank rolling on ice
        // releases or changes direction; the facing follows input at once
        // while the body keeps sliding at the saved speed.
        let iceEnabled = ruleset.iceSlideDistanceSubunits > 0
        if tank.slideMomentumSubunits > 0, let sliding = tank.slideDirection {
            if !iceEnabled || !slidesOnIce(tank, terrain: field.terrain) || tank.movementIntent == sliding {
                endSlide(&tank) // off ice, gripping tracks, or driving on in the slide direction
            } else {
                if let intent = tank.movementIntent { turnFacing(&tank, to: intent, events: &events) }
                slideStep(&tank, direction: sliding, field: field, ruleset: ruleset)
                return
            }
        } else if iceEnabled, let last = tank.slideDirection, slidesOnIce(tank, terrain: field.terrain),
                  tank.movementIntent == nil || tank.movementIntent != last {
            tank.slideMomentumSubunits = ruleset.iceSlideDistanceSubunits
            tank.slideIncrement = increment(tank, ruleset: ruleset)
            if let intent = tank.movementIntent { turnFacing(&tank, to: intent, events: &events) }
            slideStep(&tank, direction: last, field: field, ruleset: ruleset)
            return
        }

        if let desired = tank.movementIntent, desired != tank.facing {
            attemptTurn(&tank, to: desired, live: true, field: field, ruleset: ruleset, events: &events)
        } else if let buffered = tank.bufferedDirection, tank.bufferedDirectionRemainingTicks > 0,
                  buffered != tank.facing {
            attemptTurn(&tank, to: buffered, live: false, field: field, ruleset: ruleset, events: &events)
        }

        let moving = tank.movementIntent != nil
            || (tank.bufferedDirection != nil && tank.bufferedDirectionRemainingTicks > 0)
        guard moving else {
            if !slidesOnIce(tank, terrain: field.terrain) { tank.slideDirection = nil }
            return
        }
        let whole = consumeTravel(&tank, increment: increment(tank, ruleset: ruleset))
        guard whole > 0 else { return }
        let moved = sweptMove(&tank, direction: tank.facing, distance: whole, field: field, ruleset: ruleset)
        if moved < whole { tank.movementAccumulator = 0 } // pressing into a wall banks nothing
        if iceEnabled, moved > 0, slidesOnIce(tank, terrain: field.terrain) {
            tank.slideDirection = tank.facing // momentum to spend on release
        } else if !slidesOnIce(tank, terrain: field.terrain) {
            tank.slideDirection = nil
        }
    }

    /// One tick of sliding at the saved speed, bounded by the budget; a
    /// block or leaving the ice ends the slide.
    private static func slideStep(_ tank: inout TankState, direction: Direction, field: ObstacleField,
                                  ruleset: MovementRuleset) {
        let step = min(tank.slideMomentumSubunits, consumeTravel(&tank, increment: tank.slideIncrement))
        guard step > 0 else { return }
        let moved = sweptMove(&tank, direction: direction, distance: step, field: field, ruleset: ruleset)
        tank.slideMomentumSubunits = moved < step ? 0 : tank.slideMomentumSubunits - moved
        if moved < step { tank.movementAccumulator = 0 }
        if tank.slideMomentumSubunits == 0 || !slidesOnIce(tank, terrain: field.terrain) { endSlide(&tank) }
    }

    /// Facing change with alignment assistance. Outcomes, in priority order:
    /// 1. reversal always turns; 2. a legal (possibly snap-assisted)
    /// perpendicular vector turns; 3. a tank that cannot keep rolling turns
    /// in place; 4. otherwise the request is buffered. A tank leaving water
    /// turns in place (no snap nudge along the water, §4.4).
    private static func attemptTurn(
        _ tank: inout TankState, to desired: Direction, live: Bool, field: ObstacleField,
        ruleset: MovementRuleset, events: inout [DomainEvent]
    ) {
        if !tank.facing.isPerpendicular(to: desired) || tank.leavingWater {
            turnFacing(&tank, to: desired, events: &events)
            return
        }
        if snapAssistedVectorIsFree(&tank, to: desired, field: field, ruleset: ruleset) {
            turnFacing(&tank, to: desired, events: &events)
            return
        }
        let canKeepRolling = probeIsFree(position: tank.positionSubunits, direction: tank.facing,
                                         field: field, ruleset: ruleset)
        if !canKeepRolling || !junctionWithinBufferTravel(tank, to: desired, field: field, ruleset: ruleset) {
            turnFacing(&tank, to: desired, events: &events)
            return
        }
        if live {
            tank.bufferedDirection = desired
            tank.bufferedDirectionRemainingTicks = ruleset.turnBufferTicks
        }
    }

    /// Whether a lane within buffered travel ahead would make the
    /// perpendicular turn legal.
    private static func junctionWithinBufferTravel(
        _ tank: TankState, to desired: Direction, field: ObstacleField, ruleset: MovementRuleset
    ) -> Bool {
        let lane = SpatialUnits.subunitsPerQuadrant
        let perTick = increment(tank, ruleset: ruleset) / MovementRuleset.accumulatorUnitsPerSubunit
        let reach = perTick * ruleset.turnBufferTicks + ruleset.alignmentAssistWindowSubunits
        let travelAxisIsX = tank.facing.vector.x != 0
        let coordinate = travelAxisIsX ? tank.positionSubunits.x : tank.positionSubunits.y
        let sign = tank.facing.vector.x + tank.facing.vector.y
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

    /// Perpendicular-turn legality with lane alignment: snaps the travel-axis
    /// coordinate to the nearest half-cell, then full-cell lane within the
    /// assist window; the nudge is swept. Mutates only when returning true.
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
                let nudge: Direction = travelAxisIsX ? (offset > 0 ? .right : .left) : (offset > 0 ? .down : .up)
                var probe = tank
                guard sweptMove(&probe, direction: nudge, distance: abs(offset),
                                field: field, ruleset: ruleset) == abs(offset) else { continue }
            }
            guard probeIsFree(position: candidate, direction: desired, field: field, ruleset: ruleset,
                              distance: turnProbeDistance(ruleset)) else { continue }
            tank.positionSubunits = candidate
            return true
        }
        return false
    }

    private static func probeIsFree(
        position: Vec2i, direction: Direction, field: ObstacleField, ruleset: MovementRuleset,
        distance: Int = 1
    ) -> Bool {
        let target = position + direction.vector * distance
        if leavesArena(from: position, to: target, arena: field.terrain.arena) { return false }
        let box = sweptBox(from: position, to: target, ruleset: ruleset)
        return !field.blocksTank(minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY)
    }

    /// The NOMINAL footprint stays inside the arena.
    static func leavesArena(from: Vec2i, to: Vec2i, arena: ArenaSpecification) -> Bool {
        let footprint = SpatialUnits.standardTankFootprintSubunits
        let minX = min(from.x, to.x), minY = min(from.y, to.y)
        let maxX = max(from.x, to.x) + footprint, maxY = max(from.y, to.y) + footprint
        return minX < 0 || minY < 0 || maxX > arena.widthSubunits || maxY > arena.heightSubunits
    }

    private static func turnProbeDistance(_ ruleset: MovementRuleset) -> Int {
        2 * ruleset.collisionInsetSubunits + 1
    }

    /// Swept axis-aligned movement: the largest free prefix of `distance`.
    /// A tank leaving water keeps a move only when it strictly reduces its
    /// water overlap (§4.4).
    @discardableResult
    private static func sweptMove(
        _ tank: inout TankState, direction: Direction, distance: Int,
        field: ObstacleField, ruleset: MovementRuleset
    ) -> Int {
        precondition(distance >= 0)
        guard distance > 0 else { return 0 }
        let start = tank.positionSubunits
        let vector = direction.vector
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
        if tank.leavingWater, lo > 0 {
            let end = Vec2i(x: start.x + vector.x * lo, y: start.y + vector.y * lo)
            let a = collisionBox(position: start, ruleset: ruleset), b = collisionBox(position: end, ruleset: ruleset)
            let before = field.terrain.waterOverlapArea(minX: a.minX, minY: a.minY, maxX: a.maxX, maxY: a.maxY)
            let after = field.terrain.waterOverlapArea(minX: b.minX, minY: b.minY, maxX: b.maxX, maxY: b.maxY)
            if after >= before { lo = 0 }
        }
        tank.positionSubunits = Vec2i(x: start.x + vector.x * lo, y: start.y + vector.y * lo)
        return lo
    }

    static func collisionBox(
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
