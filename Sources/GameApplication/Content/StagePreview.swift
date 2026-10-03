import GameCore

/// A stage's authored map reduced to one value per cell, for presentation
/// that wants to SHOW a stage without building a world — the select screen
/// draws each card's background from this (2026-10-03).
///
/// It replays the terrain layers exactly the way the builder stacks them, so
/// what a card shows is the map that will load, not a drawing of it. Pure
/// content-layer logic: no Foundation, no rendering, no colours. The palette
/// is the adapter's business.
public enum StagePreview {
    public enum Cell: UInt8, Sendable, Equatable {
        case ground, brick, whiteBrick, steel, whiteSteel, water, ice, foliage
        /// The base footprint, and the two kinds of spawn, which are not
        /// terrain but are most of what makes a map recognisable.
        case base, playerSpawn, enemySpawn
    }

    public struct Map: Sendable, Equatable {
        public let width: Int
        public let height: Int
        /// Row-major, `width` entries per row.
        public let cells: [Cell]
        public let themeID: String

        public subscript(x: Int, y: Int) -> Cell {
            guard x >= 0, x < width, y >= 0, y < height else { return .ground }
            return cells[y * width + x]
        }
    }

    public static func map(of def: StageDefinition) -> Map {
        let arena = ArenaSpecification.universal
        var cells = [Cell](repeating: .ground, count: arena.cellsWide * arena.cellsHigh)
        for y in 0..<arena.cellsHigh {
            for x in 0..<arena.cellsWide {
                cells[y * arena.cellsWide + x] = cell(for: StageValidator.authoredCell(def, at: [x, y]).kind)
            }
        }
        // Markers last: a spawn or the base reads over whatever it stands on.
        func mark(_ corner: [Int], _ value: Cell) {
            guard corner.count == 2 else { return }
            for dy in 0..<2 {
                for dx in 0..<2 {
                    let x = corner[0] + dx, y = corner[1] + dy
                    guard x >= 0, x < arena.cellsWide, y >= 0, y < arena.cellsHigh else { continue }
                    cells[y * arena.cellsWide + x] = value
                }
            }
        }
        for spawn in def.enemySpawns { mark(spawn, .enemySpawn) }
        if let player = def.playerSpawnsByID["1"] { mark(player, .playerSpawn) }
        mark(def.baseSpawn, .base)
        return Map(width: arena.cellsWide, height: arena.cellsHigh,
                   cells: cells, themeID: def.themeID)
    }

    private static func cell(for kind: TerrainKind) -> Cell {
        switch kind {
        case .ground: .ground
        case .brick: .brick
        case .whiteBrick: .whiteBrick
        case .steel: .steel
        case .whiteSteel: .whiteSteel
        case .water: .water
        case .ice: .ice
        case .foliage: .foliage
        case .base: .base
        }
    }
}
