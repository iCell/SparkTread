/// One authored stage file, decoded from UTF-8 JSON (plan §15.1).
///
/// M0 pins only the envelope every stage must carry. Layout, waves, and objectives are
/// added in later milestones behind a `schemaVersion` bump plus a migration.
public struct StageDocument: Codable, Sendable {
    /// Schema version of the file on disk. Mismatches are rejected, never guessed at.
    public var schemaVersion: Int

    /// Stable stage identifier used by saves, replays, and content references.
    public var id: String

    /// Human-readable stage name for menus.
    public var title: String

    /// Authored arena width in cells. Must match the engine arena.
    public var gridColumns: Int

    /// Authored arena height in cells. Must match the engine arena.
    public var gridRows: Int

    /// The schema version this build reads and writes.
    public static let currentSchemaVersion = 1

    public init(
        schemaVersion: Int = StageDocument.currentSchemaVersion,
        id: String,
        title: String,
        gridColumns: Int,
        gridRows: Int
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.gridColumns = gridColumns
        self.gridRows = gridRows
    }
}
