import Foundation
import GameCore

/// Decodes stage JSON (Content/stages/*.json) into a `StageDefinition` and
/// builds a world. Foundation lives here, at the content-loading use-case
/// boundary (§14); GameCore stays Foundation-free.
public enum StageLoader {
    public enum LoadError: Error { case notFound(String), decode(String), build(String) }

    /// Decodes a definition from raw JSON data.
    public static func decode(_ data: Data) throws -> StageDefinition {
        do { return try JSONDecoder().decode(StageDefinition.self, from: data) }
        catch { throw LoadError.decode(String(describing: error)) }
    }

    /// Loads a stage by id from a bundle's `Content/stages` (or bundle root),
    /// validates it, and builds the world.
    public static func loadWorld(id: String, bundle: Bundle,
                                 rules: PickupRuleset = .provisional,
                                 session: SessionState = .campaignStart) throws -> WorldState {
        try loadWorld(at: stageURL(id: id, bundle: bundle), rules: rules, session: session)
    }

    public static func stageURL(id: String, bundle: Bundle) throws -> URL {
        guard let url = bundle.url(forResource: id, withExtension: "json", subdirectory: "Content/stages")
            ?? bundle.url(forResource: id, withExtension: "json", subdirectory: "stages")
            ?? bundle.url(forResource: id, withExtension: "json") else {
            throw LoadError.notFound(id)
        }
        return url
    }

    /// The configuration boundary (§15.3): the stage definition, the pickup
    /// rules it will run under AND the carried session state are validated
    /// before a world exists.
    public static func loadWorld(at url: URL, rules: PickupRuleset = .provisional,
                                 session: SessionState = .campaignStart) throws -> WorldState {
        let def = try loadDefinition(at: url)
        let issues = StageValidator.validate(def) + rules.validationIssues() + session.validationIssues
        if !issues.isEmpty { throw LoadError.build(issues.joined(separator: "; ")) }
        do { return try StageBuilder.build(def, rules: rules, session: session) }
        catch { throw LoadError.build(String(describing: error)) }
    }

    public static func loadDefinition(at url: URL) throws -> StageDefinition {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw LoadError.notFound(url.lastPathComponent) }
        return try decode(data)
    }
}

/// Decodes campaign JSON (Content/campaigns/*.json) and cross-checks it
/// against the stages it names (ADR-0013). Same Foundation boundary.
public enum CampaignLoader {
    public static func decode(_ data: Data) throws -> CampaignDefinition {
        do { return try JSONDecoder().decode(CampaignDefinition.self, from: data) }
        catch { throw StageLoader.LoadError.decode(String(describing: error)) }
    }

    public static func campaignURL(id: String, bundle: Bundle) throws -> URL {
        // The app bundle copies content folders flat (root), a package or
        // test bundle may keep the folder: try all three like the stages.
        guard let url = bundle.url(forResource: id, withExtension: "json", subdirectory: "Content/campaigns")
            ?? bundle.url(forResource: id, withExtension: "json", subdirectory: "campaigns")
            ?? bundle.url(forResource: id, withExtension: "json") else {
            throw StageLoader.LoadError.notFound(id)
        }
        return url
    }

    /// Loads a campaign by id from a bundle and validates it against the
    /// bundled stages (every stage present, numbered by position).
    public static func load(id: String, bundle: Bundle) throws -> CampaignDefinition {
        let def = try load(at: campaignURL(id: id, bundle: bundle))
        var stages: [String: StageDefinition] = [:]
        for stageID in def.stageIDs {
            if let url = try? StageLoader.stageURL(id: stageID, bundle: bundle) {
                stages[stageID] = try StageLoader.loadDefinition(at: url)
            }
        }
        let issues = CampaignValidator.validate(def, stages: stages)
        if !issues.isEmpty { throw StageLoader.LoadError.build(issues.joined(separator: "; ")) }
        return def
    }

    /// Decodes and structurally validates a campaign file (the stage
    /// cross-check needs the stage files: see `load(id:bundle:)` and the
    /// content validator tool).
    public static func load(at url: URL) throws -> CampaignDefinition {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw StageLoader.LoadError.notFound(url.lastPathComponent) }
        let def = try decode(data)
        let issues = CampaignValidator.validate(def)
        if !issues.isEmpty { throw StageLoader.LoadError.build(issues.joined(separator: "; ")) }
        return def
    }
}
