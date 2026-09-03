import GameCore

/// The M1 Movement Lab: a fixed, deterministic arena fixture with one player
/// tank, plus the session workflow that feeds tick commands into the kernel.
/// This is a lab fixture, not an authored campaign stage.
public enum MovementLabFixture {
    public static let seed: UInt64 = 0x5041_524B_5452_4541 // stable lab seed

    /// Builds the lab world: steel border, brick corridor walls (2-cell
    /// corridors matching the 2×2-cell tank), a water pool and an ice patch
    /// (ice slide stays inert in M1), and the player tank on a spawn cell.
    public static func makeWorld() -> WorldState {
        let arena = ArenaSpecification.universal
        var terrain = TerrainGrid(arena: arena)

        for x in 0..<arena.cellsWide {
            terrain[x, 0] = TerrainCell(kind: .steel)
            terrain[x, arena.cellsHigh - 1] = TerrainCell(kind: .steel)
        }
        for y in 0..<arena.cellsHigh {
            terrain[0, y] = TerrainCell(kind: .steel)
            terrain[arena.cellsWide - 1, y] = TerrainCell(kind: .steel)
        }

        func brickColumn(x: Int, yRange: ClosedRange<Int>) {
            for y in yRange { terrain[x, y] = TerrainCell(kind: .brick); terrain[x + 1, y] = TerrainCell(kind: .brick) }
        }
        func brickRow(y: Int, xRange: ClosedRange<Int>) {
            for x in xRange { terrain[x, y] = TerrainCell(kind: .brick); terrain[x, y + 1] = TerrainCell(kind: .brick) }
        }
        // Corridor lattice: vertical spines with gaps, horizontal shelves,
        // laid out for the 56-cell width (ADR-0009).
        brickColumn(x: 9, yRange: 1...16)
        brickColumn(x: 19, yRange: 9...25)
        brickColumn(x: 29, yRange: 1...16)
        brickColumn(x: 45, yRange: 9...25)
        brickRow(y: 19, xRange: 33...42)
        brickRow(y: 5, xRange: 36...42)
        brickRow(y: 5, xRange: 49...53)

        for y in 9...12 { for x in 49...53 { terrain[x, y] = TerrainCell(kind: .water) } }
        for y in 21...24 { for x in 4...8 { terrain[x, y] = TerrainCell(kind: .ice) } }

        var world = WorldState(terrain: terrain, seed: seed)
        world.addPlayer(PlayerState(playerID: .one))
        let cell = SpatialUnits.subunitsPerCell
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3 * cell, y: 3 * cell), facing: .down)
        return world
    }
}

/// Session workflow: owns the world, ingests at most one command per player
/// per tick, records the command log for replay, and tracks the periodic
/// checksum cadence (every `checksumInterval` ticks).
public struct MovementLabSession: Sendable {
    public private(set) var world: WorldState
    public private(set) var recording: ReplayRecording
    public let ruleset: MovementRuleset
    public static let checksumInterval = 60

    public init(world: WorldState = MovementLabFixture.makeWorld(),
                ruleset: MovementRuleset = .provisional) {
        self.world = world
        self.ruleset = ruleset
        self.recording = ReplayRecording(seed: MovementLabFixture.seed, startChecksum: world.checksum())
    }

    /// Advances one tick with the local player's held direction.
    @discardableResult
    public mutating func advance(holding direction: Direction?) -> [DomainEvent] {
        let command = PlayerCommand(playerID: .one, targetTick: world.tick, moveDirection: direction)
        return advance(commands: [command])
    }

    @discardableResult
    public mutating func advance(commands: [PlayerCommand]) -> [DomainEvent] {
        recording.append(commands: commands, atTick: world.tick)
        let events = Simulation.step(&world, commands: commands, ruleset: ruleset)
        if world.tick % Self.checksumInterval == 0 {
            recording.appendChecksum(tick: world.tick, checksum: world.checksum())
        }
        return events
    }
}
