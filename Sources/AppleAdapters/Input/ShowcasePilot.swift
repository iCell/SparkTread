import GameCore

/// The store-capture autopilot (`SPARKTREAD_PILOT`, owner 2026-10-09: App
/// Store screenshots and a preview video need real play, and nobody can
/// play inside a simulator recording). It is an INPUT source, like the
/// touch controls: it reads the world and decides what to hold and press;
/// no rule lives here, the simulation cannot tell it from a thumb, and the
/// player's own input overrides it. Never enabled outside capture runs.
///
/// The policy is deliberately plain: shoot an enemy that is lined up,
/// otherwise collect a pickup, otherwise close the smaller gap to the
/// nearest enemy; shoot whatever wall stops the tank, then detour sideways;
/// never fire along a line that crosses the own base.
struct ShowcasePilot {
    struct Decision: Equatable {
        var direction: Direction?
        var normalFire: Bool
        var specialFire: Bool
        static let idle = Decision(direction: nil, normalFire: false, specialFire: false)
    }

    private static let cell = SpatialUnits.subunitsPerCell
    /// Lined up: centres within half a cell on one axis.
    private static let lineUp = SpatialUnits.subunitsPerCell / 2
    /// Lined-up enemies farther than this are not worth turning for.
    private static let range = 22 * SpatialUnits.subunitsPerCell

    private var lastPosition: Vec2i?
    private var stillTicks = 0
    private var detour: Direction?
    private var detourTicks = 0
    private var detourCount = 0

    mutating func decide(world: WorldState) -> Decision {
        guard let id = world.player(.one)?.tankEntityID, let me = world.tank(entityID: id) else {
            lastPosition = nil; stillTicks = 0; detourTicks = 0
            return .idle
        }
        let tick = world.tick
        let centre = Self.centre(of: me.positionSubunits)
        if lastPosition == me.positionSubunits { stillTicks += 1 } else { stillTicks = 0 }
        lastPosition = me.positionSubunits

        if detourTicks > 0, let detour {
            detourTicks -= 1
            return Decision(direction: detour, normalFire: tick % 10 == 0 && safe(detour, from: centre, world: world),
                            specialFire: false)
        }

        let enemies = world.tanks.filter { $0.teamID != me.teamID }
            .map { Self.centre(of: $0.positionSubunits) }
            .sorted { distance(centre, $0) < distance(centre, $1) }

        // 1. An enemy lined up, in range, with no steel between: face it
        // and fire everything (brick in the way just gets shot through).
        let hasAmmo = (world.player(.one)?.specialAmmoByWeapon[me.specialWeaponID] ?? 0) > 0
        for enemy in enemies where distance(centre, enemy) <= Self.range {
            let dx = enemy.x - centre.x, dy = enemy.y - centre.y
            var facing: Direction?
            if abs(dx) <= Self.lineUp { facing = dy < 0 ? .up : .down }
            else if abs(dy) <= Self.lineUp { facing = dx < 0 ? .left : .right }
            guard let facing, safe(facing, from: centre, world: world),
                  !steelBetween(centre, enemy, along: facing, world: world) else { continue }
            // Pulses spaced past the normal cooldown, the special only at
            // fighting range: a full shell cap would only click.
            return Decision(direction: facing, normalFire: tick % 20 == 0,
                            specialFire: hasAmmo && distance(centre, enemy) <= 14 * Self.cell)
        }

        // 2. Otherwise a pickup, else the nearest enemy, else hold the line.
        let pickup = world.pickups.map { Vec2i(x: $0.cell.x * Self.cell + Self.cell, y: $0.cell.y * Self.cell + Self.cell) }
            .min { distance(centre, $0) < distance(centre, $1) }
        guard let goal = pickup ?? enemies.first else { return .idle }
        let dx = goal.x - centre.x, dy = goal.y - centre.y
        // Close the smaller gap first: that is what lines a shot up.
        let horizontal = abs(dx) > Self.lineUp && (abs(dx) <= abs(dy) || abs(dy) <= Self.lineUp)
        let wanted: Direction = horizontal ? (dx < 0 ? .left : .right) : (dy < 0 ? .up : .down)

        // Stopped by something: shoot it for a moment (brick gives way),
        // then go round it sideways, alternating sides.
        if stillTicks >= 70 || (stillTicks >= 6 && steelAhead(of: me.positionSubunits, facing: wanted, world: world)) {
            stillTicks = 0
            detourCount += 1
            let sideways: [Direction] = wanted == .up || wanted == .down ? [.left, .right] : [.up, .down]
            detour = sideways[detourCount % 2]
            detourTicks = 50
            return Decision(direction: detour, normalFire: false, specialFire: false)
        }
        let blocked = stillTicks >= 10
        let fire = (blocked || tick % 24 == 0) && safe(wanted, from: centre, world: world)
            && !steelAhead(of: me.positionSubunits, facing: wanted, world: world)
        return Decision(direction: wanted, normalFire: fire && tick % 20 == 0, specialFire: false)
    }

    /// Steel (which only the AP round opens, one cell a shot) on the shot's
    /// line between the two centres: not worth the rounds.
    private func steelBetween(_ from: Vec2i, _ to: Vec2i, along direction: Direction, world: WorldState) -> Bool {
        let cell = Self.cell, terrain = world.terrain
        let vertical = direction == .up || direction == .down
        let lanes = vertical ? Set([(from.x - 1) / cell, from.x / cell]) : Set([(from.y - 1) / cell, from.y / cell])
        let a = vertical ? from.y / cell : from.x / cell, b = vertical ? to.y / cell : to.x / cell
        for step in min(a, b)...max(a, b) {
            for lane in lanes {
                let (x, y) = vertical ? (lane, step) : (step, lane)
                if terrain.isInside(cellX: x, cellY: y), terrain[x, y].kind.isSteelFamily { return true }
            }
        }
        return false
    }

    /// Steel in the row or column right in front of the tank.
    private func steelAhead(of topLeft: Vec2i, facing direction: Direction, world: WorldState) -> Bool {
        let cell = Self.cell, size = SpatialUnits.standardTankFootprintSubunits, terrain = world.terrain
        let cells: [(Int, Int)]
        switch direction {
        case .up: cells = [(topLeft.x / cell, (topLeft.y - 1) / cell), ((topLeft.x + size - 1) / cell, (topLeft.y - 1) / cell)]
        case .down: cells = [(topLeft.x / cell, (topLeft.y + size) / cell), ((topLeft.x + size - 1) / cell, (topLeft.y + size) / cell)]
        case .left: cells = [((topLeft.x - 1) / cell, topLeft.y / cell), ((topLeft.x - 1) / cell, (topLeft.y + size - 1) / cell)]
        case .right: cells = [((topLeft.x + size) / cell, topLeft.y / cell), ((topLeft.x + size) / cell, (topLeft.y + size - 1) / cell)]
        }
        return cells.contains { terrain.isInside(cellX: $0.0, cellY: $0.1) && terrain[$0.0, $0.1].kind.isSteelFamily }
    }

    private static func centre(of topLeft: Vec2i) -> Vec2i {
        Vec2i(x: topLeft.x + cell, y: topLeft.y + cell)
    }

    private func distance(_ a: Vec2i, _ b: Vec2i) -> Int { abs(a.x - b.x) + abs(a.y - b.y) }

    /// False when a shot fired that way would run into the own base.
    private func safe(_ direction: Direction, from centre: Vec2i, world: WorldState) -> Bool {
        guard let base = world.base else { return true }
        let size = base.sizeSubunits, b = base.topLeftSubunits
        let margin = Self.cell
        switch direction {
        case .down: return !(centre.x > b.x - margin && centre.x < b.x + size + margin && b.y > centre.y)
        case .up: return !(centre.x > b.x - margin && centre.x < b.x + size + margin && b.y + size < centre.y)
        case .left: return !(centre.y > b.y - margin && centre.y < b.y + size + margin && b.x + size < centre.x)
        case .right: return !(centre.y > b.y - margin && centre.y < b.y + size + margin && b.x > centre.x)
        }
    }
}
