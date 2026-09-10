import Foundation
import GameApplication
import GameCore
import SpriteKit
import Testing
@testable import AppleAdapters

/// ADR-0011 / PI round 11: the stage flow WIRED through the controller,
/// scene and audio — not only the pure timeline. Covers the input boundary
/// (R11-02), the outro effect clock (R11-01), determinism across
/// intro/outcome/restart, and the automatic continue. (The engine sound
/// and its tests were removed on the owner's 2026-09-10 decision.)
private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let vs01URL = repoRoot.appendingPathComponent("Content/stages/frontier_01_first_defense.json")
private let artRoot = repoRoot.appendingPathComponent("Vendor/SparkTreadPixel")

/// A voice plays until stopped, or — when its backend models sample length
/// (`voiceDuration`) — until that much clock time has passed since `play()`,
/// the way a real player reports `isPlaying`.
private final class CountingVoice: AudioVoice {
    let name: String
    unowned let backend: CountingBackend
    private var playing = false
    private var startedAt: TimeInterval = 0
    var isPlaying: Bool { playing && backend.clock() - startedAt < backend.voiceDuration }
    var volume: Float = 1
    var numberOfLoops = 0
    var currentTime: TimeInterval = 0
    var plays = 0
    init(name: String, backend: CountingBackend) { self.name = name; self.backend = backend }
    func prepareToPlay() -> Bool { true }
    func play() -> Bool { playing = true; startedAt = backend.clock(); plays += 1; return true }
    func stop() { playing = false }
}

private final class CountingBackend: AudioBackend, @unchecked Sendable {
    var voices: [CountingVoice] = []
    /// Test time source; with the default infinite `voiceDuration` a voice
    /// stays busy until stopped (the historical semantics of these tests).
    var clock: () -> TimeInterval = { 0 }
    var voiceDuration: TimeInterval = .infinity
    func activateSession() {}
    func makeVoice(named name: String) -> AudioVoice? {
        let voice = CountingVoice(name: name, backend: self)
        voices.append(voice)
        return voice
    }
    func plays(_ name: String) -> Int { voices.filter { $0.name == name }.reduce(0) { $0 + $1.plays } }
}

/// R15-08: time is an explicit input — the frame helper advances it once
/// per frame; reading the clock has no side effect, so the cadence under
/// test is the delivered frames, not the number of clock reads.
private final class FakeClock: @unchecked Sendable {
    var now: TimeInterval = 100
}

private let cell = SpatialUnits.subunitsPerCell
/// Intro length in clock ticks (card 138 + reveal 26 + title-out 24). The
/// 188th callback moves the flow into play AND runs simulation tick 1, so
/// `introTicks - 1` callbacks leave the flow on its last intro tick.
private let introTicks = 138 + 26 + 24

@MainActor
private func makeStageController() throws -> (MovementLabController, CountingBackend) {
    let world = try StageLoader.loadWorld(at: vs01URL)
    let backend = CountingBackend()
    let clock = FakeClock()
    let controller = MovementLabController(world: world, audio: GameAudio(backend: backend, clock: { clock.now }))
    return (controller, backend)
}

/// An open arena with a player tank at (3,3) cells facing right; no stage.
private func makeOpenWorld(player: Bool = true, steelAhead: Bool = false, frozen: Bool = false) -> WorldState {
    var world = WorldState(terrain: TerrainGrid(arena: .universal), seed: 7)
    if steelAhead {
        world.terrain[5, 3] = TerrainCell(kind: .steel)
        world.terrain[5, 4] = TerrainCell(kind: .steel)
    }
    world.addPlayer(PlayerState(playerID: .one))
    if player {
        let id = world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                                 positionSubunits: Vec2i(x: 3 * cell, y: 3 * cell), facing: .right)
        if frozen { world.withTank(entityID: id) { $0.statusEffects["frozen"] = 600 } }
    }
    return world
}

@MainActor
private func makeOpenController(_ world: WorldState) -> (MovementLabController, CountingBackend, FakeClock) {
    let backend = CountingBackend()
    let clock = FakeClock()
    backend.clock = { clock.now }
    let controller = MovementLabController(world: world, audio: GameAudio(backend: backend, clock: { clock.now }))
    controller.start()
    return (controller, backend, clock)
}

/// One clock callback followed by what the scene does every frame: advance
/// the clock by one frame, then drain the events into audio (which also
/// services the engine retrigger).
@MainActor
private func frame(_ controller: MovementLabController, clock: FakeClock, count: Int = 1) {
    for _ in 0..<count {
        clock.now += 1.0 / 60
        controller.stepOneTick()
        controller.audio.play(events: controller.drainEvents())
    }
}

@MainActor
@Suite struct StageFlowInputBoundaryTests {
    /// R11-02 exact reproduction: presses on the title-out screen must not
    /// fire on the first gameplay tick.
    @Test func pressesDuringTheIntroNeverReachTheFirstGameplayTick() throws {
        let (controller, _) = try makeStageController()
        controller.start()
        #expect(controller.flow.phase == .card)
        #expect(!controller.input.isAcceptingInput) // the clock runs, the flow is not in play
        for _ in 0..<(introTicks - 1) { controller.stepOneTick() }
        #expect(controller.flow.phase == .titleOut)
        controller.input.pressNormalFire(from: .touch)
        controller.input.pressSpecialFire(from: .touch)
        controller.input.press(.up, from: .touch)
        #expect(!controller.input.specialFireHeld && controller.input.held == nil) // refused at the gate
        controller.stepOneTick()
        #expect(controller.flow.phase == .playing && controller.input.isAcceptingInput)
        let events = controller.drainEvents()
        #expect(!events.contains { if case .weaponFired = $0 { return true }; return false })
        #expect(controller.session.world.tick == 1)
    }

    /// Even a hold that got in (a source admitted for another reason) is
    /// released at the transition, and the reset watermark moves so a
    /// physical callback observed before it is dropped on delivery.
    @Test func theTransitionIntoPlayReleasesEverythingAndAdvancesTheWatermark() throws {
        let (controller, _) = try makeStageController()
        controller.start()
        controller.input.isAcceptingInput = true // simulate a leak
        controller.input.press(.left, from: .key("A"))
        controller.input.pressSpecialFire(from: .key("K"))
        #expect(controller.input.held == .left && controller.input.specialFireHeld)
        let watermark = controller.input.lastResetUptime
        for _ in 0..<introTicks { controller.stepOneTick() }
        #expect(controller.flow.phase == .playing)
        #expect(controller.input.held == nil && !controller.input.specialFireHeld)
        #expect(controller.input.lastResetUptime >= watermark)
        let events = controller.drainEvents()
        #expect(!events.contains { if case .weaponFired = $0 { return true }; return false })
        // Now a real press is admitted and fires.
        controller.input.pressNormalFire(from: .touch)
        controller.stepOneTick()
        #expect(controller.drainEvents().contains { if case .weaponFired = $0 { return true }; return false })
    }

    @Test func suspendAndResumeDuringTheIntroKeepTheGate() throws {
        let (controller, _) = try makeStageController()
        controller.start()
        for _ in 0..<10 { controller.stepOneTick() }
        controller.suspend()
        #expect(!controller.input.isAcceptingInput)
        controller.start()
        #expect(!controller.input.isAcceptingInput) // still on the card
        for _ in 0..<introTicks { controller.stepOneTick() }
        #expect(controller.flow.phase == .playing && controller.input.isAcceptingInput)
        controller.suspend()
        #expect(!controller.input.isAcceptingInput)
        controller.start()
        #expect(controller.input.isAcceptingInput) // in play: the clock decides
    }

    @Test func restartOpensANewGatedIntro() throws {
        let (controller, _) = try makeStageController()
        controller.start()
        for _ in 0..<(introTicks - 1 + 30) { controller.stepOneTick() }
        #expect(controller.input.isAcceptingInput && controller.session.world.tick == 30)
        controller.restart()
        #expect(controller.flow.phase == .card && !controller.input.isAcceptingInput)
        #expect(controller.session.world.tick == 0)
        #expect(controller.lastCompletedRecording == nil) // no outcome: nothing to keep
    }
}

@Suite struct ResultsInteractionPolicyTests {
    /// R16-01: the results panel takes touches (scrolling) whenever it is
    /// presented, win or loss; restart only on a finished loss; nothing
    /// during the card, play or the outcome text.
    @Test func resultsAreInteractiveWheneverPresentedForEitherOutcome() {
        for phase in [StageFlow.Phase.panelIn, .panelHold, .finished] {
            #expect(StageFlowPresentationPolicy.resultsInteractive(phase: phase), "\(phase)")
        }
        for phase in [StageFlow.Phase.card, .reveal, .titleOut, .playing, .outroDelay, .outroText, .outroHold, .outroFade] {
            #expect(!StageFlowPresentationPolicy.resultsInteractive(phase: phase), "\(phase)")
        }
    }

    @Test func restartIsOnlyAFinishedLossAffordance() {
        #expect(StageFlowPresentationPolicy.restartAvailable(phase: .finished, outcome: .lost))
        #expect(!StageFlowPresentationPolicy.restartAvailable(phase: .finished, outcome: .won))
        #expect(!StageFlowPresentationPolicy.restartAvailable(phase: .panelHold, outcome: .lost))
        #expect(!StageFlowPresentationPolicy.restartAvailable(phase: .playing, outcome: nil))
    }
}

@Suite struct OutcomeTitleTests {
    /// R15-05: every loss used to read "基地失守"; the title now follows the
    /// simulation's reason.
    @Test func outcomeTitlesAreTruthful() {
        #expect(HUDLabels.outcomeTitle(won: true, lossReason: nil) == "任务完成")
        #expect(HUDLabels.outcomeSubtitle(won: true, lossReason: nil) == "敌军全部歼灭")
        #expect(HUDLabels.outcomeSubtitle(won: false, lossReason: "base_destroyed") == "基地被摧毁")
        #expect(HUDLabels.outcomeSubtitle(won: false, lossReason: "player_eliminated") == "所有坦克损失")
        #expect(HUDLabels.outcomeSubtitle(won: false, lossReason: "unknown").isEmpty)
        #expect(HUDLabels.outcomeTitle(won: false, lossReason: "base_destroyed") == "基地失守")
        #expect(HUDLabels.outcomeTitle(won: false, lossReason: "player_eliminated") == "全军覆没")
        #expect(HUDLabels.outcomeTitle(won: false, lossReason: nil) == "任务失败")
        #expect(HUDLabels.outcomeTitle(won: false, lossReason: "something_new") == "任务失败")
    }
}

@MainActor
@Suite struct OutroEffectClockTests {
    /// R11-01: the decisive tick's explosion ages on the presentation clock
    /// while the world tick holds.
    @Test func effectsExpireOnThePresentationClockWhileTheWorldIsHeld() throws {
        let art = try PixelArt(root: artRoot)
        let world = makeOpenWorld()
        let controller = MovementLabController(world: world)
        let scene = MovementLabScene(size: CGSize(width: 844, height: 390), controller: controller)
        scene.installForTests(art: art, world: world)
        controller.injectEventsForTests([
            .tankDestroyed(entityID: 42, ownerPlayerID: nil, position: Vec2i(x: 10 * cell, y: 10 * cell)),
        ])
        scene.advanceForTests(world: world, elapsed: 0)
        #expect(scene.transientEffectCountForTests == 1)
        #expect(scene.children.contains { $0 is PixelEffectNode })
        // Three presentation seconds pass; the world tick does not move.
        for _ in 0..<60 { scene.advanceForTests(world: world, elapsed: 0.05) }
        #expect(world.tick == 0)
        #expect(scene.transientEffectCountForTests == 0)
        #expect(!scene.children.contains { $0 is PixelEffectNode })
    }

    private func makeLiveScene() throws -> (MovementLabController, MovementLabScene, WorldState) {
        let art = try PixelArt(root: artRoot)
        let world = makeOpenWorld()
        let controller = MovementLabController(world: world)
        let scene = MovementLabScene(size: CGSize(width: 844, height: 390), controller: controller)
        scene.installForTests(art: art, world: world)
        controller.start()
        controller.injectEventsForTests([
            .tankDestroyed(entityID: 42, ownerPlayerID: nil, position: Vec2i(x: 10 * cell, y: 10 * cell)),
        ])
        scene.update(10.0) // production frame: drains the event, spawns the effect
        #expect(scene.transientEffectCountForTests == 1)
        return (controller, scene, world)
    }

    /// R12-01: frames delivered while the controller is suspended age nothing.
    @Test func framesWhileSuspendedDoNotAgeEffects() throws {
        let (controller, scene, _) = try makeLiveScene()
        controller.suspend()
        var t = 10.0
        for _ in 0..<60 { t += 0.05; scene.update(t) } // three seconds of host rendering
        #expect(scene.transientEffectCountForTests == 1)
        controller.start()
        scene.update(t) // first active frame: zero elapsed
        #expect(scene.transientEffectCountForTests == 1)
        for _ in 0..<6 { t += 0.05; scene.update(t) } // 0.3 s active: still under the 0.72 s recipe
        #expect(scene.transientEffectCountForTests == 1)
        for _ in 0..<20 { t += 0.05; scene.update(t) } // another second: expired
        #expect(scene.transientEffectCountForTests == 0)
    }

    /// R12-01 (round 13): a suspension with NO frame in between — the paused
    /// view delivers none — then a resume after a long gap. Not even the
    /// clamped 0.1 s may be counted: at 0.70 s of active age the effect is
    /// alive exactly as in the unsuspended control (its recipe is 0.72 s and
    /// expiry is at age > 0.77 s), and the clock reads 0.70 s.
    @Test func resumeWithoutAnInactiveFrameCountsNoSuspendedTime() throws {
        let (controller, scene, _) = try makeLiveScene()
        let (_, control, _) = try makeLiveScene()
        scene.update(10.05); control.update(10.05) // 50 ms of active age each
        controller.suspend()
        controller.start() // no scene frame observed the suspension
        scene.update(40.0) // thirty seconds later: the new zero
        control.update(10.05)
        #expect(scene.presentationTimeForTests == control.presentationTimeForTests)
        var t = 40.0, tc = 10.05
        for _ in 0..<13 { t += 0.05; tc += 0.05; scene.update(t); control.update(tc) } // 0.70 s active
        #expect(abs(scene.presentationTimeForTests - 0.70) < 1e-9)
        #expect(scene.transientEffectCountForTests == 1)
        #expect(control.transientEffectCountForTests == 1)
        for _ in 0..<2 { t += 0.05; tc += 0.05; scene.update(t); control.update(tc) } // 0.80 s: past 0.77
        #expect(scene.transientEffectCountForTests == 0)
        #expect(control.transientEffectCountForTests == 0)
    }
}

@MainActor
@Suite struct StageFlowDeterminismTests {
    private func script(_ controller: MovementLabController, ticks: Int) {
        for i in 0..<ticks {
            // Presses are attempted every tick; only those the gate admits count.
            if i == introTicks + 20 { controller.input.press(.up, from: .touch) }
            if i == introTicks + 80 { controller.input.release(.up, from: .touch) }
            if i == introTicks + 40 || i == introTicks + 95 { controller.input.pressNormalFire(from: .touch) }
            if i == 50 { controller.input.pressSpecialFire(from: .touch) } // during the card: refused
            controller.stepOneTick()
        }
    }

    /// The same input script through intro and play yields the same world
    /// and a recording that replays to its own checksums.
    @Test func sameScriptSameWorldAndReplayableRecording() throws {
        let (a, _) = try makeStageController()
        let (b, _) = try makeStageController()
        a.start(); b.start()
        let total = introTicks - 1 + 300
        script(a, ticks: total)
        script(b, ticks: total)
        #expect(a.session.world.tick == 300 && b.session.world.tick == 300)
        #expect(a.session.world.checksum() == b.session.world.checksum())
        #expect(a.session.recording.commandLog == b.session.recording.commandLog)
        #expect(!a.session.recording.commandLog.isEmpty)
        let replayed = try ReplayPlayer.replay(a.session.recording, ticks: 300)
        #expect(replayed == a.session.recording.checksums)
    }
}

@MainActor
@Suite struct AutomaticContinueTests {
    /// A stage with nothing to spawn is won at once; the outro runs to its
    /// end and the controller continues into a fresh, gated intro, keeping
    /// the completed recording.
    @Test func aWonStageContinuesIntoANewIntro() {
        var world = makeOpenWorld()
        world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 12 * cell, y: 20 * cell))
        world.stage = StageState(spawnQueue: [], maxAliveEnemies: 1, enemyStartDelayTicks: 0,
                                 spawnPointsCells: [Vec2i(x: 1, y: 1)],
                                 playerRespawnCell: Vec2i(x: 3, y: 3), dropTable: [])
        let (controller, backend, clock) = makeOpenController(world)
        #expect(controller.flow.phase == .card)
        frame(controller, clock: clock, count: introTicks - 1)
        #expect(controller.flow.phase == .titleOut && controller.flow.outcome == nil)
        var steps = 0
        while controller.flow.outcome == nil, steps < 600 { frame(controller, clock: clock); steps += 1 }
        #expect(controller.flow.outcome == .won) // nothing to spawn: decided on the first gameplay tick
        #expect(!controller.input.isAcceptingInput) // gated the moment the outcome is known
        let decidedTick = controller.session.world.tick
        #expect(decidedTick >= 1)
        while controller.flow.phase != .card, steps < 2000 { frame(controller, clock: clock); steps += 1 }
        #expect(controller.flow.phase == .card) // continued into the next intro
        #expect(controller.session.world.tick == 0)
        #expect(controller.lastCompletedRecording != nil)
        #expect(controller.lastCompletedRecording?.initialWorld.stage != nil)
        #expect(backend.plays("sfx_stage_win") == 1 && backend.plays("sfx_stage_card") == 1)
        frame(controller, clock: clock) // the new card's first tick fires its cue
        #expect(backend.plays("sfx_stage_card") == 2)
        #expect(!controller.input.isAcceptingInput)
    }

    /// ADR-0013: a won stage continues into the next stage of the campaign
    /// with the carried state; the last stage ends the run; a lost stage
    /// retries from its checkpoint.
    @Test func theCampaignAdvancesCarriesStateAndRetriesFromTheCheckpoint() throws {
        let campaign = CampaignDefinition(id: "test", displayNameKey: "k", stageIDs: ["one", "two", "three"])
        // Stage worlds: "one" and "three" are won at once; "two" is lost at once (base down) unless retried
        // after the flag flips — a provider closure sees every request.
        var loseTwo = true
        var requests: [(String, SessionState)] = []
        let provider = MovementLabController.StageProvider { id, session in
            requests.append((id, session))
            var world = makeOpenWorld()
            world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 12 * cell, y: 20 * cell))
            world.stage = StageState(spawnQueue: id == "two" && loseTwo ? ["normal_a"] : [], maxAliveEnemies: 1,
                                     enemyStartDelayTicks: 600, spawnPointsCells: [Vec2i(x: 1, y: 1)],
                                     playerRespawnCell: Vec2i(x: 3, y: 3), dropTable: [],
                                     clearBonus: .init(tally: 200, reward: 330))
            world.withPlayer(.one) { session.apply(to: &$0) }
            if id == "two", loseTwo { world.base?.durability = 0 }
            return world
        }
        let backend = CountingBackend()
        let clock = FakeClock()
        backend.clock = { clock.now }
        let controller = MovementLabController(campaign: CampaignRun(campaign: campaign), stages: provider,
                                               audio: GameAudio(backend: backend, clock: { clock.now }))
        controller.start()
        #expect(controller.stageID == "one" && controller.campaignRun?.stageNumber == 1)
        var steps = 0
        func runToOutcome() { while controller.flow.outcome == nil, steps < 4000 { frame(controller, clock: clock); steps += 1 } }
        func runToNextCard() { while controller.flow.phase != .card, steps < 6000 { frame(controller, clock: clock); steps += 1 } }
        runToOutcome()
        #expect(controller.flow.outcome == .won)
        runToNextCard()
        #expect(controller.stageID == "two" && controller.campaignRun?.stageNumber == 2)
        #expect(requests.last?.1.score == 530) // stage one's exit state built stage two
        #expect(controller.session.world.player(.one)?.score == 530)
        #expect(controller.campaignRecordings.count == 1 && controller.campaignRecordings[0].stageID == "one")
        // Stage two is lost: retry rebuilds it from the checkpoint (score 530, not the attempt's state).
        frame(controller, clock: clock, count: introTicks)
        runToOutcome()
        #expect(controller.flow.outcome == .lost && controller.stageID == "two")
        while controller.flow.phase != .finished, steps < 8000 { frame(controller, clock: clock); steps += 1 }
        #expect(!controller.campaignComplete)
        loseTwo = false
        controller.restart()
        #expect(controller.stageID == "two" && controller.flow.phase == .card)
        #expect(requests.last?.0 == "two" && requests.last?.1.score == 530)
        frame(controller, clock: clock, count: introTicks)
        runToOutcome()
        #expect(controller.flow.outcome == .won)
        runToNextCard()
        #expect(controller.stageID == "three" && controller.session.world.player(.one)?.score == 1060)
        frame(controller, clock: clock, count: introTicks)
        runToOutcome()
        #expect(controller.flow.outcome == .won && controller.campaignRun?.isLastStage == true)
        while controller.flow.phase != .finished, steps < 12000 { frame(controller, clock: clock); steps += 1 }
        frame(controller, clock: clock, count: 5) // the automatic continue fires once and stops
        #expect(controller.campaignComplete && controller.campaignRun?.isComplete == true)
        #expect(controller.flow.phase == .finished && controller.stageID == "three")
        #expect(controller.campaignRecordings.count == 3)
        #expect(controller.campaignRecordings.map(\.stageID) == ["one", "two", "three"])
        #expect(controller.campaignRecordings[2].sessionState?.score == 1060)
        #expect(!controller.input.isAcceptingInput)
        controller.restartCampaign()
        #expect(controller.stageID == "one" && !controller.campaignComplete && controller.campaignRecordings.isEmpty)
        #expect(controller.session.world.player(.one)?.score == 0 && controller.flow.phase == .card)
    }

    /// ADR-0015: the bundled-style provider hands the session the
    /// difficulty's weapon rules and the run's difficulty id; a director
    /// phase raises a HUD notice that expires.
    @Test func theProviderCarriesTheDifficultyAndPhasesRaiseANotice() throws {
        let campaign = CampaignDefinition(id: "test", displayNameKey: "k", stageIDs: ["one"])
        let provider = MovementLabController.StageProvider { run in
            var world = makeOpenWorld()
            world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 12 * cell, y: 20 * cell))
            world.stage = StageState(spawnQueue: ["normal_a", "normal_a"], maxAliveEnemies: 1, enemyStartDelayTicks: 0,
                                     spawnPointsCells: [Vec2i(x: 50, y: 1)], playerRespawnCell: Vec2i(x: 3, y: 3), dropTable: [],
                                     directorPhases: [DirectorPhase(id: "elite_minelayer", afterSpawned: 1, reinforcements: ["ap_c"])])
            var weapons = WeaponRuleset.provisional
            weapons.alliedBaseDamage = run.difficultyID != "casual"
            return .init(world: world, weapons: weapons)
        }
        let controller = MovementLabController(campaign: CampaignRun(campaign: campaign, difficultyID: "casual"), stages: provider)
        #expect(controller.session.weapons.alliedBaseDamage == false)
        #expect(controller.session.recording.difficultyID == "casual")
        let (_, _, clock) = (0, 0, FakeClock())
        controller.applicationDidBecomeActive()
        var steps = 0
        while controller.directorNotice == nil, steps < 800 { frame(controller, clock: clock); steps += 1 }
        #expect(controller.directorNotice?.text == "精英布雷车来袭 ×1")
        let raised = controller.session.world.tick
        while controller.directorNotice != nil, steps < 2000 { frame(controller, clock: clock); steps += 1 }
        #expect(controller.session.world.tick - raised > MovementLabController.directorNoticeTicks)
        #expect(HUDLabels.directorPhase("elite_x", reinforcements: 0) == "精英部队来袭")
        #expect(HUDLabels.directorPhase("wave2", reinforcements: 3) == "敌军增援 ×3")
    }

    /// ADR-0012: the world pays the clear bonuses on the deciding tick; the
    /// HUD withholds them until the panel's total line (tally bonus) and
    /// reward line (reward) the way the reference counts them in, and the
    /// results table always has its four rows, the total and the reward.
    @Test func theHUDPaysTheClearBonusesOutWithThePanel() {
        var world = makeOpenWorld()
        world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 12 * cell, y: 20 * cell))
        world.stage = StageState(spawnQueue: [], maxAliveEnemies: 1, enemyStartDelayTicks: 0,
                                 spawnPointsCells: [Vec2i(x: 1, y: 1)],
                                 playerRespawnCell: Vec2i(x: 3, y: 3), dropTable: [],
                                 clearBonus: .init(tally: 200, reward: 330))
        let (controller, backend, clock) = makeOpenController(world)
        backend.voiceDuration = 0.09 // the tally tick's length: five rows 0.2 s apart never exhaust its pool of three
        var steps = 0
        while controller.flow.outcome == nil, steps < 600 { frame(controller, clock: clock); steps += 1 }
        #expect(controller.flow.outcome == .won && controller.flow.hasRewardLine)
        #expect(controller.flow.panelRows == KillTally.tableRows + 1)
        #expect(controller.clearBonus == .init(tally: 200, reward: 330))
        #expect(controller.session.world.player(.one)?.score == 530) // authoritative, final
        #expect(controller.hud.score == 0)                            // shown: nothing paid out yet
        while controller.flow.panelRowsVisible < controller.flow.panelRows, steps < 2000 {
            #expect(controller.hud.score == 0)
            frame(controller, clock: clock); steps += 1
        }
        #expect(controller.hud.score == 200) // the total line pays the tally bonus
        while !controller.flow.showsReward, steps < 2000 {
            #expect(controller.hud.score == 200)
            frame(controller, clock: clock); steps += 1
        }
        #expect(controller.hud.score == 530) // the reward line pays the reward
        #expect(backend.plays("sfx_tally_tick") == KillTally.tableRows + 1)
        while controller.flow.phase != .card, steps < 3000 { frame(controller, clock: clock); steps += 1 }
        #expect(controller.clearBonus == .none) // reset with the world
    }
}
