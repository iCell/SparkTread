/// Content validation use cases (§15.3 skeleton). Pure logic over already
/// decoded values; file I/O and JSON decoding live in Tools/ContentValidator
/// and, later, the platform adapters. Grows per milestone as schemas land.

/// One actionable validation failure: which file, which field, what is wrong.
public struct ContentIssue: Equatable, Sendable, CustomStringConvertible {
    public let file: String
    public let field: String
    public let message: String

    public init(file: String, field: String, message: String) {
        self.file = file
        self.field = field
        self.message = message
    }

    public var description: String { "\(file): \(field): \(message)" }
}

/// The decoded stable-ID registry: ordered categories of ordered IDs.
public struct IDRegistry: Equatable, Sendable {
    public let formatVersion: Int
    public let categories: [(name: String, ids: [String])]

    public init(formatVersion: Int, categories: [(name: String, ids: [String])]) {
        self.formatVersion = formatVersion
        self.categories = categories
    }

    public static func == (lhs: IDRegistry, rhs: IDRegistry) -> Bool {
        lhs.formatVersion == rhs.formatVersion
            && lhs.categories.count == rhs.categories.count
            && zip(lhs.categories, rhs.categories).allSatisfy { $0.name == $1.name && $0.ids == $1.ids }
    }
}

public enum IDRegistryValidator {
    public static let supportedFormatVersion = 1

    /// Categories the M0 seed must provide (plan §19 M0 deliverables).
    public static let requiredCategories = [
        "rulesets", "difficulties", "weapons", "equipment", "pickups", "enemies", "themes", "stages",
    ]

    public static func validate(_ registry: IDRegistry, file: String) -> [ContentIssue] {
        var issues: [ContentIssue] = []
        if registry.formatVersion != supportedFormatVersion {
            issues.append(ContentIssue(
                file: file, field: "format_version",
                message: "unsupported version \(registry.formatVersion); this validator supports \(supportedFormatVersion)"))
        }
        let present = registry.categories.map(\.name)
        for required in requiredCategories where !present.contains(required) {
            issues.append(ContentIssue(
                file: file, field: required,
                message: "required ID category is missing"))
        }
        var seenCategories = Set<String>()
        for category in registry.categories {
            if !seenCategories.insert(category.name).inserted {
                issues.append(ContentIssue(
                    file: file, field: category.name,
                    message: "duplicate category"))
            }
            if category.ids.isEmpty {
                issues.append(ContentIssue(
                    file: file, field: category.name,
                    message: "category must seed at least one ID"))
            }
            var seenIDs = Set<String>()
            for id in category.ids {
                if let reason = StableID.rejectionReason(id) {
                    issues.append(ContentIssue(
                        file: file, field: "\(category.name)/\(id)",
                        message: reason))
                }
                if !seenIDs.insert(id).inserted {
                    issues.append(ContentIssue(
                        file: file, field: "\(category.name)/\(id)",
                        message: "duplicate ID within category"))
                }
            }
        }
        return issues
    }
}

/// Stable-identifier format rules (§15.2): lowercase snake_case, never
/// localized. ASCII lowercase letters, digits, and single underscores;
/// must start with a letter and end with a letter or digit.
public enum StableID {
    public static func rejectionReason(_ id: String) -> String? {
        guard let first = id.unicodeScalars.first else { return "ID is empty" }
        guard isLowercaseLetter(first) else {
            return "ID must start with a lowercase ASCII letter"
        }
        var previousWasUnderscore = false
        for scalar in id.unicodeScalars {
            if scalar == "_" {
                if previousWasUnderscore { return "ID must not contain consecutive underscores" }
                previousWasUnderscore = true
            } else if isLowercaseLetter(scalar) || isDigit(scalar) {
                previousWasUnderscore = false
            } else {
                return "ID may only contain lowercase ASCII letters, digits, and underscores (found '\(scalar)')"
            }
        }
        if previousWasUnderscore { return "ID must not end with an underscore" }
        return nil
    }

    public static func isValid(_ id: String) -> Bool { rejectionReason(id) == nil }

    private static func isLowercaseLetter(_ s: Unicode.Scalar) -> Bool { s >= "a" && s <= "z" }
    private static func isDigit(_ s: Unicode.Scalar) -> Bool { s >= "0" && s <= "9" }
}
