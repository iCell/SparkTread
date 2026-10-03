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

    /// The player's tank drives in, fires, and the shot becomes the spark
    /// that runs under the logo as the logo lands; the rest arrives after.
    ///
    /// Every piece is the product's own: stamping is how the stage outro
    /// puts its outcome title on screen, the spark is the name's own half,
    /// and the tank is the one the player drives, drawn from the same rig
    /// the scene uses. A tank watermark was tried on this screen and
    /// dropped — standing still, seen from above, a tank is a rectangle.
    /// Driving and firing, it is unmistakably a tank, which is why it works
    /// here and did not there (owner 2026-10-03: 增加点 logo 的坦克元素).
    @State private var tankIn = false
    @State private var stamped = false
    @State private var sparked = false
    @State private var settled = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("SparkTread")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(Color.yellow)
                .shadow(color: .black, radius: 0, x: 3, y: 3)
                .scaleEffect(stamped ? 1 : 1.4)
                .opacity(stamped ? 1 : 0)
                .overlay(alignment: .bottomLeading) { spark }
                .overlay(alignment: .bottomLeading) { tank }
                // The shot and the tank get a band of their own: without it
                // the line ran straight through 坦克大战, since the stack puts
                // the subtitle 14 pt under the logo and overlays do not move
                // it. Applied after the overlays, so their geometry is still
                // measured against the logo itself.
                .padding(.bottom, 24)
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

    /// The shot: a hot leading edge dragging a yellow trail, fired along the
    /// logo's baseline from where the tank stops.
    private var spark: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(LinearGradient(colors: [.yellow.opacity(0), .yellow, .yellow.opacity(0.85)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: sparked ? proxy.size.width : 0, height: 4)
                .opacity(settled ? 0.6 : 1)
                .offset(y: proxy.size.height + 13)
        }
        .allowsHitTesting(false)
    }

    /// The tank drives in from off the left and parks at the muzzle end of
    /// the spark, where it stays as part of the title.
    @ViewBuilder private var tank: some View {
        if let image = MenuArt.playerTank {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(height: 46)
                .offset(x: tankIn ? -54 : -360, y: -8)
                .allowsHitTesting(false)
        }
    }

    private func runIntro() async {
        guard playsIntro, !stamped else {
            tankIn = true; stamped = true; sparked = true; settled = true
            return
        }
        // Drive in, fire, and let the shot carry the logo down with it.
        withAnimation(.easeOut(duration: 0.52)) { tankIn = true }
        try? await Task.sleep(for: .milliseconds(480))
        withAnimation(.easeOut(duration: 0.30)) { sparked = true }
        withAnimation(.spring(response: 0.40, dampingFraction: 0.54).delay(0.06)) { stamped = true }
        try? await Task.sleep(for: .milliseconds(420))
        withAnimation(.easeOut(duration: 0.32)) { settled = true }
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
