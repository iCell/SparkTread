import Foundation
import GameApplication
import GameCore
import SwiftUI

/// Screen flow (plan §12.1): Title → Campaign / Stage Select → the game
/// screen (intro, play, pause overlay, results) → back to the title. Pure
/// state in `AppFlowModel`; this view renders it. Launch environment:
/// `SPARKTREAD_AUTOSTART=1` skips the title into the campaign (the render
/// smoke test), `MOVEMENT_LAB=1` into the lab.
public struct AppFlowModel: Equatable, Sendable {
    public enum Screen: Equatable, Sendable {
        case title
        case campaignSelect
        /// The game screen; `stageIndex` is nil for the lab.
        case playing(stageIndex: Int?)
    }

    public private(set) var screen: Screen = .title
    /// Completed stages (from the progress document, plus this run).
    public private(set) var completedStageIDs: Set<String> = []
    /// The run to continue from (progress checkpoint), if any.
    public private(set) var checkpoint: CampaignRun?
    /// A mid-stage snapshot offered on the title, if any.
    public private(set) var suspended: SuspendedSession?
    public let campaign: CampaignDefinition?
    /// The difficulty new runs start on (plan §5.1 presets); a checkpoint
    /// run keeps its own.
    public var difficultyID: String = CampaignRun.defaultDifficultyID
    public static let difficultyIDs = ["casual", "standard", "veteran"]

    public init(campaign: CampaignDefinition?, progress: CampaignProgress? = nil,
                suspended: SuspendedSession? = nil, autostart: Bool = false, lab: Bool = false) {
        self.campaign = campaign
        if let progress, progress.campaignID == campaign?.id {
            completedStageIDs = Set(progress.completedStageIDs)
            checkpoint = progress.checkpoint
            if let checkpoint = progress.checkpoint { difficultyID = checkpoint.difficultyID }
        }
        if let suspended, suspended.run.campaign.id == campaign?.id { self.suspended = suspended }
        if lab { screen = .playing(stageIndex: nil) }
        else if autostart, campaign != nil { screen = .playing(stageIndex: 0) }
    }

    /// The run a stage card starts: the checkpoint when it is that stage,
    /// else the campaign-start state on that stage.
    public func run(forStageIndex index: Int) -> CampaignRun? {
        guard let campaign, isUnlocked(stageIndex: index) else { return nil }
        if let checkpoint, checkpoint.stageIndex == index, checkpoint.difficultyID == difficultyID { return checkpoint }
        return CampaignRun(campaign: campaign, stageIndex: index, difficultyID: difficultyID)
    }

    /// Resuming the snapshot leaves the title; declining discards it.
    public mutating func resumeSuspended() -> SuspendedSession? {
        guard let suspended else { return nil }
        screen = .playing(stageIndex: suspended.run.stageIndex)
        return suspended
    }

    public mutating func discardSuspended() { suspended = nil }

    public mutating func openCampaignSelect() { screen = .campaignSelect }
    public mutating func startTraining() { screen = .playing(stageIndex: nil) }
    public mutating func backToTitle() { screen = .title }

    /// A stage is playable when it is the first or its predecessor was
    /// completed (plan §5.1: selection understandable, not hidden behind
    /// difficulty).
    public func isUnlocked(stageIndex: Int) -> Bool {
        guard let campaign, campaign.stageIDs.indices.contains(stageIndex) else { return false }
        return stageIndex == 0 || completedStageIDs.contains(campaign.stageIDs[stageIndex - 1])
    }

    /// The stage a fresh run should start on: the first not yet completed.
    public var suggestedStageIndex: Int {
        guard let campaign else { return 0 }
        return campaign.stageIDs.firstIndex { !completedStageIDs.contains($0) } ?? 0
    }

    /// Starts the campaign on an unlocked stage (returns false otherwise).
    @discardableResult
    public mutating func startCampaign(at stageIndex: Int) -> Bool {
        guard isUnlocked(stageIndex: stageIndex) else { return false }
        screen = .playing(stageIndex: stageIndex)
        return true
    }

    public mutating func recordCompleted(stageIDs: some Sequence<String>) {
        completedStageIDs.formUnion(stageIDs)
    }
}

public struct AppRootView: View {
    @State private var model: AppFlowModel
    @State private var controller: MovementLabController?
    @State private var storeNotice: String?
    /// The launch sequence is for the launch: backing out of a menu onto
    /// the title again should not replay it.
    @State private var introPlayed = false
    private let campaign: CampaignDefinition?
    private let store: CampaignPersistence?
    /// The app's one mixer. Built here, under the launch screen, so the
    /// voice pools warm once instead of at the first game start — and so
    /// the title can play the launch tread through the same instance every
    /// controller is handed, rather than a second set of preloaded voices.
    private let audio: GameAudio
    /// Each stage's own map, for the select screen's card art. Decoded once
    /// here with the campaign rather than per card: twelve small files, and
    /// a card must never do file I/O while the list is scrolling.
    private let stageMaps: [String: StagePreview.Map]

    public init() {
        let env = ProcessInfo.processInfo.environment
        let lab = env["MOVEMENT_LAB"] != nil
        var campaign: CampaignDefinition?
        if !lab {
            // A missing or invalid bundled campaign is a build error (§15.4).
            do { campaign = try CampaignLoader.load(id: MovementLabController.bundledCampaignID, bundle: .main) }
            catch { fatalError("bundled campaign failed to load: \(error)") }
        }
        self.campaign = campaign
        var maps: [String: StagePreview.Map] = [:]
        for stageID in campaign?.stageIDs ?? [] {
            // The campaign loader already proved every stage decodes; a card
            // without art is a missing background, never a failure to start.
            if let url = try? StageLoader.stageURL(id: stageID, bundle: .main),
               let def = try? StageLoader.loadDefinition(at: url) {
                maps[stageID] = StagePreview.map(of: def)
            }
        }
        stageMaps = maps
        audio = GameAudio()
        // The save store: an unusable store or an unreadable document is a
        // notice on the title, never a crash (the file stays for inspection).
        var store: CampaignPersistence?
        var notice: String?
        var progress: CampaignProgress?
        var suspended: SuspendedSession?
        if !lab, env["SPARKTREAD_NO_SAVE"] == nil {
            do {
                let file = try FileSaveStore.standard()
                store = file
                do { progress = try file.loadProgress() } catch { notice = "进度存档无法读取：\(error)" }
                do { suspended = try file.loadSuspended() } catch { notice = "上次战斗存档无法读取：\(error)" }
            } catch {
                notice = "存档目录不可用：\(error)"
            }
        }
        self.store = store
        let model = AppFlowModel(campaign: campaign, progress: progress, suspended: suspended,
                                 autostart: env["SPARKTREAD_AUTOSTART"] != nil, lab: lab)
        _model = State(initialValue: model)
        _storeNotice = State(initialValue: notice)
        _controller = State(initialValue: Self.makeController(for: model.screen, run: model.run(forStageIndex: 0),
                                                              store: store))
    }

    private static func makeController(for screen: AppFlowModel.Screen, run: CampaignRun?,
                                       store: CampaignPersistence?) -> MovementLabController? {
        guard case .playing(let stageIndex) = screen else { return nil }
        if stageIndex != nil, let run {
            return MovementLabController(campaign: run, stages: .bundled(), persistence: store)
        }
        return MovementLabController(world: nil) // the lab
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.screen {
            case .title:
                TitleScreen(hasCampaign: campaign != nil,
                            canResume: model.suspended != nil,
                            canContinue: model.checkpoint != nil,
                            notice: storeNotice,
                            onResume: resumeSuspended,
                            onContinue: { if let run = model.checkpoint { start(run) } },
                            onStart: { discardSuspended(); model.openCampaignSelect() },
                            onTraining: { discardSuspended(); startTraining() },
                            playsIntro: !introPlayed,
                            onIntroFinished: { introPlayed = true },
                            audio: audio)
            case .campaignSelect:
                if let campaign {
                    CampaignSelectScreen(campaign: campaign, model: model, stageMaps: stageMaps,
                                         onSelect: { index in if let run = model.run(forStageIndex: index) { start(run) } },
                                         onDifficulty: { id in model.difficultyID = id },
                                         onBack: { model.backToTitle() })
                }
            case .playing:
                if let controller {
                    MovementLabView(controller: controller) { leaveGame(controller) }
                        .id(ObjectIdentifier(controller))
                }
            }
        }
        .persistentSystemOverlays(.hidden)
    }

    private func start(_ run: CampaignRun) {
        guard model.startCampaign(at: run.stageIndex) else { return }
        controller = MovementLabController(campaign: run, stages: .bundled(), audio: audio, persistence: store)
    }

    private func startTraining() {
        model.startTraining()
        controller = MovementLabController(world: nil, audio: audio)
    }

    private func resumeSuspended() {
        guard let snapshot = model.resumeSuspended() else { return }
        controller = MovementLabController(resuming: snapshot, stages: .bundled(), audio: audio, persistence: store)
    }

    /// Declining the snapshot discards it (§17.5).
    private func discardSuspended() {
        guard model.suspended != nil else { return }
        model.discardSuspended()
        try? store?.clearSuspended()
    }

    private func leaveGame(_ controller: MovementLabController) {
        model.recordCompleted(stageIDs: controller.campaignRun?.completedStageIDs ?? [])
        if let failure = controller.persistenceFailure { storeNotice = "存档失败：\(failure)" }
        self.controller = nil
        model.discardSuspended()
        model.backToTitle()
    }
}

/// Title (plan §12.1 "Title"; manifest §J lists art for it — this is the
/// provisional text treatment until Phase 1 art is authorized).
struct TitleScreen: View {
    let hasCampaign: Bool
    var canResume = false
    var canContinue = false
    var notice: String?
    var onResume: () -> Void = {}
    var onContinue: () -> Void = {}
    let onStart: () -> Void
    let onTraining: () -> Void
    /// The launch sequence runs once per app start, not every time the
    /// player backs out of a menu onto the title again.
    var playsIntro = false
    var onIntroFinished: () -> Void = {}
    /// Where the launch tread plays; nil renders the intro silent (previews,
    /// tests).
    var audio: GameAudio?

    /// The launch sequence's sound (owner 2026-10-03: the drive should have
    /// music, and the music can be the treads): the tank heard on its
    /// tracks from the moment it is in frame, receding as it drives off. The
    /// game has no engine or tread voice (owner, 2026-09-10, ADR-0011); the
    /// launch is the one place a tank is heard moving. The cue's own
    /// envelope ends with the drive, so nothing here has to stop it.
    static let treadCue = "sfx_title_tread"

    /// The two shots the tank fires as it comes in (owner 2026-10-03: 开过去
    /// 的时候再放两枪，并加上两声子弹音). They are the game's own gun: the
    /// second follows the first at the normal weapon's LV1 cooldown
    /// (GAME_RULES §5.3), the shells outrun the tank by the game's own
    /// shell-to-tank speed ratio, and the voice is the normal shot's — so
    /// the title's tank shoots like the one the player is about to drive,
    /// only at the intro's pace.
    static let shotCue = "sfx_fire_normal"
    static let firstShotTime: TimeInterval = 0.4
    static var shotTimes: [TimeInterval] {
        let ticks = WeaponRuleset.provisional.weapon("normal")?.cooldownTicks.first ?? 35
        return [firstShotTime, firstShotTime + Double(ticks) / Double(MovementRuleset.ticksPerSecond)]
    }
    /// Shell speed over tank speed in the game: 6.4 cells/s over 1.92.
    static var shellSpeedRatio: CGFloat {
        let shell = WeaponRuleset.provisional.weapon("normal")?.initialSpeedMilliSubunitsPerSecond ?? 6_553_600
        return CGFloat(shell) / CGFloat(MovementRuleset.provisional.baseSpeedMilliSubunitsPerSecond)
    }
    /// How long the muzzle flash shows — the scene's own tenth of a second.
    static let flashDuration: TimeInterval = 0.1

    /// Launch: the player's tank drives across the title band and the
    /// wordmark is what it leaves behind — revealed from the tank's rear
    /// edge, over the tracks it lays — then the tank rolls off the far side
    /// and the rest arrives (owner 2026-10-03: 坦克开过去，留下游戏标题).
    /// One animatable value drives both the tank and the reveal, so the
    /// reveal's edge IS the tank's rear and the two cannot drift apart.
    @State private var progress: Double = 0
    @State private var settled = false
    /// The wordmark's measured width; the drive's timing is derived from it.
    @State private var wordWidth: CGFloat = 0

    /// How fast the tank rolls, in points per second. Owner on the first
    /// cut: too fast — and it was eased, so it was FASTEST over the word,
    /// which is the one stretch that has to be read. A tank crosses at one
    /// deliberate speed; the duration falls out of the distance.
    private static let tankSpeed: CGFloat = 170

    private static let tankHeight: CGFloat = 50
    /// The right-facing sprite's length at that height (its body is wider
    /// than tall), used to start the run off the leading edge.
    private static let tankLength: CGFloat = 66
    /// How far past the wordmark's trailing edge the tank keeps going, so it
    /// leaves the SCREEN rather than parking beside the title. Sized for
    /// iPhone landscape: at 956 pt the centred word leaves ≈313 pt of margin,
    /// and 460 − 66 (the tank's length) clears it; iPad widths are a later
    /// milestone and would want this measured from the screen instead.
    private static let exitRun: CGFloat = 460

    /// The drive's two legs, in seconds, for a wordmark of `wordWidth`:
    /// `crossing` ends when the tank's rear clears the word — the title is
    /// complete and the buttons rise — and `total` when the tank has left.
    /// The tread cue is cut to this timeline (`TitleIntroAudioTests` holds
    /// the two together), so the constants above cannot move on their own.
    static func introTimeline(wordWidth: CGFloat) -> (shots: [TimeInterval], crossing: TimeInterval, total: TimeInterval) {
        let crossing = wordWidth + tankLength
        return (shotTimes, Double(crossing / tankSpeed), Double((crossing + exitRun) / tankSpeed))
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            TitleWordmark()
                .modifier(TankReveal(progress: progress, tankLength: Self.tankLength,
                                     exitRun: Self.exitRun, tankHeight: Self.tankHeight,
                                     tank: MenuArt.playerTank,
                                     shots: Self.shotTimes.map { CGFloat($0) * Self.tankSpeed },
                                     flashTravel: CGFloat(Self.flashDuration) * Self.tankSpeed,
                                     shellSpeedRatio: Self.shellSpeedRatio,
                                     muzzle: MenuArt.playerTankMuzzle,
                                     shell: MenuArt.sprite("px_projectile_normal"),
                                     flash: MenuArt.sprite("px_fx_muzzle_0"),
                                     flashAnchor: MenuArt.anchor(of: "px_fx_muzzle_0")))
                .background { GeometryReader { proxy in
                    Color.clear.onAppear { wordWidth = proxy.size.width }
                } }
            Spacer()
            Group {
            if hasCampaign, canResume {
                titleButton("继续上次战斗", action: onResume)
            }
            if hasCampaign, canContinue, !canResume {
                titleButton("继续战役", action: onContinue)
            }
            if hasCampaign {
                titleButton(canResume || canContinue ? "新的战役" : "开始战役", action: onStart)
            }
            titleButton("训练场", action: onTraining)
            if let notice {
                Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.orange)
                    .lineLimit(2)
                    .padding(.horizontal, 30)
            }
            }
            .opacity(settled ? 1 : 0)
            .offset(y: settled ? 0 : 14)
            Spacer().frame(height: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MenuBackdrop())
        .onAppear { runIntro() }
    }

    private func runIntro() {
        guard playsIntro, progress == 0 else {
            progress = 1
            settled = true
            return
        }
        // Measured on first layout; the fallback is the word's width at this
        // font, so a missed measurement shifts the hand-off by milliseconds.
        let width = wordWidth > 0 ? wordWidth : 370
        let drive = Self.introTimeline(wordWidth: width)
        // The treads start with the first frame of the drive; the cue
        // recedes and ends on the same timeline by construction.
        audio?.play(Self.treadCue)
        // One linear leg per milestone, all at the same speed, so the motion
        // is continuous and everything that happens along it — a shot, the
        // buttons rising the moment the title is out from under the tank —
        // is a completion, not a sleep that has to agree with the animation
        // about how long it took. The shells draw themselves from the same
        // progress the tank moves on; only their voice needs a moment.
        var milestones: [(at: TimeInterval, then: () -> Void)] = drive.shots.map { at in
            (at, { audio?.play(Self.shotCue) })
        }
        milestones.append((drive.crossing, {
            withAnimation(.easeOut(duration: 0.4)) { settled = true }
            onIntroFinished()
        }))
        milestones.append((drive.total, {}))
        advance(through: milestones[...], from: 0, total: drive.total)
    }

    private func advance(through milestones: ArraySlice<(at: TimeInterval, then: () -> Void)>,
                         from start: TimeInterval, total: TimeInterval) {
        guard let next = milestones.first else { return }
        withAnimation(.linear(duration: next.at - start)) {
            progress = next.at / total
        } completion: {
            next.then()
            advance(through: milestones.dropFirst(), from: next.at, total: total)
        }
    }

    private func titleButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.black)
                .frame(minWidth: 220)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.white))
        }
    }
}


/// Drives the launch reveal from ONE interpolated value.
///
/// SwiftUI animates a modifier's `animatableData` per frame and re-evaluates
/// its body at each step, so the mask's edge and the tank's position are
/// recomputed together from the same progress every frame. Derived from a
/// plain animated @State they were not: SwiftUI interpolated each modifier
/// between its start and end VALUES over the whole duration, and because the
/// reveal is clamped to the word, its edge crawled across the word for the
/// entire run while the unclamped tank moved at the declared speed. Measured
/// on 2026-10-03 with timestamped screenshots: the edge at ≈112 pt/s against
/// a declared 270, and the buttons arriving with the title 80 % revealed.
struct TankReveal: ViewModifier, Animatable {
    var progress: Double
    let tankLength: CGFloat
    let exitRun: CGFloat
    let tankHeight: CGFloat
    let tank: CGImage?
    /// The shots: the travel (points since the nose entered the band) at
    /// which each is fired, how far the tank travels while a flash shows,
    /// how much faster than the tank a shell flies, and the art — the gun's
    /// muzzle in icon pixels, the scene's shell, its first flash frame and
    /// that frame's anchor (the point that sits on the muzzle).
    var shots: [CGFloat] = []
    var flashTravel: CGFloat = 0
    var shellSpeedRatio: CGFloat = 1
    var muzzle: CGPoint?
    var shell: CGImage?
    var flash: CGImage?
    var flashAnchor: UnitPoint?

    // `Animatable` is a nonisolated protocol while a ViewModifier is
    // main-actor isolated; the interpolated value is a plain Double, so the
    // accessor can be nonisolated without crossing anything that matters.
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .mask {
                GeometryReader { proxy in
                    // Everything from the leading edge to the tank's rear.
                    Rectangle()
                        .frame(width: max(0, min(proxy.size.width, rear(proxy.size.width))))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transaction { $0.animation = nil }   // the per-frame value IS the motion
                }
            }
            .overlay {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    // Riding on the tracks under the baseline, hull over the
                    // bottom of the letters it has just left behind.
                    let tankY = proxy.size.height - 10
                    if let tank {
                        Image(decorative: tank, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(height: tankHeight)
                            .position(x: rear(width) + tankLength / 2, y: tankY)
                            .transaction { $0.animation = nil }
                    }
                    // The shells and the flash are the scene's own sprites at
                    // the scene's proportions to the tank (projectiles at 0.8
                    // of the art scale, the flash at 0.48), turned a quarter
                    // to face the way it drives. A shell leaves the muzzle
                    // where the gun WAS when it fired and flies on its own;
                    // the flash rides the muzzle for its tenth of a second.
                    if let tank, let muzzle {
                        let scale = tankHeight / CGFloat(tank.height)
                        let travel = rear(width) + tankLength
                        ForEach(Array(shots.enumerated()), id: \.offset) { _, fired in
                            if travel >= fired {
                                let flown = travel - fired
                                let gun = muzzlePoint(muzzle, tank: tank, scale: scale,
                                                      rear: rear(width) - flown, y: tankY)
                                if let shell {
                                    let side = CGFloat(shell.width) * scale * 0.8
                                    Image(decorative: shell, scale: 1)
                                        .interpolation(.none)
                                        .resizable()
                                        .frame(width: side, height: side)
                                        .rotationEffect(.degrees(90))
                                        .position(x: gun.x + flown * shellSpeedRatio, y: gun.y)
                                        .transaction { $0.animation = nil }
                                }
                                if let flash, let flashAnchor, flown < flashTravel {
                                    let now = muzzlePoint(muzzle, tank: tank, scale: scale,
                                                          rear: rear(width), y: tankY)
                                    let side = CGFloat(flash.width) * scale * 0.48
                                    // The frame points up with its anchor on
                                    // the muzzle: place the anchor there and
                                    // turn the frame about it.
                                    Image(decorative: flash, scale: 1)
                                        .interpolation(.none)
                                        .resizable()
                                        .frame(width: side, height: side)
                                        .rotationEffect(.degrees(90), anchor: flashAnchor)
                                        .position(x: now.x - (flashAnchor.x - 0.5) * side,
                                                  y: now.y - (flashAnchor.y - 0.5) * side)
                                        .transaction { $0.animation = nil }
                                }
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
            }
    }

    /// The gun's muzzle for a tank whose rear edge is `rear`: the icon is
    /// drawn `tankHeight` tall with its aspect kept, centred on the tank's
    /// point, and the muzzle is a pixel position inside it.
    private func muzzlePoint(_ muzzle: CGPoint, tank: CGImage, scale: CGFloat,
                             rear: CGFloat, y: CGFloat) -> CGPoint {
        let size = CGSize(width: CGFloat(tank.width) * scale, height: tankHeight)
        let topLeft = CGPoint(x: rear + tankLength / 2 - size.width / 2, y: y - size.height / 2)
        return CGPoint(x: topLeft.x + muzzle.x * scale, y: topLeft.y + muzzle.y * scale)
    }

    /// The tank's rear edge in the wordmark's space: it enters from beyond
    /// the leading edge and exits well past the trailing one.
    private func rear(_ width: CGFloat) -> CGFloat {
        -tankLength + (width + tankLength + exitRun) * progress
    }
}

/// The wordmark. Two materials the game is made of: "Spark" in the fire
/// yellow the menus accent with, "Tread" in the arena's own steel; a hard
/// extruded block under both — stepped copies, no blur, so it keeps the
/// edges pixel art has — a dark rim, and under the baseline the two tracks
/// the tank left when it drove through. Plain type was the owner's
/// complaint (2026-10-03: 标题可以设计一下，而不是很单调的字体).
struct TitleWordmark: View {
    private static let font = Font.system(size: 62, weight: .black, design: .rounded)
    private static let depth = 5
    private static let rim: CGFloat = 1.3
    private static let rimOffsets: [CGSize] = [
        CGSize(width: -rim, height: 0), CGSize(width: rim, height: 0),
        CGSize(width: 0, height: -rim), CGSize(width: 0, height: rim),
        CGSize(width: -rim, height: -rim), CGSize(width: rim, height: -rim),
        CGSize(width: -rim, height: rim), CGSize(width: rim, height: rim),
    ]
    // Faces: fire from the menus' yellow down into orange; steel from the
    // delivery's polished fine steel down into its plate (sampled colours).
    private static let sparkFace = LinearGradient(
        colors: [Color(red: 1.00, green: 0.88, blue: 0.30), Color(red: 1.00, green: 0.62, blue: 0.08)],
        startPoint: .top, endPoint: .bottom)
    private static let treadFace = LinearGradient(
        colors: [Color(red: 0.90, green: 0.93, blue: 0.95), Color(red: 0.50, green: 0.59, blue: 0.65)],
        startPoint: .top, endPoint: .bottom)
    private static let sparkSide = Color(red: 0.46, green: 0.22, blue: 0.02)
    private static let treadSide = Color(red: 0.09, green: 0.13, blue: 0.16)

    var body: some View {
        ZStack {
            // The block the letters stand on: the word stepped down and
            // to the right, one point at a time.
            ForEach(1...Self.depth, id: \.self) { step in
                word(spark: Self.sparkSide, tread: Self.treadSide)
                    .offset(x: CGFloat(step), y: CGFloat(step))
            }
            // The rim around the face.
            ForEach(0..<Self.rimOffsets.count, id: \.self) { i in
                word(spark: Color.black, tread: Color.black)
                    .offset(x: Self.rimOffsets[i].width, y: Self.rimOffsets[i].height)
            }
            word(spark: Self.sparkFace, tread: Self.treadFace)
        }
        // The tracks hang off the word as an overlay, so they are exactly as
        // wide as the word. As a stack sibling they were a GeometryReader,
        // which took the whole screen's width — and since the title screen
        // measures this view to drive the tank and the reveal, the tank was
        // being run across the screen instead of across the word.
        .overlay(alignment: .bottom) { tracks.offset(y: 20) }
        .padding(.bottom, 22)      // the band the tracks and the tank use
    }

    private func word<S: ShapeStyle, T: ShapeStyle>(spark: S, tread: T) -> some View {
        HStack(spacing: 0) {
            Text("Spark").foregroundStyle(spark)
            Text("Tread").foregroundStyle(tread)
        }
        .font(Self.font)
        .kerning(-1.5)
    }

    /// Two dashed tracks the width of the word: what a tank leaves.
    private var tracks: some View {
        VStack(spacing: 5) {
            track
            track
        }
        .padding(.horizontal, 10)
    }

    private var track: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1.5))
                path.addLine(to: CGPoint(x: proxy.size.width, y: 1.5))
            }
            .stroke(Color.black.opacity(0.7), style: StrokeStyle(lineWidth: 3.5, dash: [9, 6]))
        }
        .frame(height: 3)
    }
}

/// Campaign / stage select (plan §12.1): one card per stage with its
/// unlock state; the suggested stage is highlighted.
struct CampaignSelectScreen: View {
    let campaign: CampaignDefinition
    let model: AppFlowModel
    var stageMaps: [String: StagePreview.Map] = [:]
    let onSelect: (Int) -> Void
    var onDifficulty: (String) -> Void = { _ in }
    let onBack: () -> Void

    static func difficultyLabel(_ id: String) -> String {
        switch id {
        case "casual": "休闲"
        case "standard": "标准"
        case "veteran": "老兵"
        default: id
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("选择关卡")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Color.yellow)
                .padding(.top, 2)
            HStack(spacing: 10) {
                Text("难度")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                ForEach(AppFlowModel.difficultyIDs, id: \.self) { id in
                    Button { onDifficulty(id) } label: {
                        Text(Self.difficultyLabel(id))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(model.difficultyID == id ? Color.black : Color.white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(model.difficultyID == id ? Color.yellow : Color.white.opacity(0.15)))
                    }
                }
            }
            // Twelve cards are far wider than any phone: this row was a
            // plain HStack, so everything past the fifth stage was off the
            // screen with no way to reach it (owner, 2026-10-03). It scrolls
            // now, and opens on the stage you would play next.
            ScrollViewReader { scroll in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(Array(campaign.stageIDs.enumerated()), id: \.offset) { index, id in
                            StageCard(index: index, stageID: id, map: stageMaps[id],
                                      unlocked: model.isUnlocked(stageIndex: index),
                                      completed: model.completedStageIDs.contains(id),
                                      suggested: index == model.suggestedStageIndex,
                                      onSelect: onSelect)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                }
                .onAppear { scroll.scrollTo(model.suggestedStageIndex, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Owner 2026-10-03, on the capsule that replaced the plain label:
        // no border, not jammed against the top edge, and better looking.
        // So no frame at all — a yellow chevron and the word, carried over
        // the plate by a shadow instead of by a box, with the tap target
        // kept at 44 pt by padding rather than by anything drawn.
        .overlay(alignment: .topLeading) {
            Button(action: onBack) {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(Color.yellow)
                    Text("返回")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .shadow(color: .black.opacity(0.85), radius: 4, x: 0, y: 1)
                .padding(.vertical, 10)
                .padding(.trailing, 16)
                .contentShape(Rectangle())
            }
            .padding(.leading, 22)
            .padding(.top, 18)
        }
        .background(MenuBackdrop())
    }
}

/// One stage on the select screen, backed by its own map (ADR-free content
/// art: `StageCardArt` draws the stage's authored terrain, so the card shows
/// the place rather than a decoration of it).
struct StageCard: View {
    let index: Int
    let stageID: String
    let map: StagePreview.Map?
    let unlocked: Bool
    let completed: Bool
    let suggested: Bool
    let onSelect: (Int) -> Void

    private static let size = CGSize(width: 184, height: 132)

    var body: some View {
        let card = HUDLabels.stageCard(stageID)
        Button { onSelect(index) } label: {
            // The text is the view that sizes the card; the map goes in
            // `.background`, which is laid out to the view's bounds instead of
            // driving them. As a ZStack sibling a `scaledToFill` image made the
            // card wider than its own frame, and the frame then centred the
            // overflow — which clipped the title at both ends (owner report,
            // 2026-10-03: 文字被截取了).
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(card.subtitle)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(completed ? "已通关" : unlocked ? "可进入" : "未解锁")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(completed ? Color.green : unlocked ? Color.yellow : Color.gray)
            }
            .foregroundStyle(unlocked ? Color.white : Color.gray)
            .padding(.horizontal, 10)
            .padding(.bottom, 9)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .bottomLeading)
            .background {
                ZStack {
                    background
                    // The scrim: the map is busy, and the title has to stay
                    // readable over whichever stage it belongs to.
                    LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.85)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(suggested ? Color.yellow : Color.gray.opacity(0.5),
                        lineWidth: suggested ? 3 : 1.5))
        }
        .disabled(!unlocked)
    }

    @ViewBuilder private var background: some View {
        if let map, let image = StageCardArt.image(for: map, id: stageID) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)          // one pixel per cell stays one block
                .resizable()
                .scaledToFill()
                // A locked stage shows its shape, not its detail.
                .saturation(unlocked ? 1 : 0)
                .opacity(unlocked ? 1 : 0.45)
        } else {
            Color(red: 0.06, green: 0.05, blue: 0.03)
        }
    }
}
