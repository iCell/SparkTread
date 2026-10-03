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
                            onIntroFinished: { introPlayed = true })
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
        controller = MovementLabController(campaign: run, stages: .bundled(), persistence: store)
    }

    private func startTraining() {
        model.startTraining()
        controller = MovementLabController(world: nil)
    }

    private func resumeSuspended() {
        guard let snapshot = model.resumeSuspended() else { return }
        controller = MovementLabController(resuming: snapshot, stages: .bundled(), persistence: store)
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

    /// Launch: the player's tank drives across the title band and the
    /// wordmark is what it leaves behind — revealed from the tank's rear
    /// edge, over the tracks it lays — then the tank rolls off the far side
    /// and the rest arrives (owner 2026-10-03: 坦克开过去，留下游戏标题).
    /// One animatable value drives both the tank and the reveal, so the
    /// reveal's edge IS the tank's rear and the two cannot drift apart.
    @State private var progress: Double = 0
    @State private var settled = false

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

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            TitleWordmark()
                .mask { reveal }
                .overlay { tankPass }
            Text("坦克大战")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .opacity(settled ? 1 : 0)
                .offset(y: settled ? 0 : 10)
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
        .task { await runIntro() }
    }

    /// The tank's rear edge for the current progress, in the wordmark's own
    /// space: it enters from beyond the leading edge and exits well past the
    /// trailing one.
    private func tankRear(width: CGFloat) -> CGFloat {
        -Self.tankLength + (width + Self.tankLength + Self.exitRun) * progress
    }

    /// Everything from the wordmark's leading edge to the tank's rear is
    /// visible; the rest is still under the tank, or not yet reached.
    private var reveal: some View {
        GeometryReader { proxy in
            Rectangle()
                .frame(width: max(0, min(proxy.size.width, tankRear(width: proxy.size.width))))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var tankPass: some View {
        if let image = MenuArt.playerTank {
            GeometryReader { proxy in
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(height: Self.tankHeight)
                    // Riding on the tracks under the baseline, hull over the
                    // bottom of the letters it has just left behind.
                    .position(x: tankRear(width: proxy.size.width) + Self.tankLength / 2,
                              y: proxy.size.height - 10)
            }
            .allowsHitTesting(false)
        }
    }

    private func runIntro() async {
        guard playsIntro, progress == 0 else {
            progress = 1
            settled = true
            return
        }
        withAnimation(.easeInOut(duration: 1.35)) { progress = 1 }
        // The subtitle and buttons come up once the title is fully out from
        // under the tank, while it is still rolling off the far side.
        try? await Task.sleep(for: .milliseconds(860))
        withAnimation(.easeOut(duration: 0.34)) { settled = true }
        onIntroFinished()
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


/// The wordmark. Two materials the game is made of: "Spark" in the fire
/// yellow the menus accent with, "Tread" in the arena's own steel; a hard
/// extruded block under both — stepped copies, no blur, so it keeps the
/// edges pixel art has — a dark rim, and under the baseline the two tracks
/// the tank left when it drove through. Plain type was the owner's
/// complaint (2026-10-03: 标题可以设计一下，而不是很单调的字体).
struct TitleWordmark: View {
    private static let font = Font.system(size: 58, weight: .black, design: .rounded)
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
            .stroke(Color.black.opacity(0.6), style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
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
