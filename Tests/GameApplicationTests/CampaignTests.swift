import Foundation
import Testing
import GameCore
@testable import GameApplication

/// ADR-0013: campaign progression — the carried session state, the run,
/// the campaign content and the chained replay.
private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let stagesDir = repoRoot.appendingPathComponent("Content/stages")
private let campaignURL = repoRoot.appendingPathComponent("Content/campaigns/campaign_v1.json")

private func stageURL(_ id: String) -> URL { stagesDir.appendingPathComponent("\(id).json") }

private func loadCampaign() throws -> CampaignDefinition {
    let def = try CampaignLoader.load(at: campaignURL)
    var stages: [String: StageDefinition] = [:]
    for id in def.stageIDs { stages[id] = try StageLoader.loadDefinition(at: stageURL(id)) }
    #expect(CampaignValidator.validate(def, stages: stages).isEmpty)
    return def
}

/// A stage world that is won on its first tick (nothing left to spawn),
/// built from the real content with the carried state.
private func instantWin(_ id: String, session: SessionState) throws -> WorldState {
    var world = try StageLoader.loadWorld(at: stageURL(id), session: session)
    world.stage?.spawnQueue.removeAll()
    world.stage?.carriedPickupQueue.removeAll() // pairs with the spawn queue (invariant)
    return world
}

@Suite struct SessionStateTests {
    @Test func campaignStartMatchesAFreshPlayer() {
        let start = SessionState.campaignStart
        #expect(start.lives == 3 && start.score == 0 && start.specialAmmoByWeapon == ["rapid": 50])
        #expect(start.retainedSpeedLevel == 0 && start.retainedPowerLevel == 0
                && start.retainedEquipmentID == nil && start.retainedSpecialWeaponID == "rapid")
        #expect(start.validationIssues.isEmpty)
    }

    @Test func carriedStateReadsTheLiveTankAndAppliesToAFreshPlayer() throws {
        var world = try StageLoader.loadWorld(at: stageURL("frontier_01_first_defense"))
        world.withPlayer(.one) { $0.lives = 5; $0.score = 1234; $0.specialAmmoByWeapon = ["rapid": 7, "fire": 12] }
        let tankID = try #require(world.player(.one)?.tankEntityID)
        world.withTank(entityID: tankID) {
            $0.speedLevel = 2; $0.powerLevel = 3; $0.equipmentID = "anti_skid"; $0.specialWeaponID = "fire"
            $0.armor = 1
        }
        let carried = try #require(SessionState.carried(from: world))
        #expect(carried == SessionState(lives: 5, score: 1234, specialAmmoByWeapon: ["rapid": 7, "fire": 12],
                                        retainedSpeedLevel: 2, retainedPowerLevel: 3,
                                        retainedEquipmentID: "anti_skid", retainedSpecialWeaponID: "fire"))
        // Next stage: the player and its first tank carry it; armor is the stage's.
        let next = try StageLoader.loadWorld(at: stageURL("frontier_02_hidden_in_grass"), session: carried)
        let player = try #require(next.player(.one))
        #expect(player.lives == 5 && player.score == 1234 && player.specialAmmoByWeapon == ["rapid": 7, "fire": 12])
        #expect(player.retainedSpeedLevel == 2 && player.retainedEquipmentID == "anti_skid")
        let tank = try #require(player.tankEntityID.flatMap { next.tank(entityID: $0) })
        #expect(tank.speedLevel == 2 && tank.powerLevel == 3 && tank.equipmentID == "anti_skid" && tank.specialWeaponID == "fire")
        #expect(tank.armor == 3 && tank.armor != 1) // §6.5: armor is not carried
        #expect(SessionState.carried(from: next) == carried)
        #expect(SessionState.carried(from: WorldState(terrain: TerrainGrid(arena: .universal), seed: 1)) == nil)
    }

    @Test func carriedStateFallsBackToRetainedFieldsWithoutATank() throws {
        var world = try StageLoader.loadWorld(at: stageURL("frontier_01_first_defense"))
        world.withPlayer(.one) { $0.tankEntityID = nil; $0.retainedPowerLevel = 1; $0.retainedSpecialWeaponID = "ap"; $0.lives = -2 }
        let carried = try #require(SessionState.carried(from: world))
        #expect(carried.retainedPowerLevel == 1 && carried.retainedSpecialWeaponID == "ap" && carried.lives == 0)
    }

    @Test func outOfDomainStatesAreRefusedBeforeBuilding() throws {
        var bad = SessionState.campaignStart
        bad.lives = -1; bad.retainedPowerLevel = 9; bad.specialAmmoByWeapon = ["": 5, "rapid": -1]
        #expect(bad.validationIssues.count == 4)
        #expect(throws: StageLoader.LoadError.self) {
            try StageLoader.loadWorld(at: stageURL("frontier_01_first_defense"), session: bad)
        }
        let def = try StageLoader.loadDefinition(at: stageURL("frontier_01_first_defense"))
        #expect(throws: StageBuilder.BuildError.self) { try StageBuilder.build(def, session: bad) }
    }
}

@Suite struct CampaignRunTests {
    private let campaign = CampaignDefinition(id: "c", displayNameKey: "k", stageIDs: ["s1", "s2", "s3"])

    @Test func advancesThroughTheStagesAndCompletes() {
        var run = CampaignRun(campaign: campaign)
        #expect(run.stageID == "s1" && run.stageNumber == 1 && !run.isLastStage && run.checkpoint == .campaignStart)
        var exit = SessionState.campaignStart
        exit.score = 530
        var advanced = run.advance(exitState: exit)
        #expect(advanced)
        #expect(run.stageID == "s2" && run.stageNumber == 2 && run.checkpoint == exit && run.completedStageIDs == ["s1"])
        exit.score = 1060; exit.lives = 2
        advanced = run.advance(exitState: exit)
        #expect(advanced)
        #expect(run.stageID == "s3" && run.isLastStage && !run.isComplete)
        exit.score = 2000
        advanced = run.advance(exitState: exit) // the last stage: the run is complete, still on s3
        #expect(!advanced)
        #expect(run.isComplete && run.stageID == "s3" && run.checkpoint == exit)
        #expect(run.completedStageIDs == ["s1", "s2", "s3"] && run.validationIssues.isEmpty)
    }

    @Test func restoredRunsAreDomainChecked() {
        var run = CampaignRun(campaign: campaign, stageIndex: 1, completedStageIDs: ["s1"])
        #expect(run.validationIssues.isEmpty)
        run = CampaignRun(campaign: campaign, stageIndex: 1, completedStageIDs: ["s2"])
        #expect(run.validationIssues.contains { $0.contains("out of campaign order") })
        var bad = SessionState.campaignStart
        bad.score = -5
        run = CampaignRun(campaign: campaign, checkpoint: bad)
        #expect(run.validationIssues.contains { $0.contains("score") })
    }

    @Test func campaignDefinitionsAreValidatedStructurallyAndAgainstStages() throws {
        #expect(CampaignValidator.validate(CampaignDefinition(id: "", displayNameKey: "k", stageIDs: [])).count == 2)
        #expect(CampaignValidator.validate(CampaignDefinition(id: "c", displayNameKey: "k", stageIDs: ["a", "a"]))
                .contains { $0.contains("repeats") })
        let def = try loadCampaign()
        #expect(def.id == "campaign_v1" && def.stageIDs.count == 3)
        var stages: [String: StageDefinition] = [:]
        for id in def.stageIDs { stages[id] = try StageLoader.loadDefinition(at: stageURL(id)) }
        // A stage numbered against its position, and a missing stage, are reported.
        stages[def.stageIDs[1]]?.stageNumber = 7
        #expect(CampaignValidator.validate(def, stages: stages).contains { $0.contains("is number 7 at position 2") })
        stages.removeValue(forKey: def.stageIDs[2])
        #expect(CampaignValidator.validate(def, stages: stages).contains { $0.contains("not found") })
    }
}

@Suite struct CampaignReplayTests {
    /// Three real stages, each won at once, recorded with the carried state
    /// in their headers: the chain verifies, the exit states carry the
    /// clear bonuses, and a tampered header breaks the chain.
    @Test func threeStageChainedReplayPasses() throws {
        let def = try loadCampaign()
        var run = CampaignRun(campaign: def)
        var recordings: [ReplayRecording] = []
        var ticks: [Int] = []
        var done = false
        while !done {
            let world = try instantWin(run.stageID, session: run.checkpoint)
            var session = MovementLabSession(world: world, stageID: run.stageID, sessionState: run.checkpoint)
            for _ in 0..<2 { session.advance(holding: nil) }
            #expect(session.world.stage?.phase == .won)
            recordings.append(session.recording)
            ticks.append(2)
            let exit = try #require(SessionState.carried(from: session.world))
            done = !run.advance(exitState: exit)
        }
        #expect(recordings.count == 3 && run.isComplete)
        #expect(recordings.map(\.stageID) == def.stageIDs)
        let results = try ReplayPlayer.replayCampaign(CampaignReplay(stages: recordings), ticks: ticks)
        #expect(results.map(\.exitState.score) == [530, 1060, 1590]) // 200 + 330 per stage (ADR-0012 tier 1)
        #expect(results.map(\.exitState.lives) == [3, 3, 3])
        #expect(recordings[1].sessionState == results[0].exitState && recordings[2].sessionState == results[1].exitState)

        // A header that is not the previous exit state breaks the chain.
        var tampered = recordings
        var wrong = try #require(tampered[1].sessionState)
        wrong.score += 10
        var world1 = tampered[1].initialWorld
        world1.withPlayer(.one) { $0.score = wrong.score }
        tampered[1] = ReplayRecording(initialWorld: world1, stageID: tampered[1].stageID, sessionState: wrong)
        #expect(throws: ReplayPlayer.ReplayError.sessionStateChainBroken(stage: 1)) {
            try ReplayPlayer.replayCampaign(CampaignReplay(stages: tampered), ticks: ticks)
        }
        // A header that does not describe its own world is refused by the stage replay.
        var mismatched = ReplayRecording(initialWorld: recordings[0].initialWorld,
                                         stageID: recordings[0].stageID, sessionState: wrong)
        mismatched.append(commands: [], atTick: 0)
        #expect(throws: ReplayPlayer.ReplayError.invalidSessionState(["header does not match the initial world's player"])) {
            try ReplayPlayer.replay(mismatched, ticks: 1)
        }
        // An undecided stage cannot chain.
        let playing = MovementLabSession(world: try StageLoader.loadWorld(at: stageURL(def.stageIDs[0])),
                                         stageID: def.stageIDs[0], sessionState: .campaignStart)
        #expect(throws: ReplayPlayer.ReplayError.stageUndecided(stage: 0)) {
            try ReplayPlayer.replayCampaign(CampaignReplay(stages: [playing.recording]), ticks: [1])
        }
        #expect(throws: ReplayPlayer.ReplayError.invalidTickCount(1)) {
            try ReplayPlayer.replayCampaign(CampaignReplay(stages: recordings), ticks: [2])
        }
    }

    @Test func recordingsRoundTripTheirCampaignHeader() throws {
        let world = try StageLoader.loadWorld(at: stageURL("frontier_01_first_defense"))
        let session = MovementLabSession(world: world, stageID: "frontier_01_first_defense", sessionState: .campaignStart)
        let data = try JSONEncoder().encode(session.recording)
        let decoded = try JSONDecoder().decode(ReplayRecording.self, from: data)
        #expect(decoded.stageID == "frontier_01_first_defense" && decoded.sessionState == .campaignStart)
        #expect(decoded == session.recording)
        let lab = MovementLabSession()
        #expect(lab.recording.stageID == nil && lab.recording.sessionState == nil)
        #expect(try JSONDecoder().decode(ReplayRecording.self, from: JSONEncoder().encode(lab.recording)) == lab.recording)
    }
}
