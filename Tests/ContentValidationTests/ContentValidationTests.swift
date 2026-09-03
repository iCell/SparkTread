import Foundation
import Testing
import GameApplication
@testable import ContentValidatorKit

private let repoContentRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // ContentValidationTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // repo root
    .appendingPathComponent("Content")

@Suite struct ContentValidationTests {
    /// M0 exit criterion: the shipped seed registry validates cleanly.
    @Test func seededRegistryPasses() {
        let issues = RegistryLoader.validateContentRoot(repoContentRoot)
        #expect(issues.isEmpty, "unexpected issues: \(issues)")
    }

    /// M0 exit criterion: invalid sample content fails with actionable
    /// errors — each issue names the file, the field, and the reason.
    @Test func invalidSampleFailsWithActionableErrors() throws {
        let fixture = try #require(Bundle.module.url(
            forResource: "invalid_id_registry", withExtension: "json", subdirectory: "Fixtures"))
        let issues = RegistryLoader.validateRegistry(at: fixture)

        func hasIssue(field: String, containing fragment: String) -> Bool {
            issues.contains { $0.field == field && $0.message.contains(fragment) }
        }
        #expect(hasIssue(field: "format_version", containing: "unsupported version 99"))
        #expect(hasIssue(field: "surprise_field", containing: "unknown field"))
        #expect(hasIssue(field: "rulesets/campaign_v1", containing: "duplicate ID"))
        #expect(hasIssue(field: "difficulties/Standard", containing: "lowercase"))
        #expect(hasIssue(field: "weapons", containing: "at least one ID"))
        #expect(hasIssue(field: "equipment/anti__skid", containing: "consecutive underscores"))
        #expect(hasIssue(field: "equipment/shield_of_moon_", containing: "end with an underscore"))
        #expect(hasIssue(field: "pickups/speed-up", containing: "may only contain"))
        #expect(hasIssue(field: "stages", containing: "missing"))
        for issue in issues {
            #expect(issue.file == "invalid_id_registry.json")
            #expect(!issue.message.isEmpty)
        }
    }

    @Test func missingRegistryIsItselfActionable() {
        let issues = RegistryLoader.validateContentRoot(URL(fileURLWithPath: "/nonexistent"))
        #expect(issues.count == 1)
        #expect(issues[0].message.contains("required"))
    }
}

@Suite struct StableIDTests {
    @Test func acceptsCanonicalForms() {
        for id in ["ap", "shield_of_moon", "frontier_01_first_defense", "score_200", "normal_a"] {
            #expect(StableID.isValid(id), "expected valid: \(id)")
        }
    }

    @Test func rejectsInvalidFormsWithReasons() {
        #expect(StableID.rejectionReason("") == "ID is empty")
        #expect(StableID.rejectionReason("1up")?.contains("start with") == true)
        #expect(StableID.rejectionReason("_ap")?.contains("start with") == true)
        #expect(StableID.rejectionReason("Ap")?.contains("lowercase") == true)
        #expect(StableID.rejectionReason("ap c")?.contains("may only contain") == true)
        #expect(StableID.rejectionReason("ap—c")?.contains("may only contain") == true)
    }
}
