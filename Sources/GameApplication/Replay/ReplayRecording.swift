import GameCore

/// A recorded input stream with periodic checksums (§18.1 replay goldens,
/// §16.3). Self-contained: the initial world snapshot and the exact rulesets
/// the session stepped with travel inside the recording, so any session —
/// lab fixture, authored stage, a world already at a nonzero tick — replays
/// from its own start. Sparse: ticks without commands are neutral input
/// (ADR-0002). Codable via the standard library only; file I/O belongs to
/// adapters/tools.
public struct ReplayRecording: Codable, Equatable, Sendable {
    public struct TickCommands: Codable, Equatable, Sendable {
        public let tick: Int
        public let commands: [PlayerCommand]
    }

    public struct ChecksumPoint: Codable, Equatable, Sendable {
        public let tick: Int
        public let checksum: UInt64
    }

    /// Format 3 (2026-09-10): the embedded rulesets gained
    /// `PickupRuleset.dropsSpawnAtRandomCells`, and the EnemyBrain moved to
    /// cost-field navigation with new base-focus values. Earlier recordings
    /// (format 2) embed a rules shape and an AI this build no longer
    /// reproduces, so they are rejected as `unsupportedFormat` rather than
    /// replayed into a different game.
    ///
    /// Compatibility POLICY (not an enforced build-identity check): a
    /// recording carries a format number, not a build revision. Any change
    /// that alters simulation behaviour for the same inputs — rules shape,
    /// AI, contact resolution — must bump this number so the boundary is
    /// detected; a behaviour change shipped without a bump is undetectable
    /// here and would surface only as a checksum mismatch during playback.
    public static let currentFormatVersion = 3

    public let formatVersion: Int
    public let initialWorld: WorldState
    public let movement: MovementRuleset
    public let weapons: WeaponRuleset
    public let pickups: PickupRuleset
    public let startChecksum: UInt64
    public private(set) var commandLog: [TickCommands]
    public private(set) var checksums: [ChecksumPoint]

    public init(initialWorld: WorldState,
                movement: MovementRuleset = .provisional,
                weapons: WeaponRuleset = .provisional,
                pickups: PickupRuleset = .provisional) {
        self.formatVersion = Self.currentFormatVersion
        self.initialWorld = initialWorld
        self.movement = movement
        self.weapons = weapons
        self.pickups = pickups
        self.startChecksum = initialWorld.checksum()
        self.commandLog = []
        self.checksums = []
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, initialWorld, movement, weapons, pickups, startChecksum, commandLog, checksums
    }

    /// Decoding reads the format number FIRST and rejects a foreign format
    /// before touching any other field, so an earlier-format file — whose
    /// rules shape lacks keys this build requires — is reported as
    /// `ReplayPlayer.ReplayError.unsupportedFormat` at the import boundary
    /// rather than as a schema error about whichever key was added last.
    /// This is the one public contract for old files, whatever decoder
    /// entry point reads them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .formatVersion)
        guard version == Self.currentFormatVersion else {
            throw ReplayPlayer.ReplayError.unsupportedFormat(version)
        }
        formatVersion = version
        initialWorld = try container.decode(WorldState.self, forKey: .initialWorld)
        movement = try container.decode(MovementRuleset.self, forKey: .movement)
        weapons = try container.decode(WeaponRuleset.self, forKey: .weapons)
        pickups = try container.decode(PickupRuleset.self, forKey: .pickups)
        startChecksum = try container.decode(UInt64.self, forKey: .startChecksum)
        commandLog = try container.decode([TickCommands].self, forKey: .commandLog)
        checksums = try container.decode([ChecksumPoint].self, forKey: .checksums)
    }

    public var initialTick: Int { initialWorld.tick }

    public mutating func append(commands: [PlayerCommand], atTick tick: Int) {
        guard !commands.isEmpty else { return }
        commandLog.append(TickCommands(tick: tick, commands: commands))
    }

    public mutating func appendChecksum(tick: Int, checksum: UInt64) {
        checksums.append(ChecksumPoint(tick: tick, checksum: checksum))
    }
}

/// Deterministic playback: restores the recorded initial world and re-feeds
/// the recorded command stream tick by tick with the recorded rulesets.
public enum ReplayPlayer {
    public enum ReplayError: Error, Equatable {
        case unsupportedFormat(Int)
        /// The embedded rulesets fail their own validation — a decodable
        /// recording is not a runnable one (weapon arrays, timers, shapes).
        case invalidRules([String])
        /// The embedded world fails structural or invariant checks.
        case invalidInitialWorld([String])
        case startChecksumMismatch(expected: UInt64, actual: UInt64)
        case commandBeforeStart(tick: Int)
        case duplicateCommandTick(tick: Int)
        case invalidTickCount(Int)
        case tickRangeOverflow
    }

    /// Longest playback accepted (ten hours of ticks): a request beyond it
    /// is malformed input, not a job.
    public static let maxTickCount = 10 * 60 * 60 * MovementRuleset.ticksPerSecond

    /// Validates the recording — format, embedded rulesets, initial world
    /// (structure and invariants, before any arithmetic that assumes a safe
    /// world), checksum, command envelopes, tick range — then replays
    /// `tickCount` ticks from its initial world and returns the checksum
    /// points at the recording's cadence. Malformed data is an error, never
    /// a trap.
    public static func replay(
        _ recording: ReplayRecording, ticks tickCount: Int
    ) throws -> [ReplayRecording.ChecksumPoint] {
        guard recording.formatVersion == ReplayRecording.currentFormatVersion else {
            throw ReplayError.unsupportedFormat(recording.formatVersion)
        }
        let ruleIssues = recording.movement.validationIssues()
            + recording.weapons.validationIssues()
            + recording.pickups.validationIssues()
        guard ruleIssues.isEmpty else { throw ReplayError.invalidRules(ruleIssues) }
        let worldIssues = WorldInvariants.violations(in: recording.initialWorld)
        guard worldIssues.isEmpty else { throw ReplayError.invalidInitialWorld(worldIssues) }
        let actual = recording.initialWorld.checksum()
        guard actual == recording.startChecksum else {
            throw ReplayError.startChecksumMismatch(expected: recording.startChecksum, actual: actual)
        }
        guard tickCount >= 0, tickCount <= Self.maxTickCount else { throw ReplayError.invalidTickCount(tickCount) }
        let (endTick, overflow) = recording.initialTick.addingReportingOverflow(tickCount)
        guard !overflow, endTick >= recording.initialTick else { throw ReplayError.tickRangeOverflow }
        if let early = recording.commandLog.first(where: { $0.tick < recording.initialTick }) {
            throw ReplayError.commandBeforeStart(tick: early.tick)
        }
        var seenTicks = Set<Int>()
        for entry in recording.commandLog where !seenTicks.insert(entry.tick).inserted {
            throw ReplayError.duplicateCommandTick(tick: entry.tick)
        }
        var world = recording.initialWorld
        var points: [ReplayRecording.ChecksumPoint] = []
        var byTick: [Int: [PlayerCommand]] = [:]
        for entry in recording.commandLog { byTick[entry.tick] = entry.commands }
        for _ in 0..<tickCount {
            let commands = byTick[world.tick] ?? []
            Simulation.step(&world, commands: commands, ruleset: recording.movement,
                            weapons: recording.weapons, pickups: recording.pickups)
            if world.tick % MovementLabSession.checksumInterval == 0 {
                points.append(.init(tick: world.tick, checksum: world.checksum()))
            }
        }
        return points
    }
}
