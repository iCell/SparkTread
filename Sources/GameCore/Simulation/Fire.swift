/// Ground fire (GAME_RULES §7): flame landing, patches keyed by source,
/// per-victim burn cadence, foliage spread and burn-out.
enum Fire {
    // MARK: - Landing (§7.1)

    /// Lands a fire shell's flames: a 2×2 whole-cell footprint around the
    /// shell centre, conservatively clipped (walls, base, water, ice, out of
    /// bounds) and, after a wall/base contact, kept on the incident side of
    /// the contact face.
    static func landFlame(_ world: inout WorldState, at p: Vec2i, halfPlane: (Direction, Int)?,
                          projectile: ProjectileState, weapons: WeaponRuleset, events: inout [DomainEvent]) {
        let cell = SpatialUnits.subunitsPerCell
        // Nearest integer of (p − 1024) / 1024, halves to the smaller.
        func anchor(_ v: Int) -> Int { Combat.floorDiv(v - cell + cell / 2 - 1, cell) }
        let nx = anchor(p.x), ny = anchor(p.y)
        for (cx, cy) in [(nx, ny), (nx + 1, ny), (nx, ny + 1), (nx + 1, ny + 1)] {
            guard canBurn(world, cellX: cx, cellY: cy) else { continue }
            if let (direction, face) = halfPlane {
                let inside = switch direction {
                case .right: (cx + 1) * cell <= face
                case .left: cx * cell >= face
                case .down: (cy + 1) * cell <= face
                case .up: cy * cell >= face
                }
                guard inside else { continue }
            }
            addFlame(&world, cell: Vec2i(x: cx, y: cy), color: FireColor.of(sourceTeam: projectile.teamID),
                     sourceKey: projectile.ownerEntityID, ownerPlayerID: projectile.ownerPlayerID,
                     weapons: weapons, events: &events)
        }
    }

    /// Whether a cell can hold ground fire: inside, no wall quadrant, not the
    /// base, and neither water nor ice underneath.
    static func canBurn(_ world: WorldState, cellX: Int, cellY: Int) -> Bool {
        guard world.terrain.isInside(cellX: cellX, cellY: cellY) else { return false }
        let c = world.terrain[cellX, cellY]
        if c.kind.isSolidStructure || c.isWaterOrIce { return false }
        if let base = world.base {
            let size = SpatialUnits.subunitsPerCell
            let b = base.topLeftSubunits
            let minX = cellX * size, minY = cellY * size
            if minX < b.x + base.sizeSubunits && minX + size > b.x && minY < b.y + base.sizeSubunits && minY + size > b.y {
                return false
            }
        }
        return true
    }

    /// Creates a patch, or refreshes the same (cell, color, source) patch to
    /// the longer remaining life; ignites foliage.
    static func addFlame(_ world: inout WorldState, cell: Vec2i, color: FireColor, sourceKey: Int,
                         ownerPlayerID: PlayerID?, weapons: WeaponRuleset,
                         lifetime: Int? = nil, events: inout [DomainEvent]) {
        let life = lifetime ?? weapons.firePatchLifetimeTicks
        if let index = world.fireHazards.firstIndex(where: { $0.cell == cell && $0.color == color && $0.sourceKey == sourceKey }) {
            world.fireHazards[index].lifetimeRemainingTicks = max(world.fireHazards[index].lifetimeRemainingTicks, life)
        } else {
            world.fireHazards.append(FireHazardState(
                entityID: world.claimEntityID(), cell: cell, color: color, sourceKey: sourceKey,
                ownerPlayerID: ownerPlayerID, createdTick: world.tick, lifetimeRemainingTicks: life))
            events.append(.fireStarted(cellX: cell.x, cellY: cell.y, color: color))
        }
        var terrainCell = world.terrain[cell.x, cell.y]
        if terrainCell.kind == .foliage, terrainCell.ignitedAtTick == nil {
            terrainCell.ignitedAtTick = world.tick
            world.terrain[cell.x, cell.y] = terrainCell
        }
    }

    // MARK: - Step 6

    static func resolve(_ world: inout WorldState, weapons: WeaponRuleset, events: inout [DomainEvent]) {
        spreadFoliage(&world, weapons: weapons, events: &events)
        burnTanks(&world, weapons: weapons, events: &events)
        burnBase(&world, weapons: weapons, events: &events)
        burnOutFoliage(&world, events: &events)
    }

    /// §7.4: a foliage cell spreads once, `foliageSpreadDelayTicks` after it
    /// ignited, carrying every source that burned there before this tick to
    /// its four neighbours. Cells scan row-major; patches by entity id.
    private static func spreadFoliage(_ world: inout WorldState, weapons: WeaponRuleset, events: inout [DomainEvent]) {
        let width = world.arena.cellsWide
        var spreading: [Vec2i] = []
        for (index, cell) in world.terrain.cells.enumerated()
        where cell.kind == .foliage && !cell.hasSpread && cell.ignitedAtTick.map({ $0 + weapons.foliageSpreadDelayTicks }) == world.tick {
            spreading.append(Vec2i(x: index % width, y: index / width))
        }
        guard !spreading.isEmpty else { return }
        let existing = world.fireHazards.filter { $0.createdTick < world.tick }
        for origin in spreading {
            world.terrain[origin.x, origin.y].hasSpread = true
            let sources = existing.filter { $0.cell == origin }
            for (dx, dy) in [(0, -1), (1, 0), (0, 1), (-1, 0)] {
                let nx = origin.x + dx, ny = origin.y + dy
                guard canBurn(world, cellX: nx, cellY: ny), world.terrain[nx, ny].kind == .foliage else { continue }
                for source in sources {
                    addFlame(&world, cell: Vec2i(x: nx, y: ny), color: source.color, sourceKey: source.sourceKey,
                             ownerPlayerID: source.ownerPlayerID, weapons: weapons, events: &events)
                }
            }
        }
    }

    /// The patch that owns a burn: created first, then lowest entity id.
    private static func earliest(_ patches: [FireHazardState]) -> FireHazardState? {
        patches.min { ($0.createdTick, $0.entityID) < ($1.createdTick, $1.entityID) }
    }

    private static func burnTanks(_ world: inout WorldState, weapons: WeaponRuleset, events: inout [DomainEvent]) {
        guard !world.fireHazards.isEmpty else { return }
        let size = SpatialUnits.subunitsPerCell
        let footprint = SpatialUnits.standardTankFootprintSubunits
        for index in world.tanks.indices {
            let tank = world.tanks[index]
            guard Combat.isAlive(tank), !Combat.isProtected(tank), world.tick >= tank.nextFireDamageTick else { continue }
            let p = tank.positionSubunits
            let touching = world.fireHazards.filter { patch in
                let minX = patch.cell.x * size, minY = patch.cell.y * size
                return patch.color.hurts(teamID: tank.teamID)
                    && minX < p.x + footprint && minX + size > p.x && minY < p.y + footprint && minY + size > p.y
            }
            guard let source = earliest(touching) else { continue }
            let landed = Combat.applyTankDamage(
                &world, tankIndex: index, damage: 1,
                source: Combat.DamageSource(weaponID: "fire", ownerPlayerID: source.ownerPlayerID, explosive: false),
                events: &events)
            if landed { world.tanks[index].nextFireDamageTick = world.tick + weapons.fireDamageIntervalTicks }
        }
    }

    /// The base burns from patches on it or sharing a positive-length edge
    /// with it; sources filter by owner, not by colour (§7.3).
    private static func burnBase(_ world: inout WorldState, weapons: WeaponRuleset, events: inout [DomainEvent]) {
        guard let base = world.base, base.durability > 0, base.shieldRemainingTicks == 0,
              world.tick >= base.nextFireDamageTick, !world.fireHazards.isEmpty else { return }
        let cell = SpatialUnits.subunitsPerCell
        let bx = base.topLeftSubunits.x / cell, by = base.topLeftSubunits.y / cell
        let touching = world.fireHazards.filter { patch in
            let c = patch.cell
            let overlapsColumns = c.x >= bx && c.x <= bx + 1
            let overlapsRows = c.y >= by && c.y <= by + 1
            let geometric = (overlapsColumns && c.y >= by - 1 && c.y <= by + 2)
                || (overlapsRows && c.x >= bx - 1 && c.x <= bx + 2)
            guard geometric else { return false }
            if patch.isEnvironment || patch.color == .orange { return true }
            return weapons.alliedBaseDamage
        }
        guard let source = earliest(touching) else { return }
        let team: Int? = source.isEnvironment ? nil : (source.color == .yellow ? 1 : 2)
        if Combat.applyBaseHit(&world, sourceTeam: team, weapons: weapons, events: &events) {
            world.base?.nextFireDamageTick = world.tick + weapons.fireDamageIntervalTicks
        }
    }

    /// Foliage that has burned and holds no flame any more is gone.
    private static func burnOutFoliage(_ world: inout WorldState, events: inout [DomainEvent]) {
        let width = world.arena.cellsWide
        var burning = Set<Int>()
        for patch in world.fireHazards { burning.insert(patch.cell.y * width + patch.cell.x) }
        for (index, cell) in world.terrain.cells.enumerated()
        where cell.kind == .foliage && cell.ignitedAtTick != nil && !burning.contains(index) {
            let cx = index % width, cy = index / width
            world.terrain[cx, cy] = cell.revealedSurface
            events.append(.terrainChanged(cellX: cx, cellY: cy, quadrantMask: 0))
        }
    }
}

extension WorldState {
    /// Places red stage fire (GAME_RULES §7.3) at build time; `sourceKey`
    /// must be negative. Cells that cannot burn are skipped.
    public mutating func addEnvironmentFire(cell: Vec2i, sourceKey: Int, lifetimeTicks: Int) {
        precondition(sourceKey < 0, "environment fire uses negative source keys")
        guard Fire.canBurn(self, cellX: cell.x, cellY: cell.y) else { return }
        var events: [DomainEvent] = []
        Fire.addFlame(&self, cell: cell, color: .red, sourceKey: sourceKey, ownerPlayerID: nil,
                      weapons: .provisional, lifetime: lifetimeTicks, events: &events)
    }
}
