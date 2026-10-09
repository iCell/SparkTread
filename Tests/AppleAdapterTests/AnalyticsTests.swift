import Foundation
import Testing
import GameApplication
import GameCore
@testable import AppleAdapters

/// The analytics boundary (owner 2026-10-09): the controller names the
/// moments — a stage starting, cleared or failed, the campaign completed —
/// and the install's progress as user properties; a recording sink here,
/// Firebase in the app.
@MainActor
@Suite struct AnalyticsTests {
    private let campaign = CampaignDefinition(id: "test", displayNameKey: "k", stageIDs: ["frontier_01_a", "frontier_02_b"])

    /// Stage worlds decided at once: won when the queue is empty, lost when
    /// the base starts broken.
    private func provider(lose: Set<String> = []) -> MovementLabController.StageProvider {
        MovementLabController.StageProvider { id, session in
            var world = WorldState(terrain: TerrainGrid(arena: .universal), seed: 3)
            world.addPlayer(PlayerState(playerID: .one))
            world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                            positionSubunits: Vec2i(x: 3 * SpatialUnits.subunitsPerCell, y: 3 * SpatialUnits.subunitsPerCell), facing: .right)
            world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 12 * SpatialUnits.subunitsPerCell, y: 20 * SpatialUnits.subunitsPerCell))
            world.stage = StageState(spawnQueue: lose.contains(id) ? ["normal_a"] : [], maxAliveEnemies: 1,
                                     enemyStartDelayTicks: 6000, spawnPointsCells: [Vec2i(x: 50, y: 1)],
                                     playerRespawnCell: Vec2i(x: 3, y: 3), dropTable: [])
            world.withPlayer(.one) { session.apply(to: &$0) }
            if lose.contains(id) { world.base?.durability = 0 }
            return world
        }
    }

    @Test func aRunReportsItsStartsClearsAndTheCampaign() {
        let sink = RecordingAnalyticsSink()
        GameAnalytics.sink = sink
        defer { GameAnalytics.sink = nil }
        let store = InMemorySaveStore()
        let controller = MovementLabController(campaign: CampaignRun(campaign: campaign, difficultyID: "casual"),
                                               stages: provider(), persistence: store)
        #expect(sink.events.first == .stageStarted(stageNumber: 1, stageID: "frontier_01_a", difficulty: "casual"))
        #expect(sink.properties["last_difficulty"] == "casual")
        controller.applicationDidBecomeActive()
        var steps = 0
        while controller.flow.phase != .finished, steps < 3000 { controller.stepOneTick(); steps += 1 }
        #expect(sink.events.contains { if case .stageCleared(1, "frontier_01_a", "casual", _, 3) = $0 { return true }; return false })
        #expect(sink.properties["furthest_stage_cleared"] == "1" && sink.properties["stages_cleared"] == "1")
        controller.continueToNextStage()
        #expect(sink.events.last == .stageStarted(stageNumber: 2, stageID: "frontier_02_b", difficulty: "casual"))
        steps = 0
        while controller.flow.phase != .finished, steps < 3000 { controller.stepOneTick(); steps += 1 }
        #expect(sink.events.contains { if case .campaignCompleted("casual", _) = $0 { return true }; return false })
        #expect(sink.properties["furthest_stage_cleared"] == "2" && sink.properties["stages_cleared"] == "2")
    }

    @Test func aLossReportsItsReason() {
        let sink = RecordingAnalyticsSink()
        GameAnalytics.sink = sink
        defer { GameAnalytics.sink = nil }
        let controller = MovementLabController(campaign: CampaignRun(campaign: campaign), stages: provider(lose: ["frontier_01_a"]))
        controller.applicationDidBecomeActive()
        var steps = 0
        while controller.flow.outcome == nil, steps < 600 { controller.stepOneTick(); steps += 1 }
        #expect(sink.events.contains(.stageFailed(stageNumber: 1, stageID: "frontier_01_a", difficulty: "standard", reason: "base_destroyed")))
        // A retry is a new start of the same stage.
        controller.restart()
        #expect(sink.events.last == .stageStarted(stageNumber: 1, stageID: "frontier_01_a", difficulty: "standard"))
    }

    @Test func progressPropertiesReadTheStageNumbers() {
        let sink = RecordingAnalyticsSink()
        GameAnalytics.sink = sink
        defer { GameAnalytics.sink = nil }
        GameAnalytics.recordProgress(completedStageIDs: ["frontier_01_first_defense", "iron_citadel_06_white_bulwark", "floodplain_04_x"])
        #expect(sink.properties["furthest_stage_cleared"] == "6" && sink.properties["stages_cleared"] == "3")
        GameAnalytics.recordProgress(completedStageIDs: [])
        #expect(sink.properties["furthest_stage_cleared"] == "0" && sink.properties["stages_cleared"] == "0")
    }
}
