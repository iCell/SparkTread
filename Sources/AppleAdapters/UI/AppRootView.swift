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

    public init(campaign: CampaignDefinition?, progress: CampaignProgress? = nil,
                suspended: SuspendedSession? = nil, autostart: Bool = false, lab: Bool = false) {
        self.campaign = campaign
        if let progress, progress.campaignID == campaign?.id {
            completedStageIDs = Set(progress.completedStageIDs)
            checkpoint = progress.checkpoint
        }
        if let suspended, suspended.run.campaign.id == campaign?.id { self.suspended = suspended }
        if lab { screen = .playing(stageIndex: nil) }
        else if autostart, campaign != nil { screen = .playing(stageIndex: 0) }
    }

    /// The run a stage card starts: the checkpoint when it is that stage,
    /// else the campaign-start state on that stage.
    public func run(forStageIndex index: Int) -> CampaignRun? {
        guard let campaign, isUnlocked(stageIndex: index) else { return nil }
        if let checkpoint, checkpoint.stageIndex == index { return checkpoint }
        return CampaignRun(campaign: campaign, stageIndex: index)
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
    private let campaign: CampaignDefinition?
    private let store: CampaignPersistence?

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
                            onTraining: { discardSuspended(); startTraining() })
            case .campaignSelect:
                if let campaign {
                    CampaignSelectScreen(campaign: campaign, model: model,
                                         onSelect: { index in if let run = model.run(forStageIndex: index) { start(run) } },
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

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("SparkTread")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(Color.yellow)
                .shadow(color: .black, radius: 0, x: 3, y: 3)
            Text("坦克大战")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
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
            Spacer().frame(height: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let onSelect: (Int) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: onBack) {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text("选择关卡")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Color.yellow)
                Spacer()
                Color.clear.frame(width: 60, height: 1)
            }
            .padding(.horizontal, 24)
            HStack(spacing: 18) {
                ForEach(Array(campaign.stageIDs.enumerated()), id: \.offset) { index, id in
                    let card = HUDLabels.stageCard(id)
                    let unlocked = model.isUnlocked(stageIndex: index)
                    let completed = model.completedStageIDs.contains(id)
                    Button { onSelect(index) } label: {
                        VStack(spacing: 8) {
                            Text(card.title)
                                .font(.system(size: 22, weight: .black, design: .rounded))
                            Text(card.subtitle)
                                .font(.system(size: 15, weight: .bold))
                            Text(completed ? "已通关" : unlocked ? "可进入" : "未解锁")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(completed ? Color.green : unlocked ? Color.yellow : Color.gray)
                        }
                        .foregroundStyle(unlocked ? Color.white : Color.gray)
                        .frame(width: 150, height: 120)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.06, green: 0.05, blue: 0.03).opacity(0.95)))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(index == model.suggestedStageIndex ? Color.yellow : Color.gray.opacity(0.5),
                                    lineWidth: index == model.suggestedStageIndex ? 3 : 1.5))
                    }
                    .disabled(!unlocked)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
