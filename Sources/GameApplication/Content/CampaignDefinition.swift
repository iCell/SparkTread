import GameCore

/// Canonical campaign schema (`Content/campaigns/*.json`): the ordered stage
/// list a run walks (ADR-0013). Stage `n` of the list must carry
/// `stageNumber == n + 1` so the clear-bonus tiers (ADR-0012) and the card
/// title agree with the order. Codable is standard-library only; decoding
/// happens in `CampaignLoader`.
public struct CampaignDefinition: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var displayNameKey: String
    public var stageIDs: [String]

    public init(schemaVersion: Int = 1, id: String, displayNameKey: String, stageIDs: [String]) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayNameKey = displayNameKey
        self.stageIDs = stageIDs
    }

    public var stageCount: Int { stageIDs.count }
}

public enum CampaignValidator {
    public static let maxStages = 99

    /// Structural checks on the definition alone; `validate(_:stages:)`
    /// adds the cross-checks against the stage definitions it names.
    public static func validate(_ def: CampaignDefinition) -> [String] {
        var issues: [String] = []
        if def.schemaVersion != 1 { issues.append("schema_version \(def.schemaVersion) unsupported (expected 1)") }
        if def.id.isEmpty { issues.append("id is empty") }
        if def.stageIDs.isEmpty { issues.append("stage_ids is empty") }
        if def.stageIDs.count > maxStages { issues.append("stage_ids count \(def.stageIDs.count) exceeds \(maxStages)") }
        if Set(def.stageIDs).count != def.stageIDs.count { issues.append("stage_ids repeats a stage") }
        for id in def.stageIDs where id.isEmpty { issues.append("stage_ids contains an empty id") }
        return issues
    }

    /// Cross-checks: every listed stage exists and is numbered by its
    /// position (1-based).
    public static func validate(_ def: CampaignDefinition, stages: [String: StageDefinition]) -> [String] {
        var issues = validate(def)
        for (index, id) in def.stageIDs.enumerated() {
            guard let stage = stages[id] else { issues.append("stage '\(id)' not found"); continue }
            if stage.stageNumber != index + 1 {
                issues.append("stage '\(id)' is number \(stage.stageNumber.map(String.init) ?? "nil") at position \(index + 1)")
            }
        }
        return issues
    }
}
