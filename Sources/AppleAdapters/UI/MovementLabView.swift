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
    /// the bundled stage (presentation and integration tests have no bundle).
    private let injectedWorld: WorldState?

    public init(world: WorldState? = nil, audio: GameAudio? = nil) {
        // An injected world allows presentation tests without app-bundle content.
        // VS-01 is the app's playable stage; MOVEMENT_LAB=1 launches the
        // free-play movement/combat lab world instead.
        let useLab = ProcessInfo.processInfo.environment["MOVEMENT_LAB"] != nil
        injectedWorld = world
        if let world {
            session = MovementLabSession(world: world)
            isLab = false
        } else {
            session = useLab ? MovementLabSession() : MovementLabSession(world: VS01Stage.makeWorld())
            isLab = useLab
        }
        self.audio = audio ?? GameAudio()
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
    public var stageID: String? { isLab || session.world.stage == nil ? nil : VS01Stage.stageID }

    /// Stage worlds open with the intro card; the lab and worlds without a
    /// stage go straight to play.
    private static func makeFlow(for world: WorldState, lab: Bool) -> StageFlow {
        guard !lab, world.stage != nil else { return .playing() }
        return StageFlow(arenaCellsWide: world.arena.cellsWide, arenaCellsHigh: world.arena.cellsHigh)
    }

    /// Restart = the same stage again (a provisional prototype loop, not
    /// campaign progression: lives and score reset with the world).
    public func restart() {
        if flow.outcome != nil { lastCompletedRecording = session.recording }
        pendingEvents.removeAll()
        audio.resetForNewWorld()
        if let injectedWorld {
            session = MovementLabSession(world: injectedWorld, ruleset: session.ruleset,
                                         weapons: session.weapons, pickups: session.pickups)
        } else {
            session.restartStage()
        }
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
        public var lives: Int
        public var score: Int
        public var enemiesLeft: Int
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

    public var hud: HUDSnapshot {
        let world = session.world
        let player = world.player(.one)
        let tank = playerTank
        let enemiesLeft = (world.stage?.spawnQueue.count ?? 0)
            + world.spawnTelegraphs.count
            + world.tanks.filter { $0.teamID != 1 }.count
        let weaponID = tank?.specialWeaponID ?? player?.retainedSpecialWeaponID ?? "rapid"
        return HUDSnapshot(
            lives: player?.lives ?? 0, score: displayedScore, enemiesLeft: enemiesLeft,
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
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        activityGeneration &+= 1
        syncInputAdmission()
        audio.resume()
        haptics.resume()
        #if canImport(UIKit)
        let driver = DisplayLinkSimulationDriver { [weak self] in self?.stepOneTick() }
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
        if flow.wantsAutomaticContinue {
            restart() // a won stage continues by itself (the same stage again until more content lands)
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
            specialFire: input.specialFireHeld || scriptedSpecial)
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
            }
        }
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

    public let specialWeaponIDs = ["rapid", "fire", "ap", "explosion", "mine"]

    public func selectWeapon(_ id: String) { if isLab { session.debugSelectSpecialWeapon(id) } }
    public func setPower(_ level: Int) { if isLab { session.debugSetPowerLevel(level) } }

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
    static func weapon(_ id: String) -> String {
        switch id {
        case "rapid": "快弹"
        case "fire": "燃烧"
        case "ap": "穿甲"
        case "explosion": "爆破"
        case "mine": "地雷"
        default: id
        }
    }

    static func equipment(_ id: String?) -> String {
        switch id {
        case "amphi_tank": "两栖"
        case "anti_skid": "防滑"
        case "shield_of_moon": "月牙"
        case "memory_of_sea": "海忆"
        default: "无"
        }
    }

    /// Results-table reward categories (ADR-0012; GAME_MECHANICS_SPEC §8.2
    /// last column): 0/1 the two Normal pairs, 2 Rapid, 3 Mine,
    /// 4 Explosion, 5 Fire, 6/7 the two AP pairs.
    static func rewardCategory(_ category: Int) -> String {
        switch category {
        case 0: "普通Ⅰ"
        case 1: "普通Ⅱ"
        case 2: "快弹"
        case 3: "地雷"
        case 4: "爆破"
        case 5: "燃烧"
        case 6: "穿甲Ⅰ"
        case 7: "穿甲Ⅱ"
        default: "类别\(category)"
        }
    }

    /// Intro card title/subtitle from the stage content id
    /// (`<theme>_<number>_<name>`), e.g. "STAGE 01" / "首战防御".
    static func stageCard(_ stageID: String?) -> (title: String, subtitle: String) {
        guard let stageID else { return ("STAGE", "") }
        let parts = stageID.split(separator: "_")
        let number = parts.count > 1 ? Int(parts[1]) : nil
        let title = number.map { String(format: "STAGE %02d", $0) } ?? "STAGE"
        let name = parts.count > 2 ? parts[2...].joined(separator: "_") : ""
        let subtitle: String = switch name {
        case "first_defense": "首战防御"
        default: name.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return (title, subtitle)
    }

    /// Outcome text: truthful per loss reason (R15-05) — the base fell, the
    /// player ran out of lives, or an unnamed failure.
    static func outcomeTitle(won: Bool, lossReason: String?) -> String {
        guard !won else { return "任务完成" }
        return switch lossReason {
        case "base_destroyed": "基地失守"
        case "player_eliminated": "全军覆没"
        default: "任务失败"
        }
    }

    /// Results-panel row label for an enemy archetype id.
    static func archetype(_ id: String) -> String {
        let family = id.split(separator: "_").first.map(String.init) ?? id
        let base: String = switch family {
        case "light": "轻型"
        case "fast": "快速"
        case "power": "火力"
        case "armor", "heavy": "重装"
        case "rapid": "速射"
        case "ap": "穿甲"
        case "explosion": "爆破"
        case "fire": "喷火"
        case "mine": "布雷"
        default: family
        }
        return base + "坦克"
    }
}

/// Root view — the playable VS-01 stage, or the free-play lab with
/// `MOVEMENT_LAB=1`: SpriteKit full-map presentation,
/// touch controls, hardware keyboard and controller, provisional HUD.
public struct MovementLabView: View {
    @State private var controller = MovementLabController()
    @State private var scene: MovementLabScene?
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    @State private var selectedWeapon = "rapid"
    @State private var powerLevel = 0
    @State private var showWeaponPanel = false
    @State private var hudTick = 0
    /// Stage-flow state mirrored from the controller at 30 Hz; SwiftUI
    /// animates each transition (ADR-0011 timings) when it changes.
    @State private var flowPhase: StageFlow.Phase = .playing
    @State private var panelRows = 0
    /// Results-table tank icons by reward category, composed once from the
    /// scene's art (ADR-0012; the reference shows a tank per category).
    @State private var tankIcons: [Int: CGImage] = [:]

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
                if !Self.isIntro(flowPhase), !Self.isDimmed(flowPhase) {
                    TouchControlsView(controller: controller)
                        .ignoresSafeArea()
                }
                #endif
                if controller.isLab { weaponDebugPanel }
                stageHUD
                stageFlowOverlay(size: geometry.size)
            }
            .onChange(of: geometry.size) { _, size in scene?.surfaceDidChange(to: size) }
            .onReceive(flowTimer) { _ in syncFlow() }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .persistentSystemOverlays(.hidden)
        .deferringBottomSystemGestures() // ADR-0004 §1
        .onAppear { if scenePhase == .active { controller.start() } }
        .onDisappear { controller.stop() }
        .onChange(of: scenePhase) { _, phase in
            scene?.isPaused = phase != .active // parks SKActions while inactive
            // §17.5: losing the active state pauses immediately; returning
            // resumes with a fresh clock (no tick burst).
            if phase == .active { controller.start() } else { controller.suspend() }
        }
        .onReceive(hudTimer) { _ in hudTick &+= 1 }
    }

    /// Provisional stage HUD (§12.2): player panel (lives, armor, weapon and
    /// ammunition, power/speed, equipment, status) and the shared panel
    /// (enemies remaining, base durability/shield, score). Safe-area aware;
    /// two compact rows so nothing is clipped on the 390-point floor.
    @ViewBuilder private var stageHUD: some View {
        if controller.stagePhase != nil, !Self.isIntro(flowPhase) {
            let hud = controller.hud
            VStack(spacing: 4) {
                HStack(spacing: 14) {
                    Label("\(hud.lives)", systemImage: "heart.fill").foregroundStyle(.red)
                    Label("\(hud.enemiesLeft)", systemImage: "shield.lefthalf.filled").foregroundStyle(.orange)
                    Label("\(hud.baseHP)/\(hud.baseMaxHP)\(hud.shield ? "🛡" : "")", systemImage: "house.fill")
                        .foregroundStyle(hud.baseHP > 1 ? .green : .red)
                    Text("\(hud.score)").foregroundStyle(.yellow)
                }
                HStack(spacing: 14) {
                    if hud.lifeState == .eliminated {
                        Text("已阵亡").foregroundStyle(.red)
                    } else if hud.lifeState == .awaitingRespawn {
                        Text("重生中…").foregroundStyle(.cyan)
                    } else {
                        Text("护甲 \(hud.armor)/\(hud.maxArmor)").foregroundStyle(hud.armor > 1 ? .white : .red)
                        Text("\(HUDLabels.weapon(hud.weaponID)) \(hud.ammo)/\(hud.maxAmmo)").foregroundStyle(.orange)
                        Text("火力\(hud.powerLevel) 速度\(hud.speedLevel)").foregroundStyle(.white)
                        Text("装备 \(HUDLabels.equipment(hud.equipmentID))").foregroundStyle(.mint)
                        if hud.invincible { Text("无敌").foregroundStyle(.yellow) }
                    }
                }
            }
            .id(hudTick)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.55)))
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
        case .outroText: .easeOut(duration: 0.35)
        case .outroFade: .easeInOut(duration: 0.5)
        case .panelIn: .easeOut(duration: 0.5)
        default: nil
        }
        if let animation { withAnimation(animation) { flowPhase = phase } } else { flowPhase = phase }
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
        let card = HUDLabels.stageCard(controller.stageID)
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
                Color.black.opacity(0.82).ignoresSafeArea()
            }
            if controller.flow.showsOutcomeText, flowPhase != .outroDelay {
                let won = controller.flow.outcome == .won
                Text(HUDLabels.outcomeTitle(won: won, lossReason: controller.flow.lossReason))
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(won ? Color.yellow : Color.red)
                    .shadow(color: .black, radius: 0, x: 2, y: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, size.height * 0.14)
                    .transition(.offset(y: size.height * 0.36)) // rises from the centre
            }
            if flowPhase != .outroFade, Self.isDimmed(flowPhase) {
                // Below the outcome title, on the left (reference: title at
                // 11–17 % of the height, panel from 26 % down).
                resultsPanel(size: size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, size.width * 0.07)
                    .padding(.top, size.height * 0.23)
                    .transition(.move(edge: .leading))
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
        let width = min(size.width * 0.42, 380)
        let compact = size.height < 420
        let rowFont = Font.system(size: compact ? 15 : 17, weight: .bold, design: .monospaced)
        let iconScale: CGFloat = compact ? 1.0 : 1.25
        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Text("战斗成绩")
                    .font(.system(size: compact ? 22 : 26, weight: .heavy))
                    .foregroundStyle(Color(red: 0.86, green: 0.42, blue: 0.96))
                    .shadow(color: .black, radius: 0, x: 1, y: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 6 : 9)
                if controller.flow.showsReward {
                    Text("Reward +\(controller.clearBonus.reward)")
                        .font(.system(size: compact ? 18 : 21, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.yellow)
                        .shadow(color: .black, radius: 0, x: 1, y: 1)
                        .padding(.top, compact ? 4 : 7)
                        .transition(.offset(y: 60).combined(with: .opacity)) // rises from the table
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
                        Text("×\(row + 1) =").foregroundStyle(Color(red: 0.35, green: 0.95, blue: 0.55))
                        Text(row < panelRows ? "\(tally.rowSubtotal(row))" : "")
                            .foregroundStyle(.white)
                            .frame(width: compact ? 34 : 40, alignment: .trailing)
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
                Text("总计")
                    .font(.system(size: compact ? 18 : 21, weight: .heavy))
                    .foregroundStyle(Color(red: 0.93, green: 0.72, blue: 0.2))
                Spacer()
                Text(panelRows > KillTally.tableRows ? "\(tally.weightedTotal)" : "")
                    .font(.system(size: compact ? 26 : 30, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.yellow)
            }
            .padding(.horizontal, 14)
            .padding(.top, compact ? 4 : 6)
            HStack {
                Text("得分 \(controller.hud.score)")
                    .font(.system(size: compact ? 14 : 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                if StageFlowPresentationPolicy.restartAvailable(phase: flowPhase, outcome: controller.flow.outcome) {
                    Button {
                        controller.restart()
                    } label: {
                        Text("重新开始")
                            .font(.system(size: compact ? 15 : 17, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18).padding(.vertical, compact ? 6 : 8)
                            .background(Capsule().fill(Color.white))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, compact ? 6 : 10)
        }
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.06, green: 0.05, blue: 0.03).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.93, green: 0.72, blue: 0.2), lineWidth: 3))
        .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
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
                Text(HUDLabels.rewardCategory(category)).foregroundStyle(.white)
            }
            Text(visible ? "\(count)" : "")
                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 1.0))
                .frame(width: 24, alignment: .trailing)
        }
    }

    /// Weapon debug panel (lab only): special-weapon
    /// selector and power-level control, top-right, collapsible.
    private var weaponDebugPanel: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button(showWeaponPanel ? "武器 ▲" : "武器 ▼") { showWeaponPanel.toggle() }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.55)))
            if showWeaponPanel {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(controller.specialWeaponIDs, id: \.self) { id in
                        Button(id) {
                            selectedWeapon = id
                            controller.selectWeapon(id)
                        }
                        .font(.system(size: 12, weight: selectedWeapon == id ? .bold : .regular))
                        .foregroundStyle(selectedWeapon == id ? .yellow : .white)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { level in
                            Button("P\(level)") {
                                powerLevel = level
                                controller.setPower(level)
                            }
                            .font(.system(size: 11, weight: powerLevel == level ? .bold : .regular))
                            .foregroundStyle(powerLevel == level ? .yellow : .white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 16)
        .padding(.top, 8)
    }

    /// One scene per view; surface changes are delivered explicitly through
    /// `surfaceDidChange` (never by re-creating the scene from `body`).
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
/// loss's affordance; a win continues by itself.
enum StageFlowPresentationPolicy {
    static func resultsInteractive(phase: StageFlow.Phase) -> Bool {
        phase == .panelIn || phase == .panelHold || phase == .finished
    }

    static func restartAvailable(phase: StageFlow.Phase, outcome: StagePhase?) -> Bool {
        phase == .finished && outcome == .lost
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
