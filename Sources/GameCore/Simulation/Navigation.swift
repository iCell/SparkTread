/// Deterministic grid cost maps for enemy navigation (GAME_RULES §9.2): a
/// distance field over footprint ANCHOR cells (the top-left cell of the 2×2
/// footprint) from a goal set, by integer Dijkstra. White steel and the
/// base are impassable; brick and grey steel are passable at extra cost
/// only for families whose weapon opens them; water follows the equipment
/// profile; cells burning with fire that hurts enemies cost extra. Other
/// tanks are left to local steering.
///
/// Cost convention: `field[a]` is the total cost of the cells ENTERED after
/// `a` up to and including the goal.
enum Navigation {
    static let unreachable = Int.max / 4
    static let brickCost = 6
    static let whiteBrickCost = 12
    static let steelCost = 8
    static let fireCost = 4

    /// Which wall materials a family's weapon can open.
    struct DigAbility {
        var brick: Bool
        var steel: Bool
        func opens(_ kind: TerrainKind) -> Bool {
            if kind.isBrickFamily { return brick }
            if kind == .steel { return steel }
            return false
        }
    }

    struct Context {
        var dig: DigAbility
        var profile: TraversalProfile
        /// Row-major indices of cells burning with fire that hurts enemies.
        var burning: Set<Int>
        init(dig: DigAbility = DigAbility(brick: true, steel: false), profile: TraversalProfile = .normal,
             burning: Set<Int> = []) {
            self.dig = dig
            self.profile = profile
            self.burning = burning
        }
    }

    /// Cells holding a fire patch that hurts `hurtingTeam`.
    static func burningCells(_ world: WorldState, hurtingTeam: Int) -> Set<Int> {
        var cells = Set<Int>()
        for patch in world.fireHazards where patch.color.hurts(teamID: hurtingTeam) {
            cells.insert(patch.cell.y * world.arena.cellsWide + patch.cell.x)
        }
        return cells
    }

    static func isPassable(_ world: WorldState, anchor: Vec2i, context: Context = Context()) -> Bool {
        let arena = world.arena
        guard anchor.x >= 0, anchor.y >= 0, anchor.x + 1 < arena.cellsWide, anchor.y + 1 < arena.cellsHigh
        else { return false }
        for dy in 0..<2 {
            for dx in 0..<2 {
                let cell = world.terrain[anchor.x + dx, anchor.y + dy]
                if cell.kind == .base || cell.kind == .whiteSteel { return false }
                if cell.hasWall && !context.dig.opens(cell.kind) { return false }
                if cell.surfaceBlocksTank(profile: context.profile) { return false }
            }
        }
        if let base = world.base {
            let cell = SpatialUnits.subunitsPerCell
            let bx = base.topLeftSubunits.x / cell, by = base.topLeftSubunits.y / cell
            if anchor.x < bx + 2 && anchor.x + 2 > bx && anchor.y < by + 2 && anchor.y + 2 > by { return false }
        }
        return true
    }

    static func entryCost(_ world: WorldState, anchor: Vec2i, context: Context = Context()) -> Int {
        var cost = 1
        for dy in 0..<2 {
            for dx in 0..<2 {
                let x = anchor.x + dx, y = anchor.y + dy
                let cell = world.terrain[x, y]
                if cell.hasWall {
                    cost += cell.kind == .whiteBrick ? whiteBrickCost : cell.kind == .steel ? steelCost : brickCost
                }
                if context.burning.contains(y * world.arena.cellsWide + x) { cost += fireCost }
            }
        }
        return cost
    }

    /// Anchors from which the base can be shot: flush against a side and
    /// aligned with it; corner-touching anchors are the fallback.
    static func baseApproachGoals(_ world: WorldState, context: Context = Context()) -> [Vec2i] {
        guard let base = world.base else { return [] }
        let cell = SpatialUnits.subunitsPerCell
        let bx = base.topLeftSubunits.x / cell, by = base.topLeftSubunits.y / cell
        let aligned = [Vec2i(x: bx, y: by - 2), Vec2i(x: bx, y: by + 2),
                       Vec2i(x: bx - 2, y: by), Vec2i(x: bx + 2, y: by)]
            .filter { isPassable(world, anchor: $0, context: context) }
        if !aligned.isEmpty { return aligned }
        var goals: [Vec2i] = []
        for ay in (by - 2)...(by + 2) {
            for ax in (bx - 2)...(bx + 2) {
                let anchor = Vec2i(x: ax, y: ay)
                guard isPassable(world, anchor: anchor, context: context) else { continue }
                if ax - 1 < bx + 2 && ax + 3 > bx && ay - 1 < by + 2 && ay + 3 > by { goals.append(anchor) }
            }
        }
        return goals
    }

    static func anchor(of position: Vec2i) -> Vec2i {
        let cell = SpatialUnits.subunitsPerCell
        return Vec2i(x: (position.x + cell / 2) / cell, y: (position.y + cell / 2) / cell)
    }

    static func nearGoals(_ world: WorldState, around anchor: Vec2i, context: Context = Context()) -> [Vec2i] {
        var goals: [Vec2i] = []
        for dy in -1...1 {
            for dx in -1...1 {
                let candidate = Vec2i(x: anchor.x + dx, y: anchor.y + dy)
                if isPassable(world, anchor: candidate, context: context) { goals.append(candidate) }
            }
        }
        return goals
    }

    static func distanceField(_ world: WorldState, goals: [Vec2i], context: Context = Context()) -> [Int] {
        let width = world.arena.cellsWide, height = world.arena.cellsHigh
        var distance = [Int](repeating: unreachable, count: width * height)
        var heap = MinHeap()
        for goal in goals where isPassable(world, anchor: goal, context: context) {
            let index = goal.y * width + goal.x
            if distance[index] > 0 {
                distance[index] = 0
                heap.push(distance: 0, index: index)
            }
        }
        while let (d, index) = heap.pop() {
            guard d == distance[index] else { continue }
            let x = index % width, y = index / width
            let stepCost = entryCost(world, anchor: Vec2i(x: x, y: y), context: context)
            for direction in Direction.allCases {
                let next = Vec2i(x: x + direction.vector.x, y: y + direction.vector.y)
                guard isPassable(world, anchor: next, context: context) else { continue }
                let nextIndex = next.y * width + next.x
                let candidate = d + stepCost
                if candidate < distance[nextIndex] {
                    distance[nextIndex] = candidate
                    heap.push(distance: candidate, index: nextIndex)
                }
            }
        }
        return distance
    }

    static func isAtGoal(field: [Int], world: WorldState, anchor: Vec2i) -> Bool {
        let width = world.arena.cellsWide
        guard anchor.x >= 0, anchor.y >= 0, anchor.x < width, anchor.y < world.arena.cellsHigh else { return false }
        return field[anchor.y * width + anchor.x] == 0
    }

    static func descent(field: [Int], world: WorldState, anchor: Vec2i, preferred: Direction,
                        context: Context = Context()) -> [(direction: Direction, distance: Int)] {
        let width = world.arena.cellsWide
        guard anchor.x >= 0, anchor.y >= 0, anchor.x < width, anchor.y < world.arena.cellsHigh else { return [] }
        let here = field[anchor.y * width + anchor.x]
        guard here > 0 else { return [] }
        var options: [(Direction, Int)] = []
        let order = [preferred] + Direction.allCases.filter { $0 != preferred }
        for direction in order {
            let next = Vec2i(x: anchor.x + direction.vector.x, y: anchor.y + direction.vector.y)
            guard isPassable(world, anchor: next, context: context) else { continue }
            let remaining = field[next.y * width + next.x]
            guard remaining < unreachable else { continue }
            let total = entryCost(world, anchor: next, context: context) + remaining
            if total <= here || here >= unreachable { options.append((direction, total)) }
        }
        return options.sorted { $0.1 < $1.1 || ($0.1 == $1.1 && order.firstIndex(of: $0.0)! < order.firstIndex(of: $1.0)!) }
            .map { (direction: $0.0, distance: $0.1) }
    }

    /// Half-cell lane positions (index = (y/512) × lanesWide + x/512) a tank
    /// can reach from its nearest lane with its current equipment, over
    /// static terrain, current walls and the base — other tanks ignored
    /// (GAME_RULES §10.2).
    static func reachableLanes(_ world: WorldState, from tank: TankState, ruleset: MovementRuleset) -> Set<Int> {
        let lane = SpatialUnits.subunitsPerQuadrant
        let footprint = SpatialUnits.standardTankFootprintSubunits
        let inset = ruleset.collisionInsetSubunits
        let lanesWide = (world.arena.widthSubunits - footprint) / lane + 1
        let lanesHigh = (world.arena.heightSubunits - footprint) / lane + 1
        let profile = TraversalProfile(equipmentID: tank.equipmentID)
        let baseBox = world.base.map { ($0.topLeftSubunits.x, $0.topLeftSubunits.y, $0.sizeSubunits) }
        func free(minX: Int, minY: Int, maxX: Int, maxY: Int) -> Bool {
            if world.terrain.blocksTank(minX: minX, minY: minY, maxX: maxX, maxY: maxY, profile: profile) { return false }
            if let (bx, by, size) = baseBox, minX < bx + size && maxX > bx && minY < by + size && maxY > by { return false }
            return true
        }
        func boxFree(_ lx: Int, _ ly: Int) -> Bool {
            let x = lx * lane, y = ly * lane
            return free(minX: x + inset, minY: y + inset, maxX: x + footprint - inset, maxY: y + footprint - inset)
        }
        let sx = max(0, min(lanesWide - 1, (tank.positionSubunits.x + lane / 2) / lane))
        let sy = max(0, min(lanesHigh - 1, (tank.positionSubunits.y + lane / 2) / lane))
        var start: (Int, Int)?
        for (dx, dy) in [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)] {
            let lx = sx + dx, ly = sy + dy
            if lx >= 0, ly >= 0, lx < lanesWide, ly < lanesHigh, boxFree(lx, ly) { start = (lx, ly); break }
        }
        guard let start else { return [] }
        var seen: Set<Int> = [start.1 * lanesWide + start.0]
        var frontier = [start]
        while let (lx, ly) = frontier.popLast() {
            for direction in Direction.allCases {
                let nx = lx + direction.vector.x, ny = ly + direction.vector.y
                guard nx >= 0, ny >= 0, nx < lanesWide, ny < lanesHigh else { continue }
                let key = ny * lanesWide + nx
                guard !seen.contains(key) else { continue }
                let ax = lx * lane, ay = ly * lane, bx = nx * lane, by = ny * lane
                guard free(minX: min(ax, bx) + inset, minY: min(ay, by) + inset,
                           maxX: max(ax, bx) + footprint - inset, maxY: max(ay, by) + footprint - inset) else { continue }
                seen.insert(key)
                frontier.append((nx, ny))
            }
        }
        return seen
    }

    private struct MinHeap {
        private var items: [(distance: Int, index: Int)] = []
        private func less(_ a: (distance: Int, index: Int), _ b: (distance: Int, index: Int)) -> Bool {
            a.distance < b.distance || (a.distance == b.distance && a.index < b.index)
        }
        mutating func push(distance: Int, index: Int) {
            items.append((distance, index))
            var child = items.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard less(items[child], items[parent]) else { break }
                items.swapAt(child, parent)
                child = parent
            }
        }
        mutating func pop() -> (distance: Int, index: Int)? {
            guard !items.isEmpty else { return nil }
            let top = items[0]
            let last = items.removeLast()
            if !items.isEmpty {
                items[0] = last
                var parent = 0
                while true {
                    let left = 2 * parent + 1, right = left + 1
                    var smallest = parent
                    if left < items.count, less(items[left], items[smallest]) { smallest = left }
                    if right < items.count, less(items[right], items[smallest]) { smallest = right }
                    guard smallest != parent else { break }
                    items.swapAt(parent, smallest)
                    parent = smallest
                }
            }
            return top
        }
    }
}
