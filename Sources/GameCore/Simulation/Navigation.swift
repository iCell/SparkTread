/// Deterministic grid cost maps for enemy navigation (§10.4): a distance
/// field over footprint ANCHOR cells (the top-left cell of the 2×2 tank
/// footprint) from a goal set, computed with integer Dijkstra. Steel, water
/// and the base structure are impassable; brick is passable at extra cost
/// for families that can dig (BreakTerrain with a brick-damaging weapon)
/// and impassable for those that cannot (flame), so a walled-in base still
/// attracts a siege instead of leaving enemies to wander. Other tanks are
/// dynamic and are left to local steering.
///
/// Cost convention: `field[a]` is the total cost of the cells ENTERED after
/// `a` up to and including the goal (a goal's own entry cost counts; the
/// start anchor's does not). Forward choice therefore compares
/// `entryCost(next) + field[next]`, and the reverse relaxation charges the
/// cost of the node being expanded FROM.
enum Navigation {
    static let unreachable = Int.max / 4
    /// Cost added per brick cell inside an anchor's footprint (a brick cell
    /// takes two aligned shots to clear).
    static let brickCost = 6

    /// Whether a footprint anchored at `anchor` fits the static world;
    /// brick counts as passable only for a family that can dig.
    static func isPassable(_ world: WorldState, anchor: Vec2i, canDig: Bool = true,
                           profile: TraversalProfile = .normal) -> Bool {
        let arena = world.arena
        guard anchor.x >= 0, anchor.y >= 0, anchor.x + 1 < arena.cellsWide, anchor.y + 1 < arena.cellsHigh
        else { return false }
        for dy in 0..<2 {
            for dx in 0..<2 {
                let kind = world.terrain[anchor.x + dx, anchor.y + dy].kind
                if kind == .steel || kind == .base { return false }
                if kind == .water && profile != .amphibious { return false } // ADR-0016
                if kind == .brick && !canDig { return false }
            }
        }
        if let base = world.base {
            let cell = SpatialUnits.subunitsPerCell
            let bx = base.topLeftSubunits.x / cell, by = base.topLeftSubunits.y / cell
            if anchor.x < bx + 2 && anchor.x + 2 > bx && anchor.y < by + 2 && anchor.y + 2 > by { return false }
        }
        return true
    }

    /// Cost of entering an anchor: one step plus the brick it must dig.
    static func entryCost(_ world: WorldState, anchor: Vec2i) -> Int {
        var bricks = 0
        for dy in 0..<2 {
            for dx in 0..<2 where world.terrain[anchor.x + dx, anchor.y + dy].kind == .brick {
                bricks += 1
            }
        }
        return 1 + brickCost * bricks
    }

    /// Anchors from which the base can be shot: the four positions flush
    /// against a side and aligned with the base center (a shot from there
    /// hits). Corner-touching anchors are the fallback when no aligned one
    /// is passable (a base against a border wall).
    static func baseApproachGoals(_ world: WorldState, canDig: Bool = true,
                                  profile: TraversalProfile = .normal) -> [Vec2i] {
        guard let base = world.base else { return [] }
        let cell = SpatialUnits.subunitsPerCell
        let bx = base.topLeftSubunits.x / cell, by = base.topLeftSubunits.y / cell
        let aligned = [Vec2i(x: bx, y: by - 2), Vec2i(x: bx, y: by + 2),
                       Vec2i(x: bx - 2, y: by), Vec2i(x: bx + 2, y: by)]
            .filter { isPassable(world, anchor: $0, canDig: canDig, profile: profile) }
        if !aligned.isEmpty { return aligned }
        var goals: [Vec2i] = []
        for ay in (by - 2)...(by + 2) {
            for ax in (bx - 2)...(bx + 2) {
                let anchor = Vec2i(x: ax, y: ay)
                guard isPassable(world, anchor: anchor, canDig: canDig, profile: profile) else { continue }
                // Touching: the expanded footprint intersects the base cells.
                if ax - 1 < bx + 2 && ax + 3 > bx && ay - 1 < by + 2 && ay + 3 > by {
                    goals.append(anchor)
                }
            }
        }
        return goals
    }

    /// The anchor cell nearest to a tank's top-left position.
    static func anchor(of position: Vec2i) -> Vec2i {
        let cell = SpatialUnits.subunitsPerCell
        return Vec2i(x: (position.x + cell / 2) / cell, y: (position.y + cell / 2) / cell)
    }

    /// Anchors within one cell of a tank's anchor (a shooting neighbourhood).
    static func nearGoals(_ world: WorldState, around anchor: Vec2i, canDig: Bool = true,
                          profile: TraversalProfile = .normal) -> [Vec2i] {
        var goals: [Vec2i] = []
        for dy in -1...1 {
            for dx in -1...1 {
                let candidate = Vec2i(x: anchor.x + dx, y: anchor.y + dy)
                if isPassable(world, anchor: candidate, canDig: canDig, profile: profile) { goals.append(candidate) }
            }
        }
        return goals
    }

    /// Multi-source Dijkstra from the goal set; index = y * cellsWide + x.
    /// Goals hold 0; expanding from `current` into a predecessor `next`
    /// charges `entryCost(current)` — the cell the forward walker enters
    /// after `next` — so a goal's own brick is priced like any other cell.
    static func distanceField(_ world: WorldState, goals: [Vec2i], canDig: Bool = true,
                              profile: TraversalProfile = .normal) -> [Int] {
        let width = world.arena.cellsWide, height = world.arena.cellsHigh
        var distance = [Int](repeating: unreachable, count: width * height)
        var heap = MinHeap()
        for goal in goals where isPassable(world, anchor: goal, canDig: canDig, profile: profile) {
            let index = goal.y * width + goal.x
            if distance[index] > 0 {
                distance[index] = 0
                heap.push(distance: 0, index: index)
            }
        }
        while let (d, index) = heap.pop() {
            guard d == distance[index] else { continue } // stale entry
            let x = index % width, y = index / width
            let stepCost = entryCost(world, anchor: Vec2i(x: x, y: y))
            for direction in Direction.allCases {
                let next = Vec2i(x: x + direction.vector.x, y: y + direction.vector.y)
                guard isPassable(world, anchor: next, canDig: canDig, profile: profile) else { continue }
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

    /// Whether `anchor` is a goal of the field (remaining cost zero).
    static func isAtGoal(field: [Int], world: WorldState, anchor: Vec2i) -> Bool {
        let width = world.arena.cellsWide
        guard anchor.x >= 0, anchor.y >= 0, anchor.x < width, anchor.y < world.arena.cellsHigh else { return false }
        return field[anchor.y * width + anchor.x] == 0
    }

    /// The optimal next steps from `anchor`: neighbours whose
    /// `entryCost(next) + field[next]` does not exceed the remaining cost
    /// here, ordered by that total then by a fixed tie order (`preferred`
    /// first, then up/right/down/left). Empty at the goal or when nothing
    /// is reachable.
    static func descent(field: [Int], world: WorldState, anchor: Vec2i,
                        preferred: Direction, canDig: Bool = true,
                        profile: TraversalProfile = .normal) -> [(direction: Direction, distance: Int)] {
        let width = world.arena.cellsWide
        guard anchor.x >= 0, anchor.y >= 0, anchor.x < width, anchor.y < world.arena.cellsHigh else { return [] }
        let here = field[anchor.y * width + anchor.x]
        guard here > 0 else { return [] }
        var options: [(Direction, Int)] = []
        let order = [preferred] + Direction.allCases.filter { $0 != preferred }
        for direction in order {
            let next = Vec2i(x: anchor.x + direction.vector.x, y: anchor.y + direction.vector.y)
            guard isPassable(world, anchor: next, canDig: canDig, profile: profile) else { continue }
            let remaining = field[next.y * width + next.x]
            guard remaining < unreachable else { continue }
            let total = entryCost(world, anchor: next) + remaining
            if total <= here || here >= unreachable { options.append((direction, total)) }
        }
        return options.sorted { $0.1 < $1.1 || ($0.1 == $1.1 && order.firstIndex(of: $0.0)! < order.firstIndex(of: $1.0)!) }
            .map { (direction: $0.0, distance: $0.1) }
    }

    /// A tiny binary min-heap of (distance, index) pairs; ties by index so
    /// the traversal order is fully deterministic.
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
