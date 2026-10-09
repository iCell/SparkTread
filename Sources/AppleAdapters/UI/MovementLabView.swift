import Combine          // Timer.publish's Publishers namespace
import GameApplication
import GameCore
import SpriteKit
import SwiftUI

/// Owns the Movement Lab wiring: session, input store, physical-input
/// adapter, the display-link clock driver (composition per §14.2), and the
/// presentation services (audio, haptics) whose lifecycle follows the
/// application's active state (§17.5).
@MainActor
public final class MovementLabController {
    public private(set) var session: MovementLabSession
    public let input = HeldDirectionStore()
    public let audio: GameAudio
    public let haptics: GameHaptics
    /// Lab mode (MOVEMENT_LAB=1): free-play world with the debug overlay and
    /// the weapon cheat panel. The playable stage shows neither (§18.4).
    public let isLab: Bool
    /// Events since the scene last drained them (presentation feed).
    private var pendingEvents: [DomainEvent] = []
    /// Stage presentation timeline (intro card, reveal, play, outro,
    /// results); the simulation steps only while it allows (ADR-0011).
    public private(set) var flow: StageFlow
    /// Enemies destroyed this stage, for the results panel.
    public private(set) var tally = KillTally()
    /// The recording of the last stage that reached an outcome, kept when
    /// the automatic continue replaced the session (post-game export/debug).
    public private(set) var lastCompletedRecording: ReplayRecording?
    #if canImport(GameController)
    private var physicalInput: PhysicalInputAdapter?
    #endif
    #if canImport(UIKit)
    private var driver: DisplayLinkSimulationDriver?
    #endif

    /// The injected world, if any: restarts rebuild it instead of loading
    /// a stage (presentation and integration tests have no bundle).
    private let injectedWorld: WorldState?

    /// Where campaign stages come from (ADR-0013): the bundled content in
    /// the app, an in-memory provider in tests.
    public struct StageProvider {
        /// A built stage: the world and the weapon rules it runs under (the
        /// difficulty's `alliedBaseDamage` lives in the rules, ADR-0005).
        public struct StageBuild {
            public var world: WorldState
            public var weapons: WeaponRuleset
            /// The stage's theme, which picks the ground family the scene
            /// tiles with. Presentation only — the simulation never sees it.
            public var themeID: String
            public init(world: WorldState, weapons: WeaponRuleset = .provisional,
                        themeID: String = "frontier") {
                self.world = world
                self.weapons = weapons
                self.themeID = themeID
            }
        }
        public let build: (_ run: CampaignRun) throws -> StageBuild

        public init(build: @escaping (_ run: CampaignRun) throws -> StageBuild) { self.build = build }

        /// Worlds only, provisional rules (tests).
        public init(load: @escaping (_ stageID: String, _ session: SessionState) throws -> WorldState) {
            build = { run in StageBuild(world: try load(run.stageID, run.checkpoint)) }
        }

        /// The app bundle: the stage under the run's difficulty (ADR-0015).
        public static func bundled(_ bundle: Bundle = .main, rules: PickupRuleset = .provisional) -> StageProvider {
            StageProvider { run in
                let difficulty = try DifficultyLoader.load(id: run.difficultyID, bundle: bundle)
                let stage = try StageLoader.loadStage(at: StageLoader.stageURL(id: run.stageID, bundle: bundle),
                                                      rules: rules, session: run.checkpoint,
                                                      difficulty: difficulty)
                var weapons = WeaponRuleset.provisional
                weapons.alliedBaseDamage = difficulty.alliedBaseDamage
                return StageBuild(world: stage.world, weapons: weapons,
                                  themeID: stage.definition.themeID)
            }
        }
    }

    /// The campaign this controller walks (nil in the lab and for injected
    /// worlds) and its stage source.
    public private(set) var campaignRun: CampaignRun?
    private let stages: StageProvider?
    /// Where progress and the suspended session go (plan §16.1; nil for the
    /// lab, injected worlds and tests without a store). Write failures are
    /// reported through `persistenceFailure` and never interrupt play.
    public var persistence: CampaignPersistence?
    public private(set) var persistenceFailure: String?
    /// Best score seen this run (progress document).
    private var bestScore = 0
    /// Recordings of the stages completed in this run, in order — the
    /// chained campaign replay (plan §16.3).
    public private(set) var campaignRecordings: [ReplayRecording] = []
    /// Set when the last stage's results have settled: the run is over.
    public private(set) var campaignComplete = false
    /// A won campaign stage is BOOKED the moment its results settle — run
    /// advanced, progress persisted — and the next stage is only BUILT when
    /// the player asks for it (owner 2026-10-07). Booking first means the
    /// win is on disk while the results sit there, however long they sit.
    private var wonStageBooked = false
    /// The results of a won stage are up and the next stage is waiting for
    /// the player's 下一关.
    public var nextStageAvailable: Bool {
        campaignRun != nil && wonStageBooked && !campaignComplete && flow.awaitsContinue
    }

    public static let bundledCampaignID = "campaign_v1"

    /// The app's controller: the bundled campaign, or the free-play lab
    /// with MOVEMENT_LAB=1. A missing or invalid bundled campaign is a
    /// build error (§15.4 fail-fast).
    public convenience init(audio: GameAudio? = nil) {
        if ProcessInfo.processInfo.environment["MOVEMENT_LAB"] != nil {
            self.init(world: nil, audio: audio)
        } else {
            let campaign: CampaignDefinition
            do { campaign = try CampaignLoader.load(id: Self.bundledCampaignID, bundle: .main) }
            catch { fatalError("bundled campaign failed to load: \(error)") }
            self.init(campaign: CampaignRun(campaign: campaign), stages: .bundled(), audio: audio)
        }
    }

    /// A campaign run from an explicit stage source.
    public init(campaign: CampaignRun, stages: StageProvider, audio: GameAudio? = nil,
                persistence: CampaignPersistence? = nil) {
        injectedWorld = nil
        isLab = false
        campaignRun = campaign
        self.stages = stages
        self.persistence = persistence
        let made = Self.makeStage(for: campaign, stages: stages)
        session = made.session
        themeID = made.themeID
        self.audio = audio ?? GameAudio()
        // The mixer is shared across games (AppRootView builds one), so a
        // controller taking it over starts it clean: no loop wanted by a
        // game the player quit mid-burn may survive into this one's start.
        self.audio.resetForNewWorld()
        self.haptics = GameHaptics()
        flow = Self.makeFlow(for: session.world, lab: false)
        #if canImport(GameController)
        physicalInput = PhysicalInputAdapter(store: input)
        #endif
        input.isAcceptingInput = false
        self.audio.suspend()
        self.haptics.suspend()
        logStageStart()
    }

    /// Analytics: a campaign stage begins — at construction, on retry, on
    /// 下一关 and on 再来一局 (every `adopt`).
    private func logStageStart() {
        guard let run = campaignRun else { return }
        GameAnalytics.log(.stageStarted(stageNumber: run.stageNumber, stageID: run.stageID, difficulty: run.difficultyID))
        GameAnalytics.set(.lastDifficulty, run.difficultyID)
    }

    /// Resumes a suspended session (plan §17.5, ADR-0003 §3): the snapshot
    /// world continues its recording; the flow starts in play (the intro
    /// is presentation and was already seen) and the game opens PAUSED so
    /// the player resumes deliberately.
    public init(resuming snapshot: SuspendedSession, stages: StageProvider, audio: GameAudio? = nil,
                persistence: CampaignPersistence? = nil) {
        precondition(snapshot.validationIssues.isEmpty, "snapshot rejected: \(snapshot.validationIssues)")
        injectedWorld = nil
        isLab = false
        campaignRun = snapshot.run
        self.stages = stages
        self.persistence = persistence
        session = MovementLabSession(resuming: snapshot.world, recording: snapshot.recording)
        self.audio = audio ?? GameAudio()
        // The mixer is shared across games (AppRootView builds one), so a
        // controller taking it over starts it clean: no loop wanted by a
        // game the player quit mid-burn may survive into this one's start.
        self.audio.resetForNewWorld()
        self.haptics = GameHaptics()
        flow = .playing()
        isPaused = true
        #if canImport(GameController)
        physicalInput = PhysicalInputAdapter(store: input)
        #endif
        input.isAcceptingInput = false
        self.audio.suspend()
        self.haptics.suspend()
    }

    /// An injected world (tests) or, with nil, the free-play lab world.
    public init(world: WorldState? = nil, audio: GameAudio? = nil) {
        injectedWorld = world
        stages = nil
        if let world {
            session = MovementLabSession(world: world)
            isLab = false
        } else {
            session = .trainingArena()
            isLab = true
        }
        self.audio = audio ?? GameAudio()
        // The mixer is shared across games (AppRootView builds one), so a
        // controller taking it over starts it clean: no loop wanted by a
        // game the player quit mid-burn may survive into this one's start.
        self.audio.resetForNewWorld()
        self.haptics = GameHaptics()
        flow = Self.makeFlow(for: session.world, lab: isLab)
        #if canImport(GameController)
        physicalInput = PhysicalInputAdapter(store: input)
        #endif
        // Cold start is INACTIVE until the view reports the active scene
        // phase (§17.5): no input admitted, no sound, no haptics before then.
        input.isAcceptingInput = false
        self.audio.suspend()
        self.haptics.suspend()
    }

    /// Bumped whenever the world is rebuilt so the scene knows to rebuild
    /// its static layers.
    public private(set) var worldGeneration = 0

    /// The playable stage's content id (nil in the lab / injected worlds);
    /// the view derives the intro card's title from it.
    public var stageID: String? { campaignRun?.stageID }

    /// Builds the run's current stage from its checkpoint. Stage content
    /// that fails to build is a build error (§15.4): the campaign was
    /// validated against its stages when it was loaded.
    private static func makeStage(for run: CampaignRun, stages: StageProvider)
        -> (session: MovementLabSession, themeID: String) {
        do {
            let built = try stages.build(run)
            return (MovementLabSession(world: built.world, weapons: built.weapons, stageID: run.stageID,
                                       sessionState: run.checkpoint, difficultyID: run.difficultyID),
                    built.themeID)
        } catch {
            fatalError("campaign stage '\(run.stageID)' failed to build: \(error)")
        }
    }

    /// The current stage's theme, which picks the ground family the scene
    /// tiles with. Presentation state, not simulation state: the campaign
    /// has run four themes since stage 4, and the scene drew frontier sand
    /// under all of them until this carried the choice through.
    public private(set) var themeID = "frontier"

    /// Swaps in a built stage and the theme it is drawn with.
    private func adopt(_ made: (session: MovementLabSession, themeID: String)) {
        themeID = made.themeID
        wonStageBooked = false
        replaceSession(made.session)
        logStageStart()
    }

    /// Stage worlds open with the intro card; the lab and worlds without a
    /// stage go straight to play.
    private static func makeFlow(for world: WorldState, lab: Bool) -> StageFlow {
        guard !lab, world.stage != nil else { return .playing() }
        return StageFlow(arenaCellsWide: world.arena.cellsWide, arenaCellsHigh: world.arena.cellsHigh)
    }

    /// Retry = the current stage again from its checkpoint (ADR-0013: the
    /// session state at the stage's start, so nothing from the failed
    /// attempt carries); injected and lab worlds rebuild as they were.
    public func restart() {
        if flow.outcome != nil { lastCompletedRecording = session.recording }
        if let campaignRun, let stages {
            adopt(Self.makeStage(for: campaignRun, stages: stages))
        } else if let injectedWorld {
            replaceSession(MovementLabSession(world: injectedWorld, ruleset: session.ruleset,
                                              weapons: session.weapons, pickups: session.pickups))
        } else {
            replaceSession(.trainingArena())
        }
    }

    /// A won campaign stage's results have settled: book the win — the run
    /// moves on from the carried state and the progress document is written
    /// now, not when the player taps — and either hold for 下一关 or, after
    /// the last stage, end the run (the results stay up).
    private func bookWonStage() {
        guard var run = campaignRun, !wonStageBooked else { return }
        wonStageBooked = true
        campaignRecordings.append(session.recording)
        lastCompletedRecording = session.recording
        let exit = SessionState.carried(from: session.world) ?? run.checkpoint
        bestScore = max(bestScore, exit.score)
        GameAnalytics.log(.stageCleared(stageNumber: run.stageNumber, stageID: run.stageID, difficulty: run.difficultyID,
                                        score: exit.score, lives: exit.lives))
        let hasNext = run.advance(exitState: exit)
        if !hasNext { GameAnalytics.log(.campaignCompleted(difficulty: run.difficultyID, score: exit.score)) }
        campaignRun = run
        // Checkpoint after every completed stage (§5.1): completed stages,
        // the run to continue (none once the campaign is complete), best score.
        persistProgress(checkpoint: hasNext ? run : nil, run: run)
        if !hasNext {
            campaignComplete = true
            syncInputAdmission()
        }
    }

    /// Writes the progress document around `run`: the completed stages are
    /// the UNION of the stored document's and the run's, so a new run that
    /// starts part-way never locks stages an earlier run opened; the best
    /// score is the greater of the two.
    private func persistProgress(checkpoint: CampaignRun?, run: CampaignRun) {
        persist { store in
            let stored = try store.loadProgress()
            let completed = Array(Set((stored?.completedStageIDs ?? []) + run.completedStageIDs)).sorted()
            try store.saveProgress(CampaignProgress(
                campaignID: run.campaign.id, completedStageIDs: completed,
                checkpoint: checkpoint, bestScore: max(bestScore, stored?.bestScore ?? 0)))
            // The install's progress, as the audience is cut by it.
            GameAnalytics.recordProgress(completedStageIDs: completed)
        }
    }

    /// A run the player has just started from the title or the select
    /// screen becomes the run to continue (owner 2026-10-09: a new casual
    /// game, lost on its first stage, then 继续 resumed an OLD run with its
    /// last lives — because a checkpoint was only ever written on a win).
    /// Written at the start, with the run's own starting state.
    public func checkpointRunStart() {
        guard let run = campaignRun, !campaignComplete else { return }
        persistProgress(checkpoint: run, run: run)
    }

    /// The player's 下一关 on a won stage's results: build the booked next
    /// stage. Nothing happens unless the results are up and the win booked.
    public func continueToNextStage() {
        guard nextStageAvailable, let run = campaignRun, let stages else { return }
        adopt(Self.makeStage(for: run, stages: stages))
    }

    /// Starts the campaign over from its first stage and the campaign
    /// start state; the checkpoint to continue from is withdrawn.
    public func restartCampaign() {
        guard let campaignRun, let stages else { restart(); return }
        let fresh = CampaignRun(campaign: campaignRun.campaign)
        self.campaignRun = fresh
        campaignRecordings.removeAll()
        campaignComplete = false
        bestScore = 0
        persist { store in
            let completed = try store.loadProgress()?.completedStageIDs ?? []
            try store.saveProgress(CampaignProgress(campaignID: fresh.campaign.id, completedStageIDs: completed,
                                                    checkpoint: nil, bestScore: try store.loadProgress()?.bestScore ?? 0))
        }
        adopt(Self.makeStage(for: fresh, stages: stages))
    }

    /// Leaving the game screen mid-run (返回标题): the suspended session, if
    /// any, is abandoned (§16.1) and the clock stops.
    public func abandon() {
        persist { try $0.clearSuspended() }
        stop()
    }

    /// Writes the mid-stage snapshot (ADR-0003 §3) while a campaign stage
    /// is being played; nothing while there is no stage, in the lab, or
    /// once the stage is decided.
    private func saveSuspendedSession() {
        guard let run = campaignRun, !campaignComplete, session.world.stage?.phase == .playing,
              flow.allowsSimulation else { return }
        let snapshot = SuspendedSession(run: run, world: session.world, recording: session.recording)
        persist { try $0.saveSuspended(snapshot) }
    }

    /// Persistence never interrupts play: a failing store is recorded on
    /// `persistenceFailure` (the title reports it) and play continues.
    private func persist(_ body: (CampaignPersistence) throws -> Void) {
        guard let persistence else { return }
        do { try body(persistence); persistenceFailure = nil }
        catch { persistenceFailure = String(describing: error) }
    }

    private func replaceSession(_ next: MovementLabSession) {
        isPaused = false
        pendingEvents.removeAll()
        audio.resetForNewWorld()
        session = next
        flow = Self.makeFlow(for: session.world, lab: isLab)
        tally = KillTally()
        clearBonus = .none
        syncInputAdmission()
        worldGeneration += 1
    }

    public var stagePhase: StagePhase? { session.world.stage?.phase }

    /// Provisional stage HUD data (§12.2): everything the player panel and
    /// the shared HUD show, read from the authoritative world.
    public struct HUDSnapshot: Equatable {
        /// Reserve tanks (GAME_RULES §11.3).
        public var lives: Int
        public var score: Int
        public var enemiesLeft: Int
        /// §15.2: enemies not yet on the field, and on the field now.
        public var enemiesWaiting: Int
        public var enemiesOnField: Int
        public var baseHP: Int
        public var baseMaxHP: Int
        public var shield: Bool
        public var armor: Int
        public var maxArmor: Int
        public var speedLevel: Int
        public var powerLevel: Int
        public var weaponID: String
        public var ammo: Int
        public var maxAmmo: Int
        public var equipmentID: String?
        public var invincible: Bool
        public var lifeState: LifeState
    }

    /// The player's §13 statistics for the results panel.
    public var stats: (maxHits: Int, maxCombos: Int) {
        let player = session.world.player(.one)
        return (player?.maxHits ?? 0, player?.maxCombos ?? 0)
    }

    public var hud: HUDSnapshot {
        let world = session.world
        let player = world.player(.one)
        let tank = playerTank
        let unfired = world.stage.map { stage in
            stage.directorPhases.dropFirst(stage.directorPhasesFired).reduce(0) { $0 + $1.reinforcements.count }
        } ?? 0
        let waiting = (world.stage?.spawnQueue.count ?? 0) + world.spawnTelegraphs.count + unfired
        let onField = world.tanks.filter { $0.teamID != 1 }.count
        let enemiesLeft = waiting + onField
        let weaponID = tank?.specialWeaponID ?? player?.retainedSpecialWeaponID ?? "rapid"
        return HUDSnapshot(
            lives: player?.lives ?? 0, score: displayedScore, enemiesLeft: enemiesLeft,
            enemiesWaiting: waiting, enemiesOnField: onField,
            baseHP: world.base?.durability ?? 0, baseMaxHP: world.base?.maxDurability ?? 0,
            shield: (world.base?.shieldRemainingTicks ?? 0) > 0,
            armor: tank?.armor ?? 0, maxArmor: tank?.maxArmor ?? 8,
            speedLevel: tank?.speedLevel ?? player?.retainedSpeedLevel ?? 0,
            powerLevel: tank?.powerLevel ?? player?.retainedPowerLevel ?? 0,
            weaponID: weaponID,
            ammo: player?.specialAmmoByWeapon[weaponID] ?? 0,
            maxAmmo: session.weapons.weapon(weaponID)?.maxAmmo ?? 0,
            equipmentID: tank?.equipmentID ?? player?.retainedEquipmentID,
            invincible: tank?.statusEffects["invincible"] != nil,
            lifeState: player?.lifeState ?? .active)
    }

    /// Launch-env autopilot for automated capture and demos; player input
    /// (touch/keyboard/controller) always overrides it when present.
    private let autodrive = ProcessInfo.processInfo.environment["MOVEMENT_LAB_AUTODRIVE"] != nil

    private func autodriveDirection(forTick tick: Int) -> Direction? {
        switch (tick % 1080) {
        case 0..<300: .down
        case 300..<540: .right
        case 540..<600: .up
        case 600..<840: .right
        case 840..<900: nil
        default: .up
        }
    }

    // MARK: - Lifecycle (§17.5, ADR-0007)

    /// The clock is running (the application is active and the view is on
    /// screen). Presentation services and input admission follow it.
    public private(set) var isRunning = false
    /// Bumped on every start/suspend so a presentation clock can detect a
    /// suspension that happened BETWEEN two of its frames (a paused view
    /// receives no frame while inactive) and rebase instead of counting the
    /// gap (R12-01).
    public private(set) var activityGeneration = 0

    /// Starts (or resumes) the clock, re-admits input, resumes audio and
    /// haptics. Idempotent. The reset watermark advances here too, so a
    /// physical callback OBSERVED while inactive but delivered after this
    /// point is dropped: admission is decided by when the event happened,
    /// not by when the main actor got to it.
    /// The next simulated tick follows a (re)start of the clock: its command
    /// carries `.continue` so the core drops buffered presses (§5.1).
    private var resumePending = false

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        resumePending = true
        activityGeneration &+= 1
        syncInputAdmission()
        audio.resume()
        haptics.resume()
        #if canImport(UIKit)
        let driver = DisplayLinkSimulationDriver(stepTick: { [weak self] in self?.stepOneTick() },
                                                 onStall: { [weak self] in self?.handleStall() })
        driver.start()
        self.driver = driver
        #endif
    }

    /// The application left the active state (or never reached it): stop
    /// the clock (no catch-up on return — the driver restarts with a fresh
    /// timestamp), silence audio and haptics, release every held input and
    /// refuse new presses until `start`, and discard queued presentation
    /// events so nothing historical plays after resume. Idempotent and
    /// effective even before the first start.
    public func suspend() {
        if isRunning { activityGeneration &+= 1 }
        isRunning = false
        #if canImport(UIKit)
        driver?.stop()
        driver = nil
        #endif
        input.releaseAll()
        input.isAcceptingInput = false
        pendingEvents.removeAll()
        audio.suspend()
        haptics.suspend()
    }

    /// View gone: same as a suspension.
    public func stop() { suspend() }

    // MARK: - Pause (plan §12.1 "Pause (overlay)", ADR-0007: an explicit
    // application-layer state, never a side effect of view state)

    /// The game is paused by the player or by an interruption during
    /// play: the clock is stopped and stays stopped through activations
    /// until `resume()`.
    public private(set) var isPaused = false

    /// Pauses a running game (no-op while already paused or not running).
    public func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        suspend()
    }

    /// Resumes from the pause overlay with a fresh clock.
    public func resume() {
        guard isPaused else { return }
        isPaused = false
        start()
    }

    /// Toggle for the pause/back action.
    public func togglePause() { isPaused ? resume() : pause() }

    /// A frame gap past the stall threshold (GAME_RULES §15.3): mid-play it
    /// becomes the player-visible pause; elsewhere the clock just goes on.
    func handleStall() {
        guard isRunning, flow.allowsSimulation, stagePhase == .playing else { return }
        pause()
    }

    /// §17.5: losing the active state pauses immediately; mid-play it
    /// becomes a PLAYER-visible pause (the overlay waits for "继续"), while
    /// an intro, outro or results screen simply resumes on return.
    public func applicationDidBecomeInactive() {
        let midPlay = isRunning && flow.allowsSimulation && stagePhase == .playing
        if midPlay { saveSuspendedSession() } // §17.5: written before suspension
        suspend()
        if midPlay { isPaused = true }
    }

    /// Returning to the active state resumes the clock unless the game is
    /// paused (then the overlay's "继续" does).
    public func applicationDidBecomeActive() {
        guard !isPaused else { return }
        start()
    }

    /// ONE input-admission policy (R11-02): input is accepted only while
    /// the clock runs AND the flow is in play. Every transition releases
    /// everything held or pending and advances the reset watermark, so a
    /// physical callback observed before the transition is dropped when it
    /// is delivered after it. Cutscene input is ignored outright — holding
    /// a direction through the intro does not carry into play.
    private func syncInputAdmission() {
        input.releaseAll()
        input.isAcceptingInput = isRunning && flow.allowsSimulation
    }

    /// The clock's callback: one tick of the stage flow, then — only while
    /// the flow is in play — one simulation tick. Internal for the driver
    /// and the integration tests.
    func stepOneTick() {
        let wasPlaying = flow.allowsSimulation
        for cue in flow.advance() { play(cue) }
        if flow.allowsSimulation != wasPlaying { syncInputAdmission() }
        if flow.awaitsContinue {
            // A campaign stage books its win and holds for the player; the
            // lab and an injected world have no next stage and no page to
            // tap, so they roll straight into the same stage again.
            if campaignRun != nil { bookWonStage() } else { restart() }
            return
        }
        guard flow.allowsSimulation else { return }
        let tick = session.world.tick
        let scripted = autodrive ? autodriveDirection(forTick: tick) : nil
        let scriptedNormal = autodrive && tick % 45 < 2
        let scriptedSpecial = autodrive && tick % 130 < 2
        if isLab { session.debugRespawnPlayerIfNeeded() }
        let normalPulse = input.consumeNormalFirePulse()
        let holding = input.held ?? scripted
        tally.remember(session.world)
        let events = session.advance(
            holding: holding,
            normalFire: normalPulse || scriptedNormal,
            specialFire: input.specialFireHeld || scriptedSpecial,
            sessionRequest: resumePending ? .continue : .none)
        resumePending = false
        tally.observe(events)
        pendingEvents += events
        for event in events {
            if case .stageClearBonus(let tally, let reward) = event {
                clearBonus = ScoreRules.ClearBonus(tally: tally, reward: reward)
            }
        }
        for event in events {
            if case .stageWon = event {
                flow.beginOutro(won: true, resultRows: KillTally.tableRows, rewardLine: clearBonus.reward > 0)
            }
            if case .stageLost(let reason) = event {
                flow.beginOutro(won: false, resultRows: KillTally.tableRows, lossReason: reason)
                if let run = campaignRun {
                    GameAnalytics.log(.stageFailed(stageNumber: run.stageNumber, stageID: run.stageID,
                                                   difficulty: run.difficultyID, reason: reason))
                }
            }
        }
        // A decided stage is no longer resumable: the snapshot goes (§16.1).
        if flow.outcome != nil, campaignRun != nil { persist { try $0.clearSuspended() } }
        if !flow.allowsSimulation { syncInputAdmission() }
    }

    /// Stage-flow cues → sounds (the outcome stingers moved here from the
    /// events: the reference plays them with the transition, not the kill).
    private func play(_ cue: StageFlow.Cue) {
        switch cue {
        case .cardTitle: audio.play("sfx_stage_card")
        case .reveal: break
        // The reference's results ambience starts about a second after the
        // outcome text and runs through the results (owner: a longer sound
        // on finishing a stage); the stinger carries its own lead-in.
        // Both outcomes (owner 2026-09-10 evening: the stage-end music is the
        // reference's results passage; the invented loss variant was removed).
        case .outcomeText: audio.play("sfx_stage_win")
        case .fade: break
        case .panelRow: audio.play("sfx_tally_tick", volume: 0.6) // four table rows + the total line
        case .reward: break // no isolated reference instance for the reward line yet
        }
    }

    /// The won stage's clear bonuses (ADR-0012), already in the world's
    /// score; the HUD withholds them until the results panel pays them out
    /// (tally bonus with the total line, reward with the reward line) the
    /// way the reference counts them in. Reset with the world.
    public private(set) var clearBonus = ScoreRules.ClearBonus.none

    /// Score the HUD shows: the world's score minus the clear bonuses the
    /// panel has not yet paid out.
    public var displayedScore: Int {
        let score = session.world.player(.one)?.score ?? 0
        guard flow.outcome == .won else { return score }
        var withheld = 0
        if flow.panelRowsVisible < flow.panelRows { withheld += clearBonus.tally }
        if !flow.showsReward { withheld += clearBonus.reward }
        return max(0, score - withheld)
    }

    public func drainEvents() -> [DomainEvent] {
        defer { pendingEvents.removeAll() }
        return pendingEvents
    }

    /// Test seam: events as if the simulation had emitted them this tick.
    func injectEventsForTests(_ events: [DomainEvent]) { pendingEvents += events }

    // MARK: - Weapon debug panel (lab only)

    public let specialWeaponIDs = ["rapid", "fire", "ap", "explosion"]

    public func selectWeapon(_ id: String) { if isLab { session.debugSelectSpecialWeapon(id) } }
    public func setPower(_ level: Int) { if isLab { session.debugSetPowerLevel(level) } }
    /// Training Arena: every pickup the content knows, and a spawner.
    public var pickupIDs: [String] { isLab ? TrainingArenaFixture.pickupIDs : [] }
    @discardableResult
    public func spawnPickup(_ id: String) -> Bool { isLab ? session.debugSpawnPickup(id) : false }
    /// Training Arena: the enemy families, equipment, and the spawner
    /// (family + power level + equipment; nil keeps the archetype's own).
    public var enemyFamilies: [String] { isLab ? TrainingArenaFixture.enemyFamilies : [] }
    public var enemyEquipmentIDs: [String] { isLab ? TrainingArenaFixture.equipmentIDs : [] }
    @discardableResult
    public func spawnEnemy(family: String, powerLevel: Int, equipmentID: String?) -> Bool {
        isLab ? session.debugSpawnEnemy(family: family, powerLevel: powerLevel, equipmentID: .some(equipmentID)) : false
    }
    public func clearEnemies() { if isLab { session.debugClearEnemies() } }

    public var playerTank: TankState? {
        session.world.player(.one)?.tankEntityID.flatMap { session.world.tank(entityID: $0) }
    }

    public var currentAmmo: Int {
        guard let tank = playerTank else { return 0 }
        return session.world.player(.one)?.specialAmmoByWeapon[tank.specialWeaponID] ?? 0
    }
}

/// Human-readable HUD labels (Chinese UI, §12.2): the HUD never shows raw
/// internal IDs.
enum HUDLabels {
    /// Every label is a key into the string catalog, resolved through the
    /// `Strings` of the language in force (owner 2026-10-08: six languages,
    /// the phone's by default, changeable in Settings). The tables that
    /// used to hold Chinese here now hold keys; the words live in
    /// `Resources/Localizable.xcstrings`.
    static func weapon(_ id: String, _ s: Strings) -> String {
        ["normal", "rapid", "fire", "ap", "explosion"].contains(id) ? s("weapon.\(id)") : id
    }

    static func equipment(_ id: String?, _ s: Strings) -> String {
        guard let id, ["amphi_tank", "anti_skid"].contains(id) else { return s("equipment.none") }
        return s("equipment.\(id)")
    }

    /// Results-table categories (GAME_RULES §13): ×1 Normal A/B | C/D,
    /// ×2 Rapid A/B | C/D, ×3 Explosion | Fire, ×4 AP A/B | C/D.
    static func rewardCategory(_ category: Int, _ s: Strings) -> String {
        (0...7).contains(category) ? s("reward.category.\(category)") : s("reward.category.other", category)
    }

    /// The stage content's name keys, by the name part of the stage id
    /// (`<theme>_<NN>_<name>`); the same keys the stage JSON declares as
    /// `displayNameKey`.
    private static let stageNameKeys: [String: String] = [
        "first_defense": "stage.vs01.name", "hidden_in_grass": "stage.vs02.name", "desert_stairs": "stage.vs03.name",
        "amphibious_crossing": "stage.s04.name", "slick_lane": "stage.s05.name", "white_bulwark": "stage.s06.name",
        "supply_run": "stage.s07.name", "fine_steel_gates": "stage.s08.name", "firebreaks": "stage.s09.name",
        "double_tempo": "stage.s10.name", "siege_rotation": "stage.s11.name", "all_arms": "stage.s12.name",
    ]

    /// Intro card title/subtitle from the stage content id
    /// (`<theme>_<number>_<name>`), e.g. "STAGE 01" / "首战防御".
    static func stageCard(_ stageID: String?, _ s: Strings) -> (title: String, subtitle: String) {
        guard let stageID else { return ("STAGE", "") }
        // The id is <theme>_<NN>_<name>, and the theme is not always one
        // word: `iron_citadel_08_fine_steel_gates` broke a parser that read
        // the number out of position 1, so stages 6, 8, 11 and 12 showed
        // "STAGE" with their number stranded in the subtitle. Find the
        // number, and the name is whatever follows it.
        let parts = stageID.split(separator: "_")
        let numberIndex = parts.firstIndex { Int($0) != nil }
        let number = numberIndex.map { Int(parts[$0])! }
        let title = number.map { s("stage.title", $0) } ?? "STAGE"
        let name = numberIndex.map { parts[(parts.index(after: $0))...].joined(separator: "_") } ?? ""
        let subtitle = stageNameKeys[name].map { s($0) } ?? name.replacingOccurrences(of: "_", with: " ").capitalized
        return (title, subtitle)
    }

    /// Outcome text: truthful per loss reason (R15-05) — the base fell, the
    /// player ran out of lives, or an unnamed failure.
    static func outcomeTitle(won: Bool, lossReason: String?, _ s: Strings) -> String {
        guard !won else { return s("outcome.won") }
        return switch lossReason {
        case "base_destroyed": s("outcome.base_destroyed")
        case "player_eliminated": s("outcome.player_eliminated")
        default: s("outcome.failed")
        }
    }

    /// Enemy family names for the training panel.
    static func enemyFamily(_ family: String, _ s: Strings) -> String { weapon(family, s) }

    /// Training roster label: family, tier and resistance, e.g. "普通A 1".
    static func rosterEntry(_ entry: TrainingArenaFixture.RosterEntry, _ s: Strings) -> String {
        "\(weapon(entry.family, s))\(entry.tier) \(entry.resistance)"
    }

    /// Pickup names for the training panel; the score pickups are their
    /// numbers in every language.
    static func pickup(_ id: String, _ s: Strings) -> String {
        switch id {
        case "score_200": "+200"
        case "score_500": "+500"
        case "score_1000": "+1000"
        case "score_2000": "+2000"
        case "speed_up", "armor_up", "power_up", "level_up", "max_speed_power", "max_armor_ammo", "ammo_crate",
             "rapid_weapon", "fire_weapon", "ap_weapon", "explosion_weapon", "amphi_tank", "anti_skid",
             "invincibility", "base_shield", "freeze_enemy", "bomb", "extra_life": s("pickup.\(id)")
        default: id
        }
    }

    /// One line under the stamped outcome title: why the stage ended.
    static func outcomeSubtitle(won: Bool, lossReason: String?, _ s: Strings) -> String {
        guard !won else { return s("outcome.detail.won") }
        return switch lossReason {
        case "base_destroyed": s("outcome.detail.base_destroyed")
        case "player_eliminated": s("outcome.detail.player_eliminated")
        default: ""
        }
    }

    /// Results-panel row label for an enemy archetype id.
    static func archetype(_ id: String, _ s: Strings) -> String {
        let family = id.split(separator: "_").first.map(String.init) ?? id
        switch family {
        case "light", "fast", "power", "rapid", "ap", "explosion", "fire": return s("enemy.family.\(family)")
        case "armor", "heavy": return s("enemy.family.armor")
        default: return s("enemy.family.other", family)
        }
    }
}

/// Root view — the playable VS-01 stage, or the free-play lab with
/// `MOVEMENT_LAB=1`: SpriteKit full-map presentation,
/// touch controls, hardware keyboard and controller, provisional HUD.
public struct MovementLabView: View {
    @State private var controller: MovementLabController
    @State private var scene: MovementLabScene?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.strings) private var strings
    @Environment(SettingsStore.self) private var settings
    /// Leave the game screen (pause overlay "返回标题", results "返回标题").
    private let onExit: (() -> Void)?

    /// The app's default: the bundled campaign (or the lab with
    /// MOVEMENT_LAB=1), no exit.
    public init() {
        _controller = State(initialValue: MovementLabController())
        onExit = nil
    }

    /// A game screen for a controller the root created (title flow).
    public init(controller: MovementLabController, onExit: (() -> Void)? = nil) {
        _controller = State(initialValue: controller)
        self.onExit = onExit
    }

    @State private var selectedWeapon = "rapid"
    @State private var powerLevel = 0
    @State private var showWeaponPanel = false
    /// Training panel enemy picker: family, then power level and equipment.
    @State private var enemyFamily: String?
    @State private var enemyPower = 0
    @State private var enemyEquipment: String?
    @State private var hudTick = 0
    /// Stage-flow state mirrored from the controller at 30 Hz; SwiftUI
    /// animates each transition (ADR-0011 timings) when it changes.
    @State private var flowPhase: StageFlow.Phase = .playing
    @State private var panelRows = 0
    /// Results-table tank icons by reward category, composed once from the
    /// scene's art (ADR-0012; the reference shows a tank per category).
    @State private var tankIcons: [Int: CGImage] = [:]
    /// Outcome impact: flash opacity (fades after the stamp) and the shake
    /// trigger (each increment runs one shake, losses only).
    @State private var outcomeFlash: Double = 0
    @State private var outcomeShake: CGFloat = 0

    private let hudTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private let flowTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // NOT `SpriteView(isPaused:)`: presenting through that binding
                // left the SKView blank on device and simulator (2026-09-10
                // owner report: flat gray after the intro). Inactivity pauses
                // the SCENE instead (see the scene-phase handler), which parks
                // SKActions; the scene's own update guard handles the clock.
                SpriteView(scene: liveScene(for: geometry.size))
                    .ignoresSafeArea()
                #if canImport(UIKit)
                // The reference shows no controls over its card or results;
                // the simulation does not step there either (ADR-0011).
                if !Self.isIntro(flowPhase), !Self.isDimmed(flowPhase), !paused {
                    TouchControlsView(controller: controller, art: scene?.loadedArt,
                                      specialWeaponID: controller.hud.weaponID,
                                      mirrored: settings.mirrorControls)
                        .ignoresSafeArea()
                }
                #endif
                if controller.isLab { weaponDebugPanel }
                stageHUD
                if !Self.isIntro(flowPhase), !Self.isDimmed(flowPhase), !paused { pauseButton }
                stageFlowOverlay(size: geometry.size)
                if paused { pauseOverlay }
            }
            .coordinateSpace(name: Self.surfaceSpace)
            .onChange(of: geometry.size) { _, size in scene?.surfaceDidChange(to: size) }
            .onReceive(flowTimer) { _ in
                syncFlow()
                // The pause/back action is polled here, outside the tick: a
                // paused game has no ticks to consume it.
                if controller.input.consumePauseRequest(), controller.isPaused || controller.flow.allowsSimulation {
                    controller.togglePause()
                }
                if paused != controller.isPaused { paused = controller.isPaused }
                scene?.isPaused = scenePhase != .active || controller.isPaused
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .persistentSystemOverlays(.hidden)
        .deferringBottomSystemGestures() // ADR-0004 §1
        .onAppear { if scenePhase == .active { controller.applicationDidBecomeActive() } }
        .onDisappear { controller.stop() }
        .onChange(of: scenePhase) { _, phase in
            // §17.5: losing the active state pauses immediately (mid-play as
            // a player-visible pause); returning resumes with a fresh clock
            // (no tick burst) unless the pause overlay is up.
            if phase == .active { controller.applicationDidBecomeActive() } else { controller.applicationDidBecomeInactive() }
            paused = controller.isPaused
            scene?.isPaused = phase != .active || controller.isPaused // parks SKActions
        }
        .onReceive(hudTimer) { _ in hudTick &+= 1 }
        .onChange(of: settings.hapticsEnabled, initial: true) { _, on in controller.haptics.isEnabled = on }
    }

    /// Mirrors `controller.isPaused` into view state (SwiftUI does not
    /// observe the controller).
    @State private var paused = false
    /// The HUD pill's own frame, so it can tell what it is covering.
    @State private var hudRect: CGRect = .zero
    static let surfaceSpace = "sparktread.surface"
    /// Re-read on every HUD refresh, which is the cadence the numbers
    /// already update at.
    private var hudObstructed: Bool {
        scene?.drawsLiveObject(under: hudRect) ?? false
    }

    private var pauseButton: some View {
        Button {
            controller.pause()
            paused = controller.isPaused
        } label: {
            if let glyph = MenuArt.sprite("px_ui_icon_pause") {
                Image(decorative: glyph, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "pause.fill").font(.system(size: 14, weight: .heavy))
            }
        }
        .buttonStyle(PlateButtonStyle(role: .secondary, size: .small))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 14)
        .padding(.top, 6)
    }

    /// Pause overlay (plan §12.1): resume, restart the stage, exit.
    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(strings("pause.title"))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.yellow)
                PlateButton(title: strings("pause.resume"), icon: "play.fill", role: .primary, size: .large) {
                    controller.resume(); paused = false
                }
                HStack(spacing: 12) {
                    if controller.stagePhase != nil {
                        PlateButton(title: strings("pause.restart"), icon: "arrow.counterclockwise") {
                            controller.restart(); controller.resume(); paused = false
                        }
                    }
                    if let onExit {
                        PlateButton(title: strings("pause.exit"), icon: "xmark") { controller.abandon(); onExit() }
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
            .platePanel()
        }
    }

    /// Provisional stage HUD (§12.2): player panel (lives, armor, weapon and
    /// ammunition, power/speed, equipment, status) and the shared panel
    /// (enemies remaining, base durability/shield, score). Safe-area aware;
    /// two compact rows so nothing is clipped on the 390-point floor.
    @ViewBuilder private var stageHUD: some View {
        if controller.stagePhase != nil, !Self.isIntro(flowPhase), !Self.isDimmed(flowPhase) {
            StageHUDBar(hud: controller.hud, scale: settings.largeHUD ? 1.3 : 1)
            .id(hudTick)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(settings.highContrastHUD ? 0.92 : 0.55)))
            // The full-screen arena (ADR-0022) leaves the HUD nowhere off the
            // playfield, and it sits on the top edge — which §9 makes the
            // spawn lane, so an arriving enemy is exactly under it. §15.1
            // forbids an opaque HUD over a key object, so the pill thins out
            // while anything live is behind it and comes back when it passes.
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { hudRect = proxy.frame(in: .named(Self.surfaceSpace)) }
                    .onChange(of: proxy.frame(in: .named(Self.surfaceSpace))) { _, rect in
                        hudRect = rect
                    }
            })
            // 0.4, not lower: the top edge is the spawn lane, so the pill
            // spends real time thinned out, and it still has to be readable
            // at a glance while it is. Enough to see a tank through, enough
            // to read the armour and the ammo.
            // High contrast: an opaque pill that never thins out.
            .opacity(hudObstructed && !settings.highContrastHUD ? 0.4 : 1)
            .animation(settings.reduceMotion ? nil : .easeInOut(duration: 0.18), value: hudObstructed)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 4)
        }
    }

    // MARK: - Stage flow presentation (ADR-0011)

    private static func isIntro(_ phase: StageFlow.Phase) -> Bool {
        phase == .card || phase == .reveal || phase == .titleOut
    }

    /// From the outro fade on, the playfield is dark and the results own the screen.
    private static func isDimmed(_ phase: StageFlow.Phase) -> Bool {
        phase == .outroFade || phase == .panelIn || phase == .panelHold || phase == .finished
    }

    /// Mirrors the controller's flow into view state, choosing the animation
    /// the reference measured for each transition.
    private func syncFlow() {
        let phase = controller.flow.phase
        let rows = controller.flow.panelRowsVisible
        if rows != panelRows { panelRows = rows }
        guard phase != flowPhase else { return }
        let animation: Animation? = switch phase {
        case .card: .easeOut(duration: 1.0)      // title slides in
        case .titleOut: .easeIn(duration: 0.4)   // title flips away
        case .outroText: .spring(response: 0.35, dampingFraction: 0.55) // title stamps in
        case .outroFade: .easeInOut(duration: 0.6)                       // title glides to the top
        case .panelIn: .spring(response: 0.4, dampingFraction: 0.72)     // card pops in
        default: nil
        }
        if let animation { withAnimation(animation) { flowPhase = phase } } else { flowPhase = phase }
        if phase == .outroText {
            // Impact: a screen flash that fades, and a shake on a loss.
            outcomeFlash = controller.flow.outcome == .won ? 0.55 : 0.7
            withAnimation(.easeOut(duration: 0.45)) { outcomeFlash = 0 }
            if controller.flow.outcome != .won {
                if !settings.reduceMotion { withAnimation(.easeOut(duration: 0.5)) { outcomeShake += 1 } }
            }
        }
        if Self.isDimmed(phase), tankIcons.isEmpty, let art = scene?.loadedArt {
            var icons: [Int: CGImage] = [:]
            for category in 0..<KillTally.tableRows * 2 {
                if let image = try? PixelTankIcons.image(category: category, art: art) { icons[category] = image }
            }
            tankIcons = icons
        }
    }

    /// Intro card, playfield reveal title, outcome text, fade, results.
    @ViewBuilder private func stageFlowOverlay(size: CGSize) -> some View {
        let card = HUDLabels.stageCard(controller.stageID, strings)
        ZStack {
            if flowPhase == .card {
                Color.black.ignoresSafeArea()
            }
            if flowPhase == .card || flowPhase == .reveal {
                VStack(spacing: 10) {
                    Text(card.title)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(Color.yellow)
                        .shadow(color: .black, radius: 0, x: 3, y: 3)
                    Text(card.subtitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 0, x: 2, y: 2)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .leading),
                    removal: .modifier(active: FlipAway(progress: 1), identity: FlipAway(progress: 0))))
            }
            if Self.isDimmed(flowPhase) {
                // The scene's cover tiles close over the arena; this dims the
                // margins and the HUD area so the card owns the screen.
                Color.black.opacity(0.82).ignoresSafeArea()
            }
            if outcomeFlash > 0 {
                (controller.flow.outcome == .won ? Color.white : Color.red)
                    .opacity(outcomeFlash)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            if controller.flow.showsOutcomeText, flowPhase != .outroDelay {
                let won = controller.flow.outcome == .won
                let centred = flowPhase == .outroText || flowPhase == .outroHold
                VStack(spacing: 6) {
                    Text(HUDLabels.outcomeTitle(won: won, lossReason: controller.flow.lossReason, strings))
                        .font(.system(size: 52, weight: .black))
                        .foregroundStyle(won ? Color.yellow : Color.red)
                        .shadow(color: .black, radius: 0, x: 3, y: 3)
                        .shadow(color: (won ? Color.yellow : Color.red).opacity(centred ? 0.6 : 0), radius: 18)
                    if centred {
                        Text(HUDLabels.outcomeSubtitle(won: won, lossReason: controller.flow.lossReason, strings))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 0, x: 2, y: 2)
                            .transition(.opacity)
                    }
                }
                .scaleEffect(centred ? 1 : 0.6)
                .modifier(OutcomeShake(phase: outcomeShake))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centred ? .center : .top)
                .padding(.top, centred ? 0 : size.height * 0.04)
                .transition(.scale(scale: 2.6).combined(with: .opacity)) // stamps in
            }
            if flowPhase != .outroFade, Self.isDimmed(flowPhase) {
                // Centred below the title (owner: "起码得居中").
                resultsPanel(size: size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.top, size.height * 0.1)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .allowsHitTesting(StageFlowPresentationPolicy.resultsInteractive(phase: flowPhase))
    }

    /// The reference's "战斗成绩" panel (ADR-0012, owner layout feedback
    /// 2026-09-10): a compact card on the left of the darkened playfield —
    /// title band, four rows of "icon count icon count ×k = subtotal", a
    /// rule, "总计"; the reward text rises over the title on a won stage
    /// with a clear bonus; the score and, on a loss, the restart button sit
    /// in the footer. Fixed at four rows, so no scrolling (R15-05 applied
    /// to a variable tally; the table is now the reference's fixed shape).
    private func resultsPanel(size: CGSize) -> some View {
        let tally = controller.tally
        let width = min(size.width * 0.46, 420)
        let compact = size.height < 420
        let rowFont = Font.system(size: compact ? 15 : 17, weight: .bold, design: .monospaced)
        let iconScale: CGFloat = compact ? 1.0 : 1.25
        return VStack(spacing: 0) {
            // The title, and under it the reward line of a won stage with a
            // clear bonus — its own line, reserved from the start so the
            // table does not shift when it lands. It used to sit in a ZStack
            // over the title and printed across it (owner 2026-10-08).
            VStack(spacing: 0) {
                Text(strings("results.title"))
                    .font(.system(size: compact ? 22 : 26, weight: .heavy))
                    .foregroundStyle(Color(red: 0.86, green: 0.42, blue: 0.96))
                    .shadow(color: .black, radius: 0, x: 1, y: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.top, compact ? 6 : 9)
                    .padding(.bottom, controller.flow.hasRewardLine ? 2 : (compact ? 6 : 9))
                if controller.flow.hasRewardLine {
                    Text(verbatim: strings("results.reward", String(controller.clearBonus.reward)))
                        .font(.system(size: compact ? 16 : 18, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.yellow)
                        .shadow(color: .black, radius: 0, x: 1, y: 1)
                        .padding(.bottom, compact ? 5 : 7)
                        .opacity(controller.flow.showsReward ? 1 : 0)
                        .offset(y: controller.flow.showsReward ? 0 : 14) // rises into its line
                        .animation(.easeOut(duration: 0.3), value: controller.flow.showsReward)
                }
            }
            .background(Color.black.opacity(0.35))
            Rectangle().fill(Color(red: 0.93, green: 0.72, blue: 0.2)).frame(height: 2)
            VStack(spacing: compact ? 4 : 6) {
                ForEach(0..<KillTally.tableRows, id: \.self) { row in
                    let counts = tally.rowCounts(row)
                    HStack(spacing: 6) {
                        categoryCell(2 * row, count: counts.left, scale: iconScale, visible: row < panelRows)
                        categoryCell(2 * row + 1, count: counts.right, scale: iconScale, visible: row < panelRows)
                        Spacer(minLength: 8)
                        Text(verbatim: "×\(row + 1) =").foregroundStyle(Color(red: 0.35, green: 0.95, blue: 0.55))
                        // Fixed digit columns (owner: "不同数字的时候也是能够对齐的"):
                        // right-aligned, plain digits, no grouping separators.
                        Text(verbatim: row < panelRows ? String(tally.rowSubtotal(row)) : "")
                            .foregroundStyle(.white)
                            .frame(width: compact ? 44 : 52, alignment: .trailing)
                    }
                    .font(rowFont)
                    .frame(height: 26 * iconScale + 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, compact ? 6 : 10)
            Rectangle().fill(Color(red: 0.95, green: 0.5, blue: 0.1)).frame(height: 3)
                .padding(.horizontal, 10)
            HStack(alignment: .firstTextBaseline) {
                Text(strings("results.total"))
                    .font(.system(size: compact ? 18 : 21, weight: .heavy))
                    .foregroundStyle(Color(red: 0.93, green: 0.72, blue: 0.2))
                Spacer()
                Text(verbatim: panelRows > KillTally.tableRows ? String(tally.weightedTotal) : "")
                    .font(.system(size: compact ? 26 : 30, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.yellow)
                    .frame(width: compact ? 80 : 96, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.top, compact ? 4 : 6)
            // The numbers on one line, the actions on their own line under
            // them: sharing a row squeezed the plates into two-line labels
            // and wrapped the statistics (owner 2026-10-08: 按钮排版有问题).
            HStack(spacing: 14) {
                Text(verbatim: strings("results.score", String(controller.hud.score)))
                    .font(.system(size: compact ? 14 : 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                // GAME_RULES §13 statistics.
                Text(verbatim: strings("results.stats", String(controller.stats.maxHits), String(controller.stats.maxCombos)))
                    .font(.system(size: compact ? 12 : 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 1.0))
                    .lineLimit(1)
                    .fixedSize()
                Spacer()
                if controller.campaignComplete {
                    Text(strings("results.campaignComplete"))
                        .font(.system(size: compact ? 15 : 17, weight: .heavy))
                        .foregroundStyle(Color.yellow)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, compact ? 6 : 10)
            HStack(spacing: 12) {
                if controller.campaignComplete {
                    PlateButton(title: strings("results.playAgain"), icon: "arrow.counterclockwise", role: .primary,
                                size: compact ? .small : .regular) { controller.restartCampaign() }
                    if let onExit {
                        PlateButton(title: strings("results.exit"), icon: "xmark", size: compact ? .small : .regular) {
                            controller.abandon(); onExit()
                        }
                    }
                }
                if controller.nextStageAvailable {
                    PlateButton(title: strings("results.next"), icon: "chevron.right", role: .primary,
                                size: compact ? .small : .regular) { controller.continueToNextStage() }
                }
                if StageFlowPresentationPolicy.restartAvailable(phase: flowPhase, outcome: controller.flow.outcome) {
                    PlateButton(title: strings("results.restart"), icon: "arrow.counterclockwise", role: .primary,
                                size: compact ? .small : .regular) { controller.restart() }
                    if let onExit {
                        PlateButton(title: strings("results.exit"), icon: "xmark", size: compact ? .small : .regular) {
                            controller.abandon(); onExit()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.top, compact ? 4 : 6)
            .padding(.bottom, compact ? 8 : 12)
        }
        .frame(width: width)
        .platePanel(radius: 12)
    }

    /// One category of a table row: the tank icon (or its label while the
    /// art is unavailable) and the kill count, blank until the row's cue.
    @ViewBuilder private func categoryCell(_ category: Int, count: Int, scale: CGFloat, visible: Bool) -> some View {
        HStack(spacing: 5) {
            if let icon = tankIcons[category] {
                Image(decorative: icon, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: CGFloat(icon.width) * scale, height: CGFloat(icon.height) * scale)
            } else {
                Text(HUDLabels.rewardCategory(category, strings)).foregroundStyle(.white)
            }
            Text(verbatim: visible ? String(count) : "")
                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 1.0))
                .frame(width: 36, alignment: .trailing) // three digits

        }
    }

    /// Weapon debug panel (lab only): special-weapon
    /// selector and power-level control, top-right, collapsible.
    /// Training Arena panel (lab only, top-right): special weapon and
    /// power level, a pickup spawner for every pickup the content knows,
    /// and a reset. Collapsible; the list scrolls inside half the surface.
    private var weaponDebugPanel: some View {
        VStack(alignment: .trailing, spacing: 6) {
            PlateButton(title: strings("lab.panel"), icon: showWeaponPanel ? "chevron.up" : "chevron.down", size: .small) {
                showWeaponPanel.toggle()
            }
            if showWeaponPanel {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(strings("lab.weapon")).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.yellow)
                        HStack(spacing: 4) {
                            ForEach(controller.specialWeaponIDs, id: \.self) { id in
                                panelButton(HUDLabels.weapon(id, strings), selected: selectedWeapon == id) {
                                    selectedWeapon = id
                                    controller.selectWeapon(id)
                                }
                            }
                        }
                        Text(strings("lab.power")).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.yellow)
                        HStack(spacing: 4) {
                            ForEach(0..<4, id: \.self) { level in
                                panelButton("P\(level)", selected: powerLevel == level) {
                                    powerLevel = level
                                    controller.setPower(level)
                                }
                            }
                        }
                        Text(strings("lab.enemies")).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.yellow)
                        HStack(spacing: 4) {
                            ForEach(controller.enemyFamilies, id: \.self) { family in
                                panelButton(HUDLabels.enemyFamily(family, strings), selected: enemyFamily == family) { enemyFamily = family }
                            }
                        }
                        if let family = enemyFamily {
                            HStack(spacing: 4) {
                                Text(strings("lab.power")).font(.system(size: 11)).foregroundStyle(.white)
                                ForEach(0..<4, id: \.self) { level in
                                    panelButton("P\(level)", selected: enemyPower == level) { enemyPower = level }
                                }
                            }
                            HStack(spacing: 4) {
                                Text(strings("lab.equipment")).font(.system(size: 11)).foregroundStyle(.white)
                                panelButton(strings("lab.none"), selected: enemyEquipment == nil) { enemyEquipment = nil }
                                ForEach(controller.enemyEquipmentIDs, id: \.self) { id in
                                    panelButton(HUDLabels.equipment(id, strings), selected: enemyEquipment == id) { enemyEquipment = id }
                                }
                            }
                            HStack(spacing: 4) {
                                panelButton(strings("lab.add", HUDLabels.enemyFamily(family, strings), enemyPower, HUDLabels.equipment(enemyEquipment, strings)), selected: true) {
                                    controller.spawnEnemy(family: family, powerLevel: enemyPower, equipmentID: enemyEquipment)
                                }
                            }
                        }
                        panelButton(strings("lab.clearEnemies"), selected: false) { controller.clearEnemies() }
                        Text(strings("lab.drops")).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.yellow)
                        let ids = controller.pickupIDs
                        ForEach(Array(stride(from: 0, to: ids.count, by: 3)), id: \.self) { start in
                            HStack(spacing: 4) {
                                ForEach(ids[start..<min(start + 3, ids.count)], id: \.self) { id in
                                    panelButton(HUDLabels.pickup(id, strings), selected: false) { controller.spawnPickup(id) }
                                }
                            }
                        }
                        panelButton(strings("lab.reset"), selected: false) { controller.restart() }
                    }
                }
                .frame(maxWidth: 340, maxHeight: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 16)
        .padding(.top, 8)
    }

    private func panelButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(PlateButtonStyle(role: .secondary, size: .small, selected: selected))
    }

    /// One scene per view; surface changes are delivered explicitly through
    /// `surfaceDidChange` (never by re-creating the scene from `body`).
    /// The scene reads the safe-area insets from its SKView (GAME_RULES §15.1).
    private func liveScene(for size: CGSize) -> MovementLabScene {
        if let scene { return scene }
        // Scene matches the real device surface so the uniform fit is
        // computed against the true edge-to-edge bounds (ADR-0004).
        let created = MovementLabScene(
            size: size == .zero ? CGSize(width: 844, height: 390) : size,
            controller: controller)
        DispatchQueue.main.async { scene = created }
        return created
    }
}

private extension View {
    /// Bottom-edge system gestures are deferred during gameplay (ADR-0004
    /// §1); the modifier only exists on iOS.
    @ViewBuilder func deferringBottomSystemGestures() -> some View {
        #if os(iOS)
        self.defersSystemGestures(on: .bottom)
        #else
        self
        #endif
    }
}

/// Interaction policy for the stage-flow overlay (R16-01). Gameplay input is
/// already refused by the controller's admission policy outside play and
/// the touch controls are hidden from the fade on, so the overlay may take
/// touches whenever the results panel is presented — for EITHER outcome,
/// so a large tally can be scrolled and read. Restart stays a finished
/// loss's affordance; a won campaign stage holds for the player's 下一关
/// (`MovementLabController.nextStageAvailable`).
enum StageFlowPresentationPolicy {
    static func resultsInteractive(phase: StageFlow.Phase) -> Bool {
        phase == .panelIn || phase == .panelHold || phase == .finished
    }

    static func restartAvailable(phase: StageFlow.Phase, outcome: StagePhase?) -> Bool {
        phase == .finished && outcome == .lost
    }
}

/// Loss impact: a decaying horizontal shake, one cycle per trigger
/// increment (animatable through `phase`).
private struct OutcomeShake: GeometryEffect {
    var phase: CGFloat
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let t = phase - phase.rounded(.down)         // 0…1 within the current cycle
        let amplitude = 10 * (1 - t)
        let dx = sin(t * .pi * 7) * amplitude
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}

/// The intro title's exit: a quarter-turn flip about the vertical axis
/// while fading (the reference flips its stage title away over ≈0.4 s).
private struct FlipAway: ViewModifier {
    var progress: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(90 * progress), axis: (x: 0, y: 1, z: 0))
            .opacity(1 - progress)
    }
}
