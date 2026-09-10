import Foundation
import Testing
import GameApplication
import GameCore
@testable import AppleAdapters

/// Plan §17.5 / §16.1 through the controller: the suspended session is
/// written when the app leaves the foreground mid-stage and deleted on
/// completion or abandonment; progress is checkpointed after every won
/// stage; a resumed snapshot continues deterministically.
private let cell = SpatialUnits.subunitsPerCell
private let campaign = CampaignDefinition(id: "test", displayNameKey: "k", stageIDs: ["a_01_x", "a_02_y"])

/// Stage worlds with one far-off enemy so play lasts; `instantWin` stages
/// are decided on their first tick.
private func provider(instantWin: Set<String> = []) -> MovementLabController.StageProvider {
    MovementLabController.StageProvider { id, session in
        var world = WorldState(terrain: TerrainGrid(arena: .universal), seed: 11)
        world.addPlayer(PlayerState(playerID: .one))
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3 * cell, y: 3 * cell), facing: .right)
        world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 12 * cell, y: 20 * cell))
        world.stage = StageState(spawnQueue: instantWin.contains(id) ? [] : ["normal_a"], maxAliveEnemies: 1,
                                 enemyStartDelayTicks: 6000, spawnPointsCells: [Vec2i(x: 50, y: 1)],
                                 playerRespawnCell: Vec2i(x: 3, y: 3), dropTable: [],
                                 clearBonus: .init(tally: 200, reward: 330))
        world.withPlayer(.one) { session.apply(to: &$0) }
        return world
    }
}

@MainActor
private func play(_ controller: MovementLabController, ticks: Int = 0) {
    controller.applicationDidBecomeActive()
    while !controller.flow.allowsSimulation { controller.stepOneTick() }
    for _ in 0..<ticks { controller.stepOneTick() }
}

@MainActor
@Suite struct PersistenceLifecycleTests {
    @Test func leavingTheForegroundMidStageWritesTheSnapshotAndNothingDuringTheIntro() throws {
        let store = InMemorySaveStore()
        let controller = MovementLabController(campaign: CampaignRun(campaign: campaign), stages: provider(),
                                               persistence: store)
        controller.applicationDidBecomeActive()
        controller.applicationDidBecomeInactive() // on the card
        #expect(store.suspendedWrites == 0)
        controller.applicationDidBecomeActive()
        play(controller, ticks: 90)
        controller.applicationDidBecomeInactive()
        #expect(store.suspendedWrites == 1 && controller.isPaused)
        let snapshot = try #require(store.suspended)
        #expect(snapshot.world.tick == controller.session.world.tick && snapshot.run.stageID == "a_01_x")
        #expect(snapshot.recording.stageID == "a_01_x" && snapshot.validationIssues.isEmpty)
        #expect(controller.persistenceFailure == nil)
    }

    @Test func aDecidedStageClearsTheSnapshotAndAWinCheckpointsProgress() throws {
        let store = InMemorySaveStore()
        let controller = MovementLabController(campaign: CampaignRun(campaign: campaign), stages: provider(instantWin: ["a_01_x"]),
                                               persistence: store)
        controller.applicationDidBecomeActive()
        // Pretend a snapshot exists from an earlier foreground exit.
        try store.saveSuspended(SuspendedSession(run: CampaignRun(campaign: campaign),
                                                 world: controller.session.world, recording: controller.session.recording))
        var steps = 0
        while controller.flow.outcome == nil, steps < 600 { controller.stepOneTick(); steps += 1 }
        #expect(controller.flow.outcome == .won && store.suspended == nil && store.suspendedClears == 1)
        while controller.flow.phase != .card, steps < 3000 { controller.stepOneTick(); steps += 1 }
        let progress = try #require(store.progress)
        #expect(progress.completedStageIDs == ["a_01_x"] && progress.bestScore == 530)
        #expect(progress.checkpoint?.stageID == "a_02_y" && progress.checkpoint?.checkpoint.score == 530)
        // Abandoning the run (返回标题) clears any snapshot.
        play(controller, ticks: 30)
        controller.applicationDidBecomeInactive()
        #expect(store.suspended != nil)
        controller.abandon()
        #expect(store.suspended == nil && !controller.isRunning)
    }

    @Test func aResumedSnapshotOpensPausedAndContinuesDeterministically() throws {
        let store = InMemorySaveStore()
        let original = MovementLabController(campaign: CampaignRun(campaign: campaign), stages: provider(),
                                             persistence: store)
        play(original, ticks: 200)
        original.applicationDidBecomeInactive()
        let snapshot = try #require(store.suspended)
        let resumed = MovementLabController(resuming: snapshot, stages: provider(), persistence: store)
        #expect(resumed.isPaused && !resumed.isRunning && resumed.flow.phase == .playing)
        #expect(resumed.session.world.tick == original.session.world.tick && resumed.session.world.tick > 200)
        #expect(resumed.stageID == "a_01_x")
        resumed.applicationDidBecomeActive() // stays paused until the player resumes
        #expect(!resumed.isRunning)
        resumed.resume()
        #expect(resumed.isRunning && resumed.input.isAcceptingInput)
        original.resume()
        for _ in 0..<300 { resumed.stepOneTick(); original.stepOneTick() }
        #expect(resumed.session.world.checksum() == original.session.world.checksum())
        #expect(resumed.session.recording.checksums == original.session.recording.checksums)
        #expect(resumed.session.recording.initialTick == 0)
    }

    @Test func aFailingStoreIsReportedNotFatal() {
        final class Broken: CampaignPersistence {
            struct Boom: Error {}
            func loadProgress() throws -> CampaignProgress? { throw Boom() }
            func saveProgress(_ progress: CampaignProgress) throws { throw Boom() }
            func loadSuspended() throws -> SuspendedSession? { throw Boom() }
            func saveSuspended(_ session: SuspendedSession) throws { throw Boom() }
            func clearSuspended() throws { throw Boom() }
        }
        let controller = MovementLabController(campaign: CampaignRun(campaign: campaign), stages: provider(),
                                               persistence: Broken())
        play(controller, ticks: 10)
        controller.applicationDidBecomeInactive()
        #expect(controller.persistenceFailure?.contains("Boom") == true && controller.isPaused)
    }
}

@Suite struct FileSaveStoreTests {
    private func temporaryStore() throws -> FileSaveStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sparktread-save-\(UUID().uuidString)")
        return try FileSaveStore(directory: dir)
    }

    @Test func documentsRoundTripAtomicallyAndClearRemovesTheFile() throws {
        let store = try temporaryStore()
        #expect(try store.loadProgress() == nil && store.loadSuspended() == nil)
        let progress = CampaignProgress(campaignID: "test", completedStageIDs: ["a_01_x"],
                                        checkpoint: CampaignRun(campaign: campaign, stageIndex: 1, completedStageIDs: ["a_01_x"]),
                                        bestScore: 530)
        try store.saveProgress(progress)
        #expect(try store.loadProgress() == progress)
        let world = try provider().load("a_01_x", .campaignStart)
        let session = MovementLabSession(world: world, stageID: "a_01_x", sessionState: .campaignStart)
        let snapshot = SuspendedSession(run: CampaignRun(campaign: campaign), world: world, recording: session.recording)
        try store.saveSuspended(snapshot)
        #expect(try store.loadSuspended() == snapshot)
        try store.clearSuspended()
        #expect(!FileManager.default.fileExists(atPath: store.suspendedURL.path))
        #expect(try store.loadSuspended() == nil)
        try store.clearSuspended() // idempotent
    }

    @Test func foreignVersionsAndCorruptFilesAreErrorsNotCrashes() throws {
        let store = try temporaryStore()
        try Data("{\"schemaVersion\": 2, \"campaignID\": \"x\"}".utf8).write(to: store.progressURL)
        #expect(throws: SaveSchema.Error.unsupportedVersion(2)) { try store.loadProgress() }
        try Data("not json".utf8).write(to: store.suspendedURL)
        #expect(throws: FileSaveStore.FileError.self) { try store.loadSuspended() }
        try Data("{\"campaignID\": \"x\"}".utf8).write(to: store.progressURL) // no version
        #expect(throws: SaveSchema.Error.unsupportedVersion(-1)) { try store.loadProgress() }
        // The files stay for inspection.
        #expect(FileManager.default.fileExists(atPath: store.progressURL.path))
    }
}
