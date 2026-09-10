import GameCore

/// A single-player run through a campaign (ADR-0013): the current stage and
/// the session state at that stage's START — the checkpoint a retry returns
/// to. Advancing consumes a won stage's exit state (plan §16.3: exit state
/// equals the next stage's initial state); a lost stage retries from the
/// checkpoint, so nothing gained in the failed attempt survives it.
public struct CampaignRun: Codable, Equatable, Sendable {
    public let campaign: CampaignDefinition
    public private(set) var stageIndex: Int
    /// Session state at the current stage's start (the checkpoint).
    public private(set) var checkpoint: SessionState
    /// Stages completed in this run, in order.
    public private(set) var completedStageIDs: [String]
    /// The difficulty the run is played on (plan §5.1; ADR-0015); fixed
    /// for the run.
    public let difficultyID: String

    public static let defaultDifficultyID = "standard"

    public init(campaign: CampaignDefinition, stageIndex: Int = 0,
                checkpoint: SessionState = .campaignStart, completedStageIDs: [String] = [],
                difficultyID: String = CampaignRun.defaultDifficultyID) {
        precondition(!campaign.stageIDs.isEmpty, "a campaign needs at least one stage")
        precondition(campaign.stageIDs.indices.contains(stageIndex), "stage index out of range")
        self.campaign = campaign
        self.stageIndex = stageIndex
        self.checkpoint = checkpoint
        self.completedStageIDs = completedStageIDs
        self.difficultyID = difficultyID
    }

    private enum CodingKeys: String, CodingKey { case campaign, stageIndex, checkpoint, completedStageIDs, difficultyID }

    /// Runs saved before difficulty existed decode as standard.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        campaign = try c.decode(CampaignDefinition.self, forKey: .campaign)
        stageIndex = try c.decode(Int.self, forKey: .stageIndex)
        checkpoint = try c.decode(SessionState.self, forKey: .checkpoint)
        completedStageIDs = try c.decode([String].self, forKey: .completedStageIDs)
        difficultyID = try c.decodeIfPresent(String.self, forKey: .difficultyID) ?? Self.defaultDifficultyID
    }

    public var stageID: String { campaign.stageIDs[stageIndex] }
    /// 1-based campaign position (the stage's `stageNumber`).
    public var stageNumber: Int { stageIndex + 1 }
    public var isLastStage: Bool { stageIndex == campaign.stageIDs.count - 1 }
    public var stageCount: Int { campaign.stageIDs.count }

    /// A won stage: records it and moves to the next stage with the exit
    /// state as the new checkpoint. Returns false — and leaves the run on
    /// the last stage with the exit state recorded — when the campaign is
    /// complete.
    @discardableResult
    public mutating func advance(exitState: SessionState) -> Bool {
        completedStageIDs.append(stageID)
        checkpoint = exitState
        guard !isLastStage else { return false }
        stageIndex += 1
        return true
    }

    /// True once every stage has been completed.
    public var isComplete: Bool { completedStageIDs.count == campaign.stageIDs.count }

    /// Domain checks for a run restored from data.
    public var validationIssues: [String] {
        var issues = CampaignValidator.validate(campaign) + checkpoint.validationIssues
        if difficultyID.isEmpty { issues.append("difficulty id is empty") }
        if !campaign.stageIDs.indices.contains(stageIndex) { issues.append("stage index \(stageIndex) out of range") }
        if completedStageIDs.count > campaign.stageIDs.count { issues.append("more completed stages than the campaign has") }
        for (i, id) in completedStageIDs.enumerated() where i < campaign.stageIDs.count && campaign.stageIDs[i] != id {
            issues.append("completed stage '\(id)' out of campaign order")
        }
        return issues
    }
}
