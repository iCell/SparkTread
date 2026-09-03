import Foundation
import GameCore

/// Decodes and checks stage content.
///
/// Operates on in-memory `Data` only: this module never touches the filesystem, so the
/// same validation runs from the app bundle, from a test fixture string, and from the
/// `ContentValidator` CLI, which is the only place file reading is allowed.
public enum StageValidator {
    /// Decodes stage JSON and enforces the M0 invariants.
    ///
    /// - Throws: `ContentError` describing the first problem found, with a fix in its message.
    public static func validate(stageData: Data) throws -> StageDocument {
        let document: StageDocument
        do {
            document = try JSONDecoder().decode(StageDocument.self, from: stageData)
        } catch {
            throw ContentError.malformedJSON(underlying: String(describing: error))
        }

        guard document.schemaVersion == StageDocument.currentSchemaVersion else {
            throw ContentError.unsupportedSchemaVersion(
                found: document.schemaVersion,
                supported: StageDocument.currentSchemaVersion
            )
        }

        guard !document.id.isEmpty else {
            throw ContentError.emptyIdentifier
        }

        guard document.gridColumns == Int(ArenaGeometry.columns),
              document.gridRows == Int(ArenaGeometry.rows) else {
            throw ContentError.gridMismatch(
                columns: document.gridColumns,
                rows: document.gridRows
            )
        }

        return document
    }
}
