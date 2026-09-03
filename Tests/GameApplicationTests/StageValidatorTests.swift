import Foundation
import Testing
@testable import GameApplication

@Suite("StageValidator")
struct StageValidatorTests {
    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    private let validStage = """
        {
          "schemaVersion": 1,
          "id": "stage_01",
          "title": "First Contact",
          "gridColumns": 48,
          "gridRows": 27
        }
        """

    @Test("a valid stage decodes and round-trips its fields")
    func validStageRoundTrips() throws {
        let document = try StageValidator.validate(stageData: data(validStage))
        #expect(document.schemaVersion == 1)
        #expect(document.id == "stage_01")
        #expect(document.title == "First Contact")
        #expect(document.gridColumns == 48)
        #expect(document.gridRows == 27)
    }

    @Test("malformed JSON is reported as malformedJSON")
    func malformedJSONIsRejected() {
        #expect {
            try StageValidator.validate(stageData: data("{ not json at all"))
        } throws: { error in
            guard case .malformedJSON = error as? ContentError else { return false }
            return true
        }
    }

    @Test("a missing required field is reported as malformedJSON")
    func missingFieldIsRejected() {
        let json = """
            { "schemaVersion": 1, "id": "stage_01", "gridColumns": 48, "gridRows": 27 }
            """
        #expect {
            try StageValidator.validate(stageData: data(json))
        } throws: { error in
            guard case .malformedJSON(let underlying) = error as? ContentError else { return false }
            // The decoder's own message must survive into the diagnostic.
            return underlying.contains("title")
        }
    }

    @Test("an unknown schema version reports both versions")
    func unsupportedSchemaVersionCarriesBothNumbers() {
        let json = validStage.replacingOccurrences(
            of: "\"schemaVersion\": 1",
            with: "\"schemaVersion\": 999"
        )
        #expect {
            try StageValidator.validate(stageData: data(json))
        } throws: { error in
            error as? ContentError == .unsupportedSchemaVersion(found: 999, supported: 1)
        }
    }

    @Test("an empty id is rejected")
    func emptyIdentifierIsRejected() {
        let json = validStage.replacingOccurrences(of: "\"stage_01\"", with: "\"\"")
        #expect {
            try StageValidator.validate(stageData: data(json))
        } throws: { error in
            error as? ContentError == .emptyIdentifier
        }
    }

    @Test("a wrong grid is rejected and the message names the expected arena")
    func gridMismatchIsRejected() {
        let json = validStage
            .replacingOccurrences(of: "\"gridColumns\": 48", with: "\"gridColumns\": 40")
            .replacingOccurrences(of: "\"gridRows\": 27", with: "\"gridRows\": 30")

        #expect {
            try StageValidator.validate(stageData: data(json))
        } throws: { error in
            guard let contentError = error as? ContentError,
                  contentError == .gridMismatch(columns: 40, rows: 30) else { return false }
            let message = contentError.description
            // The author must be told the arena is 48x27, not just that theirs is wrong.
            return message.contains("40x30") && message.contains("48") && message.contains("27")
        }
    }

    @Test("every error description is non-empty and actionable")
    func descriptionsAreActionable() {
        let errors: [ContentError] = [
            .malformedJSON(underlying: "boom"),
            .unsupportedSchemaVersion(found: 2, supported: 1),
            .emptyIdentifier,
            .gridMismatch(columns: 1, rows: 1),
        ]
        for error in errors {
            #expect(!error.description.isEmpty)
        }
    }
}
