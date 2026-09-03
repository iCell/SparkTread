import GameCore

/// Content problems reported back to whoever authored the file.
///
/// Every case's `description` names the offending value *and* the fix, because these
/// messages are the entire diagnostic surface of the `ContentValidator` tool and of CI.
public enum ContentError: Error, Equatable, CustomStringConvertible {
    /// The bytes are not valid JSON, or do not match the stage schema's shape.
    case malformedJSON(underlying: String)

    /// The file declares a schema version this build cannot read.
    case unsupportedSchemaVersion(found: Int, supported: Int)

    /// `id` is missing or blank, so nothing can reference this stage.
    case emptyIdentifier

    /// The authored grid does not match the fixed engine arena.
    case gridMismatch(columns: Int, rows: Int)

    public var description: String {
        switch self {
        case .malformedJSON(let underlying):
            return """
                Stage file could not be decoded: \(underlying). \
                Check that the file is valid UTF-8 JSON and that every required field \
                (schemaVersion, id, title, gridColumns, gridRows) is present with the right type.
                """
        case .unsupportedSchemaVersion(let found, let supported):
            return """
                Stage file declares schemaVersion \(found) but this build reads \(supported). \
                Set "schemaVersion": \(supported), or run the content migration for version \(found).
                """
        case .emptyIdentifier:
            return """
                Stage file has an empty "id". Give the stage a stable, non-empty identifier \
                (for example "stage_01"); saves and replays reference stages by this value.
                """
        case .gridMismatch(let columns, let rows):
            return """
                Stage grid is \(columns)x\(rows) but the arena is fixed at \
                \(ArenaGeometry.columns)x\(ArenaGeometry.rows) (ADR-0003). \
                Set "gridColumns": \(ArenaGeometry.columns) and "gridRows": \(ArenaGeometry.rows), \
                and re-author the layout to fit.
                """
        }
    }
}
