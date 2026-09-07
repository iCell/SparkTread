import Foundation
import GameApplication

/// Decodes content JSON into GameApplication value types and runs validation.
/// Tooling/adapter layer: may import Foundation; production core must not.
public enum RegistryLoader {
    /// Top-level keys the registry document may carry. Unknown fields are
    /// rejected until the schema explicitly permits extension data (§15.5).
    static let knownKeys: Set<String> = Set(["format_version", "notes"]).union(IDRegistryValidator.requiredCategories)

    public static func validateRegistry(at url: URL) -> [ContentIssue] {
        let file = url.lastPathComponent
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return [ContentIssue(file: file, field: "-", message: "cannot read file: \(error.localizedDescription)")]
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return [ContentIssue(file: file, field: "-", message: "not valid JSON: \(error.localizedDescription)")]
        }
        guard let dictionary = object as? [String: Any] else {
            return [ContentIssue(file: file, field: "-", message: "top level must be a JSON object")]
        }

        var issues: [ContentIssue] = []
        for key in dictionary.keys.sorted() where !knownKeys.contains(key) {
            issues.append(ContentIssue(
                file: file, field: key,
                message: "unknown field; extension data is rejected until the schema permits it"))
        }
        guard let version = dictionary["format_version"] as? Int else {
            issues.append(ContentIssue(file: file, field: "format_version", message: "missing or not an integer"))
            return issues
        }

        var categories: [(name: String, ids: [String])] = []
        for name in IDRegistryValidator.requiredCategories {
            guard let value = dictionary[name] else { continue } // reported as missing by the validator
            guard let ids = value as? [String] else {
                issues.append(ContentIssue(file: file, field: name, message: "must be an array of strings"))
                continue
            }
            categories.append((name: name, ids: ids))
        }
        issues.append(contentsOf: IDRegistryValidator.validate(
            IDRegistry(formatVersion: version, categories: categories), file: file))
        return issues
    }

    /// Validates every content document under a content root. M0 knows only
    /// the ID registry; stage/weapon/etc. schemas append here as they land.
    public static func validateContentRoot(_ root: URL) -> [ContentIssue] {
        let registry = root.appendingPathComponent("Schemas/id_registry.json")
        guard FileManager.default.fileExists(atPath: registry.path) else {
            return [ContentIssue(
                file: "Schemas/id_registry.json", field: "-",
                message: "missing; the stable-ID registry is required (GE-020)")]
        }
        var issues = validateRegistry(at: registry)
        issues.append(contentsOf: validateStages(in: root))
        return issues
    }

    /// Validates every stage JSON under `Content/stages` (§15.3) through the
    /// GameApplication StageValidator.
    public static func validateStages(in root: URL) -> [ContentIssue] {
        let dir = root.appendingPathComponent("stages")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        var issues: [ContentIssue] = []
        for url in entries.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let file = "stages/" + url.lastPathComponent
            guard let data = try? Data(contentsOf: url) else {
                issues.append(ContentIssue(file: file, field: "-", message: "cannot read file"))
                continue
            }
            do {
                let def = try StageLoader.decode(data)
                for message in StageValidator.validate(def) {
                    issues.append(ContentIssue(file: file, field: def.id.isEmpty ? "-" : def.id, message: message))
                }
            } catch {
                issues.append(ContentIssue(file: file, field: "-", message: "invalid stage JSON: \(error)"))
            }
        }
        return issues
    }
}
