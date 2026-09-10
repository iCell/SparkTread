import Foundation
import Testing
import GameCore
@testable import GameApplication

/// Plan §16.1–16.2, ADR-0003 §3: the save documents, their version gate,
/// and a suspended session that resumes deterministically.
private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let vs01URL = repoRoot.appendingPathComponent("Content/stages/frontier_01_first_defense.json")
private let campaign = CampaignDefinition(id: "campaign_v1", displayNameKey: "k",
                                          stageIDs: ["frontier_01_first_defense", "frontier_02_hidden_in_grass", "frontier_03_desert_stairs"])

private func script(_ session: inout MovementLabSession, from start: Int, ticks: Int) {
    for i in start..<(start + ticks) {
        let dir: Direction? = [Direction.up, .right, nil, .left, .down][(i / 45) % 5]
        session.advance(holding: dir, normalFire: i % 17 == 0, specialFire: i % 60 < 12)
    }
}

@Suite struct SaveDocumentTests {
    @Test func documentsCarryTheCurrentVersionAndValidate() throws {
        let run = CampaignRun(campaign: campaign)
        var progress = CampaignProgress(campaignID: "campaign_v1", completedStageIDs: ["frontier_01_first_defense"],
                                        checkpoint: run, bestScore: 530)
        #expect(progress.schemaVersion == SaveSchema.current && progress.validationIssues.isEmpty)
        progress.bestScore = -1
        progress.completedStageIDs = ["a", "a"]
        #expect(progress.validationIssues.count == 2)
        var other = CampaignProgress(campaignID: "other", checkpoint: run)
        #expect(other.validationIssues.contains { $0.contains("another campaign") })
        other.campaignID = ""
        #expect(other.validationIssues.contains { $0.contains("empty") })

        let world = try StageLoader.loadWorld(at: vs01URL)
        let session = MovementLabSession(world: world, stageID: run.stageID, sessionState: run.checkpoint)
        var snapshot = SuspendedSession(run: run, world: session.world, recording: session.recording)
        #expect(snapshot.validationIssues.isEmpty)
        snapshot.world.stage?.phase = .won
        #expect(snapshot.validationIssues == ["snapshot stage is decided"])
        snapshot.world.stage?.phase = .playing
        snapshot.run = CampaignRun(campaign: campaign, stageIndex: 1)
        #expect(snapshot.validationIssues.contains("recording is of another stage"))
        var noStage = snapshot
        noStage.world.stage = nil
        #expect(noStage.validationIssues.contains("snapshot has no stage"))
    }

    @Test func theInMemoryStoreGatesVersionsAndRefusesInvalidDocuments() throws {
        let store = InMemorySaveStore()
        #expect(try store.loadProgress() == nil && store.loadSuspended() == nil)
        var progress = CampaignProgress(campaignID: "campaign_v1", bestScore: 10)
        try store.saveProgress(progress)
        #expect(try store.loadProgress() == progress && store.progressWrites == 1)
        progress.bestScore = -3
        #expect(throws: SaveSchema.Error.self) { try store.saveProgress(progress) }
        let future = InMemorySaveStore(progress: { var p = CampaignProgress(campaignID: "c"); p.schemaVersion = 2; return p }())
        #expect(throws: SaveSchema.Error.unsupportedVersion(2)) { try future.loadProgress() }
        try store.clearSuspended()
        #expect(store.suspendedClears == 0) // nothing to clear
    }
}

@Suite struct SuspendedSessionResumeTests {
    /// ADR-0003 §3 / §17.5: run N ticks, snapshot (world + recording),
    /// resume, run M more: checksums equal an uninterrupted N+M run, and
    /// the resumed recording replays as ONE recording from the stage start.
    @Test func resumingASnapshotMatchesAnUninterruptedRun() throws {
        let run = CampaignRun(campaign: campaign)
        let world = try StageLoader.loadWorld(at: vs01URL, session: run.checkpoint)
        var interrupted = MovementLabSession(world: world, stageID: run.stageID, sessionState: run.checkpoint)
        script(&interrupted, from: 0, ticks: 500)
        let snapshot = SuspendedSession(run: run, world: interrupted.world, recording: interrupted.recording)
        #expect(snapshot.validationIssues.isEmpty)
        // Through the document's Codable shape, as a file store would.
        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(SuspendedSession.self, from: data)
        #expect(restored == snapshot)
        var resumed = MovementLabSession(resuming: restored.world, recording: restored.recording)
        #expect(resumed.world.tick == 500 && resumed.stageID == run.stageID && resumed.sessionState == run.checkpoint)
        script(&resumed, from: 500, ticks: 700)

        var uninterrupted = MovementLabSession(world: world, stageID: run.stageID, sessionState: run.checkpoint)
        script(&uninterrupted, from: 0, ticks: 1200)
        #expect(resumed.world.checksum() == uninterrupted.world.checksum())
        #expect(resumed.world == uninterrupted.world)
        #expect(resumed.recording.checksums == uninterrupted.recording.checksums)
        #expect(resumed.recording.initialTick == 0 && resumed.recording.commandLog.count == uninterrupted.recording.commandLog.count)
        // The resumed recording is one recording of the whole run.
        let replayed = try ReplayPlayer.replay(resumed.recording, ticks: 1200)
        #expect(replayed == uninterrupted.recording.checksums)
    }

    @Test func inconsistentSnapshotsAreRefused() throws {
        let world = try StageLoader.loadWorld(at: vs01URL)
        var session = MovementLabSession(world: world, stageID: "frontier_01_first_defense", sessionState: .campaignStart)
        script(&session, from: 0, ticks: 120)
        #expect(SuspendedSessionCheck.issues(world: session.world, recording: session.recording).isEmpty)
        // A snapshot from an earlier world than the recording's last command.
        var earlier = world
        for _ in 0..<50 { Simulation.step(&earlier, commands: []) }
        #expect(SuspendedSessionCheck.issues(world: earlier, recording: session.recording).contains("commands beyond the snapshot"))
        // A world older than the recording's start.
        let late = ReplayRecording(initialWorld: earlier, stageID: "frontier_01_first_defense", sessionState: .campaignStart)
        #expect(SuspendedSessionCheck.issues(world: world, recording: late).contains("world precedes its recording"))
        // A recording whose start no longer matches its checksum.
        var tampered = session.recording
        let data = try JSONEncoder().encode(tampered)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["startChecksum"] = 1
        tampered = try JSONDecoder().decode(ReplayRecording.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(SuspendedSessionCheck.issues(world: session.world, recording: tampered).contains("recording start checksum mismatch"))
    }
}
