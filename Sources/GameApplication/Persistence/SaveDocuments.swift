import GameCore

/// Persistence documents (plan §16.1–16.2, ADR-0003 §3, ADR-0014): what a
/// campaign run keeps between launches. Every document carries a
/// `schemaVersion`; `SaveSchema` gates versions and holds the (currently
/// empty) version-to-version migration table. Codable via the standard
/// library only — the file adapter lives in AppleAdapters.
public enum SaveSchema {
    /// The one version this build reads and writes.
    public static let current = 1

    public enum Error: Swift.Error, Equatable {
        case unsupportedVersion(Int)
        case invalidDocument([String])
    }

    /// Version gate for a decoded document: a document from a later build
    /// (or a corrupt version number) is refused before its content is
    /// trusted; earlier versions would be migrated here as they appear.
    public static func check(version: Int) throws {
        guard version == current else { throw Error.unsupportedVersion(version) }
    }
}

/// `campaign_progress.json`: unlocked/completed stages, the checkpoint run
/// to continue from (nil once the campaign is complete or never started),
/// and the best score. Written after every completed stage (§5.1).
public struct CampaignProgress: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var campaignID: String
    public var completedStageIDs: [String]
    /// The run to continue: the stage after the last completed one with
    /// the carried state as its checkpoint.
    public var checkpoint: CampaignRun?
    public var bestScore: Int

    public init(campaignID: String, completedStageIDs: [String] = [], checkpoint: CampaignRun? = nil,
                bestScore: Int = 0) {
        self.schemaVersion = SaveSchema.current
        self.campaignID = campaignID
        self.completedStageIDs = completedStageIDs
        self.checkpoint = checkpoint
        self.bestScore = bestScore
    }

    public var validationIssues: [String] {
        var issues: [String] = []
        if campaignID.isEmpty { issues.append("campaign id is empty") }
        if bestScore < 0 || bestScore > WorldInvariants.maxScore { issues.append("best score out of domain") }
        if Set(completedStageIDs).count != completedStageIDs.count { issues.append("completed stages repeat") }
        if let checkpoint {
            issues += checkpoint.validationIssues
            if checkpoint.campaign.id != campaignID { issues.append("checkpoint belongs to another campaign") }
        }
        return issues
    }
}

/// `suspended_session.json`: a mid-stage authoritative snapshot plus the
/// command log to date (ADR-0003 §3), written when the app leaves the
/// foreground mid-stage and deleted on stage completion or abandonment.
public struct SuspendedSession: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var run: CampaignRun
    public var world: WorldState
    public var recording: ReplayRecording

    public init(run: CampaignRun, world: WorldState, recording: ReplayRecording) {
        self.schemaVersion = SaveSchema.current
        self.run = run
        self.world = world
        self.recording = recording
    }

    /// A snapshot is resumable only when it is internally consistent: the
    /// run and world pass their domain checks, the stage is still being
    /// played, the recording starts where it says and precedes the world.
    public var validationIssues: [String] {
        var issues = run.validationIssues + WorldInvariants.violations(in: world)
        guard let stage = world.stage else { return issues + ["snapshot has no stage"] }
        if stage.phase != .playing { issues.append("snapshot stage is decided") }
        if recording.stageID != run.stageID { issues.append("recording is of another stage") }
        if recording.sessionState != run.checkpoint { issues.append("recording header differs from the checkpoint") }
        if recording.initialWorld.checksum() != recording.startChecksum { issues.append("recording start checksum mismatch") }
        if world.tick < recording.initialTick { issues.append("world precedes its recording") }
        if let last = recording.commandLog.last, last.tick >= world.tick { issues.append("commands beyond the snapshot") }
        return issues
    }
}

/// The narrow persistence operations the session layer needs (plan §13.2:
/// "Session orchestration defines the narrow persistence operations it
/// needs … Save adapters implement session-owned requirements").
public protocol CampaignPersistence: AnyObject {
    func loadProgress() throws -> CampaignProgress?
    func saveProgress(_ progress: CampaignProgress) throws
    func loadSuspended() throws -> SuspendedSession?
    func saveSuspended(_ session: SuspendedSession) throws
    func clearSuspended() throws
}

/// In-memory store for tests and previews: the documents round-trip
/// through their Codable shape only by value.
public final class InMemorySaveStore: CampaignPersistence {
    public private(set) var progress: CampaignProgress?
    public private(set) var suspended: SuspendedSession?
    public private(set) var suspendedWrites = 0
    public private(set) var suspendedClears = 0
    public private(set) var progressWrites = 0

    public init(progress: CampaignProgress? = nil, suspended: SuspendedSession? = nil) {
        self.progress = progress
        self.suspended = suspended
    }

    public func loadProgress() throws -> CampaignProgress? {
        guard let progress else { return nil }
        try SaveSchema.check(version: progress.schemaVersion)
        return progress
    }

    public func saveProgress(_ progress: CampaignProgress) throws {
        let issues = progress.validationIssues
        guard issues.isEmpty else { throw SaveSchema.Error.invalidDocument(issues) }
        self.progress = progress
        progressWrites += 1
    }

    public func loadSuspended() throws -> SuspendedSession? {
        guard let suspended else { return nil }
        try SaveSchema.check(version: suspended.schemaVersion)
        return suspended
    }

    public func saveSuspended(_ session: SuspendedSession) throws {
        let issues = session.validationIssues
        guard issues.isEmpty else { throw SaveSchema.Error.invalidDocument(issues) }
        suspended = session
        suspendedWrites += 1
    }

    public func clearSuspended() throws {
        if suspended != nil { suspendedClears += 1 }
        suspended = nil
    }
}
