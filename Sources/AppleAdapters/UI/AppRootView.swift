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
    /// Stages completed this app run (persisted campaign progress arrives
    /// with the checkpoint save; until then the unlock state lives here).
    public private(set) var completedStageIDs: Set<String> = []
    public let campaign: CampaignDefinition?

    public init(campaign: CampaignDefinition?, autostart: Bool = false, lab: Bool = false) {
        self.campaign = campaign
        if lab { screen = .playing(stageIndex: nil) }
        else if autostart, campaign != nil { screen = .playing(stageIndex: 0) }
    }

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
    private let campaign: CampaignDefinition?

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
        let model = AppFlowModel(campaign: campaign, autostart: env["SPARKTREAD_AUTOSTART"] != nil, lab: lab)
        _model = State(initialValue: model)
        _controller = State(initialValue: Self.makeController(for: model.screen, campaign: campaign))
    }

    private static func makeController(for screen: AppFlowModel.Screen, campaign: CampaignDefinition?) -> MovementLabController? {
        guard case .playing(let stageIndex) = screen else { return nil }
        if let stageIndex, let campaign {
            return MovementLabController(campaign: CampaignRun(campaign: campaign, stageIndex: stageIndex), stages: .bundled())
        }
        return MovementLabController(world: nil) // the lab
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.screen {
            case .title:
                TitleScreen(hasCampaign: campaign != nil,
                            onStart: { model.openCampaignSelect() },
                            onTraining: { enter(.playing(stageIndex: nil)) })
            case .campaignSelect:
                if let campaign {
                    CampaignSelectScreen(campaign: campaign, model: model,
                                         onSelect: { index in if model.startCampaign(at: index) { enter(model.screen) } },
                                         onBack: { model.backToTitle() })
                }
            case .playing:
                if let controller {
                    MovementLabView(controller: controller) {
                        model.recordCompleted(stageIDs: controller.campaignRun?.completedStageIDs ?? [])
                        self.controller = nil
                        model.backToTitle()
                    }
                    .id(ObjectIdentifier(controller))
                }
            }
        }
        .persistentSystemOverlays(.hidden)
    }

    private func enter(_ screen: AppFlowModel.Screen) {
        controller = Self.makeController(for: screen, campaign: campaign)
        if case .playing(let index) = screen, index == nil { model.startTraining() }
    }
}

/// Title (plan §12.1 "Title"; manifest §J lists art for it — this is the
/// provisional text treatment until Phase 1 art is authorized).
struct TitleScreen: View {
    let hasCampaign: Bool
    let onStart: () -> Void
    let onTraining: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("SparkTread")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(Color.yellow)
                .shadow(color: .black, radius: 0, x: 3, y: 3)
            Text("坦克大战")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            if hasCampaign {
                titleButton("开始战役", action: onStart)
            }
            titleButton("训练场", action: onTraining)
            Spacer().frame(height: 30)
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
