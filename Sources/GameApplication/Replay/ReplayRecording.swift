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

    /// Format 5 (2026-09-10, ADR-0015): the enemy brain reads its cadence,
    /// focus, fire windows and mine roll from `StageState.enemyBehavior`
    /// (the mine roll draws differently), the director runs authored
    /// phases, and the header names the difficulty.
    /// Format 4 (2026-09-10, ADR-0013): the header gained the campaign
    /// fields `stageID` and `sessionState` (plan §16.3 `initial_session_state`)
    /// so a campaign replay can verify that each stage's exit state equals
    /// the next stage's initial state; the stage clear bonus (ADR-0012)
    /// changed the score surface. Format 3 (2026-09-10): the embedded
    /// rulesets gained `PickupRuleset.dropsSpawnAtRandomCells`, and the
    /// EnemyBrain moved to cost-field navigation with new base-focus values.
    /// Earlier recordings embed a rules shape and an AI this build no longer
    /// reproduces, so they are rejected as `unsupportedFormat` rather than
    /// replayed into a different game.
    ///
    /// Compatibility POLICY (not an enforced build-identity check): a
    /// recording carries a format number, not a build revision. Any change
    /// that alters simulation behaviour for the same inputs — rules shape,
    /// AI, contact resolution — must bump this number so the boundary is
    /// detected; a behaviour change shipped without a bump is undetectable
    /// here and would surface only as a checksum mismatch during playback.
    public static let currentFormatVersion = 5

    public let formatVersion: Int
    /// Campaign header (ADR-0013): the stage this recording plays and the
    /// session state it started from; nil for lab and ad-hoc worlds.
    public let stageID: String?
    public let sessionState: SessionState?
    /// The difficulty the stage was built under (ADR-0015); the world
    /// carries its effects, this names them.
    public let difficultyID: String?
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
                pickups: PickupRuleset = .provisional,
                stageID: String? = nil, sessionState: SessionState? = nil, difficultyID: String? = nil) {
        self.formatVersion = Self.currentFormatVersion
        self.stageID = stageID
        self.sessionState = sessionState
        self.difficultyID = difficultyID
        self.initialWorld = initialWorld
        self.movement = movement
        self.weapons = weapons
        self.pickups = pickups
        self.startChecksum = initialWorld.checksum()
        self.commandLog = []
        self.checksums = []
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, stageID, sessionState, difficultyID, initialWorld, movement, weapons, pickups
        case startChecksum, commandLog, checksums
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
        stageID = try container.decodeIfPresent(String.self, forKey: .stageID)
        sessionState = try container.decodeIfPresent(SessionState.self, forKey: .sessionState)
        difficultyID = try container.decodeIfPresent(String.self, forKey: .difficultyID)
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

/// A campaign replay is an ordered list of stage recordings (plan §16.3);
/// the harness verifies that each stage's exit state equals the next
/// stage's initial session state before replaying it.
public struct CampaignReplay: Codable, Equatable, Sendable {
    public var stages: [ReplayRecording]
    public init(stages: [ReplayRecording]) { self.stages = stages }
}

/// Deterministic playback: restores the recorded initial world and re-feeds
/// the recorded command stream tick by tick with the recorded rulesets.
public enum ReplayPlayer {
    public enum ReplayError: Error, Equatable {
        case unsupportedFormat(Int)
        /// The carried session state in a recording's header fails its
        /// domain checks or does not match the player it built.
        case invalidSessionState([String])
        /// Chained campaign replay (ADR-0013): stage `index` starts from a
        /// session state that is not the previous stage's exit state.
        case sessionStateChainBroken(stage: Int)
        /// A campaign replay stage never reached an outcome in its ticks.
        case stageUndecided(stage: Int)
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
        if let header = recording.sessionState {
            let issues = header.validationIssues
            guard issues.isEmpty else { throw ReplayError.invalidSessionState(issues) }
            // The header is the state the stage was BUILT from: the world's
            // player must carry exactly it (the builder applies it verbatim).
            guard SessionState.carried(from: recording.initialWorld) == header else {
                throw ReplayError.invalidSessionState(["header does not match the initial world's player"])
            }
        }
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
        return try replayWorld(recording, ticks: tickCount).points
    }

    /// `replay` plus the final world (a campaign stage's exit state lives
    /// in it).
    static func replayWorld(
        _ recording: ReplayRecording, ticks tickCount: Int
    ) throws -> (points: [ReplayRecording.ChecksumPoint], world: WorldState) {
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
        return (points, world)
    }

    /// Chained campaign playback (plan §16.3, ADR-0013): every stage is
    /// validated and replayed for its recorded tick span (`ticks[i]`); a
    /// stage must reach an outcome, and the state its player carries out
    /// (`SessionState.carried`) must equal the next recording's header.
    /// Returns each stage's checksum points and exit state.
    public static func replayCampaign(
        _ campaign: CampaignReplay, ticks: [Int]
    ) throws -> [(points: [ReplayRecording.ChecksumPoint], exitState: SessionState)] {
        guard ticks.count == campaign.stages.count else { throw ReplayError.invalidTickCount(ticks.count) }
        var results: [(points: [ReplayRecording.ChecksumPoint], exitState: SessionState)] = []
        var previousExit: SessionState?
        for (index, stage) in campaign.stages.enumerated() {
            if let previousExit {
                guard stage.sessionState == previousExit else { throw ReplayError.sessionStateChainBroken(stage: index) }
            }
            let run = try replayWorld(stage, ticks: ticks[index])
            // `replay` validated the format, rules, world and header first.
            _ = try replay(stage, ticks: 0)
            guard let phase = run.world.stage?.phase, phase != .playing else { throw ReplayError.stageUndecided(stage: index) }
            guard let exit = SessionState.carried(from: run.world) else { throw ReplayError.stageUndecided(stage: index) }
            results.append((run.points, exit))
            previousExit = exit
        }
        return results
    }
}
