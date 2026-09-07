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
    public static func loadWorld(id: String, bundle: Bundle) throws -> WorldState {
        guard let url = bundle.url(forResource: id, withExtension: "json", subdirectory: "Content/stages")
            ?? bundle.url(forResource: id, withExtension: "json", subdirectory: "stages")
            ?? bundle.url(forResource: id, withExtension: "json") else {
            throw LoadError.notFound(id)
        }
        return try loadWorld(at: url)
    }

    public static func loadWorld(at url: URL) throws -> WorldState {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw LoadError.notFound(url.lastPathComponent) }
        let def = try decode(data)
        let issues = StageValidator.validate(def)
        if !issues.isEmpty { throw LoadError.build(issues.joined(separator: "; ")) }
        do { return try StageBuilder.build(def) }
        catch { throw LoadError.build(String(describing: error)) }
    }
}
