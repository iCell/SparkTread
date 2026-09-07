import Foundation
import GameCore

/// VS-01 "First Defense" (§11.3). The stage is now authored as canonical
/// content at `Content/stages/frontier_01_first_defense.json` and loaded
/// through the content pipeline; this enum is just the runtime entry point.
public enum VS01Stage {
    public static let stageID = "frontier_01_first_defense"

    /// Builds the VS-01 world from the bundled canonical stage JSON. A
    /// missing/invalid bundled stage is a build error (§15.4 fail-fast).
    public static func makeWorld(bundle: Bundle = .main) -> WorldState {
        do {
            return try StageLoader.loadWorld(id: stageID, bundle: bundle)
        } catch {
            fatalError("VS-01 stage content failed to load: \(error)")
        }
    }
}
