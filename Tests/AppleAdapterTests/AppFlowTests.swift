import Foundation
import Testing
import GameApplication
import GameCore
@testable import AppleAdapters

/// Plan §12.1 screen flow and the explicit pause (ADR-0007, §17.5).
@Suite struct AppFlowModelTests {
    private let campaign = CampaignDefinition(id: "c", displayNameKey: "k", stageIDs: ["a_01_x", "a_02_y", "a_03_z"])

    @Test func titleToSelectToPlayAndBack() {
        var model = AppFlowModel(campaign: campaign)
        #expect(model.screen == .title)
        model.openCampaignSelect()
        #expect(model.screen == .campaignSelect)
        #expect(model.isUnlocked(stageIndex: 0) && !model.isUnlocked(stageIndex: 1) && !model.isUnlocked(stageIndex: 9))
        #expect(!model.startCampaign(at: 1) && model.screen == .campaignSelect) // locked
        #expect(model.startCampaign(at: 0) && model.screen == .playing(stageIndex: 0))
        model.recordCompleted(stageIDs: ["a_01_x"])
        model.backToTitle()
        #expect(model.screen == .title && model.isUnlocked(stageIndex: 1) && model.suggestedStageIndex == 1)
        model.startTraining()
        #expect(model.screen == .playing(stageIndex: nil))
    }

    @Test func launchEnvironmentSkipsTheTitle() {
        #expect(AppFlowModel(campaign: campaign, autostart: true).screen == .playing(stageIndex: 0))
        #expect(AppFlowModel(campaign: nil, autostart: true).screen == .title)
        #expect(AppFlowModel(campaign: nil, lab: true).screen == .playing(stageIndex: nil))
        #expect(AppFlowModel(campaign: nil).suggestedStageIndex == 0 && !AppFlowModel(campaign: nil).isUnlocked(stageIndex: 0))
    }
}

@Suite struct PauseBindingTests {
    @Test @MainActor func pauseIsAnEdgeOutsideTheActivityGate() {
        #expect(PhysicalBindings.keyboard["Escape"] == .pause && PhysicalBindings.keyboard["P"] == .pause)
        #expect(PhysicalBindings.controllerButtons["buttonMenu"] == .pause)
        let store = HeldDirectionStore()
        store.isAcceptingInput = false // paused: the gate is closed, the pause key still works
        PhysicalBindings.apply(.pause, pressed: true, from: .key("Escape"), to: store)
        PhysicalBindings.apply(.pause, pressed: false, from: .key("Escape"), to: store) // release is not an edge
        #expect(store.consumePauseRequest())
        #expect(!store.consumePauseRequest()) // consumed once
        PhysicalBindings.apply(.pause, pressed: true, from: .key("P"), to: store)
        PhysicalBindings.apply(.pause, pressed: true, from: .controller("pad", control: "buttonMenu"), to: store)
        #expect(store.consumePauseRequest() && !store.consumePauseRequest()) // two presses, one toggle
    }
}

@MainActor
@Suite struct PauseLifecycleTests {
    private func makeController() -> MovementLabController {
        var world = WorldState(terrain: TerrainGrid(arena: .universal), seed: 3)
        world.addPlayer(PlayerState(playerID: .one))
        let cell = SpatialUnits.subunitsPerCell
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3 * cell, y: 3 * cell), facing: .right)
        world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 12 * cell, y: 20 * cell))
        world.stage = StageState(spawnQueue: ["normal_a"], maxAliveEnemies: 1, enemyStartDelayTicks: 6000,
                                 spawnPointsCells: [Vec2i(x: 1, y: 1)], playerRespawnCell: Vec2i(x: 3, y: 3),
                                 dropTable: [])
        return MovementLabController(world: world)
    }

    private func play(_ controller: MovementLabController) {
        controller.applicationDidBecomeActive()
        while !controller.flow.allowsSimulation { controller.stepOneTick() }
    }

    @Test func pauseStopsTheClockAndResumeReadmitsInput() {
        let controller = makeController()
        play(controller)
        #expect(controller.isRunning && controller.input.isAcceptingInput && !controller.isPaused)
        let tick = controller.session.world.tick
        let generation = controller.activityGeneration
        controller.pause()
        #expect(controller.isPaused && !controller.isRunning && !controller.input.isAcceptingInput)
        #expect(controller.activityGeneration == generation + 1)
        controller.applicationDidBecomeActive() // an activation does not lift a pause
        #expect(controller.isPaused && !controller.isRunning)
        controller.pause() // idempotent
        #expect(controller.activityGeneration == generation + 1)
        controller.resume()
        #expect(!controller.isPaused && controller.isRunning && controller.input.isAcceptingInput)
        #expect(controller.session.world.tick == tick) // nothing stepped while paused
        controller.togglePause()
        #expect(controller.isPaused)
        controller.togglePause()
        #expect(!controller.isPaused && controller.isRunning)
    }

    @Test func inactivityMidPlayBecomesAPlayerVisiblePause() {
        let controller = makeController()
        play(controller)
        controller.applicationDidBecomeInactive()
        #expect(controller.isPaused && !controller.isRunning)
        controller.applicationDidBecomeActive()
        #expect(controller.isPaused && !controller.isRunning) // waits for "继续"
        controller.resume()
        #expect(controller.isRunning)
    }

    @Test func inactivityDuringTheIntroJustSuspendsAndResumes() {
        let controller = makeController()
        controller.applicationDidBecomeActive()
        #expect(controller.flow.phase == .card)
        controller.applicationDidBecomeInactive()
        #expect(!controller.isPaused && !controller.isRunning)
        controller.applicationDidBecomeActive()
        #expect(controller.isRunning && !controller.isPaused)
    }

    @Test func pauseIsIgnoredWhileNotRunningAndClearedByARestart() {
        let controller = makeController()
        controller.pause() // never started: nothing to pause
        #expect(!controller.isPaused)
        play(controller)
        controller.pause()
        controller.restart() // "重新开始本关" from the overlay: a fresh intro, not paused
        #expect(!controller.isPaused && controller.flow.phase == .card)
        controller.resume() // no-op
        #expect(!controller.isPaused)
    }
}
