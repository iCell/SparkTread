import GameCore

/// A recorded input stream with periodic checksums (§18.1 replay goldens).
/// Sparse: ticks without commands are neutral input (ADR-0002). Codable via
/// the standard library only; file I/O belongs to adapters/tools.
public struct ReplayRecording: Codable, Equatable, Sendable {
    public struct TickCommands: Codable, Equatable, Sendable {
        public let tick: Int
        public let commands: [PlayerCommand]
    }

    public struct ChecksumPoint: Codable, Equatable, Sendable {
        public let tick: Int
        public let checksum: UInt64
    }

    public let seed: UInt64
    public let startChecksum: UInt64
    public private(set) var commandLog: [TickCommands]
    public private(set) var checksums: [ChecksumPoint]

    public init(seed: UInt64, startChecksum: UInt64) {
        self.seed = seed
        self.startChecksum = startChecksum
        self.commandLog = []
        self.checksums = []
    }

    public mutating func append(commands: [PlayerCommand], atTick tick: Int) {
        guard !commands.isEmpty else { return }
        commandLog.append(TickCommands(tick: tick, commands: commands))
    }

    public mutating func appendChecksum(tick: Int, checksum: UInt64) {
        checksums.append(ChecksumPoint(tick: tick, checksum: checksum))
    }
}

/// Deterministic playback: rebuilds the world from the fixture and re-feeds
/// the recorded command stream tick by tick.
public enum ReplayPlayer {
    /// Replays into a fresh fixture world for `tickCount` ticks and returns
    /// the checksum points at the recording's cadence.
    public static func replay(
        _ recording: ReplayRecording,
        ticks tickCount: Int,
        ruleset: MovementRuleset = .provisional
    ) -> [ReplayRecording.ChecksumPoint] {
        var world = MovementLabFixture.makeWorld()
        var points: [ReplayRecording.ChecksumPoint] = []
        var byTick: [Int: [PlayerCommand]] = [:]
        for entry in recording.commandLog { byTick[entry.tick] = entry.commands }
        for _ in 0..<tickCount {
            let commands = byTick[world.tick] ?? []
            Simulation.step(&world, commands: commands, ruleset: ruleset)
            if world.tick % MovementLabSession.checksumInterval == 0 {
                points.append(.init(tick: world.tick, checksum: world.checksum()))
            }
        }
        return points
    }
}
