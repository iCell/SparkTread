import Foundation

/// Product analytics (owner 2026-10-09: Firebase Analytics, with every
/// installed player's progress through the campaign on top of the basics).
///
/// The boundary: the adapters NAME the moments and the numbers; a sink
/// ships them. Firebase itself lives in the app target, never in this
/// package — the simulation, the tests and `swift test` on macOS stay free
/// of it, and the sink can be a recorder in tests or nothing at all when
/// the app runs without a Firebase configuration.
public enum AnalyticsEvent: Equatable, Sendable {
    /// A campaign stage begins (also on retry and on 下一关).
    case stageStarted(stageNumber: Int, stageID: String, difficulty: String)
    /// A campaign stage is won; `lives` is the reserve count carried out.
    case stageCleared(stageNumber: Int, stageID: String, difficulty: String, score: Int, lives: Int)
    /// A campaign stage is lost, with the rulebook's reason id.
    case stageFailed(stageNumber: Int, stageID: String, difficulty: String, reason: String)
    /// The last stage is won.
    case campaignCompleted(difficulty: String, score: Int)

    /// Firebase-style name and parameters: snake_case names under 40
    /// characters, parameter values strings or numbers.
    public var name: String {
        switch self {
        case .stageStarted: "stage_start"
        case .stageCleared: "stage_clear"
        case .stageFailed: "stage_fail"
        case .campaignCompleted: "campaign_complete"
        }
    }

    public var parameters: [String: AnalyticsValue] {
        switch self {
        case let .stageStarted(number, id, difficulty):
            ["stage_number": .int(number), "stage_id": .string(id), "difficulty": .string(difficulty)]
        case let .stageCleared(number, id, difficulty, score, lives):
            ["stage_number": .int(number), "stage_id": .string(id), "difficulty": .string(difficulty),
             "score": .int(score), "lives": .int(lives)]
        case let .stageFailed(number, id, difficulty, reason):
            ["stage_number": .int(number), "stage_id": .string(id), "difficulty": .string(difficulty), "reason": .string(reason)]
        case let .campaignCompleted(difficulty, score):
            ["difficulty": .string(difficulty), "score": .int(score)]
        }
    }
}

public enum AnalyticsValue: Equatable, Sendable {
    case int(Int)
    case string(String)
}

/// User properties: what an INSTALL has reached, set once known and again
/// whenever it grows, so the audience can be cut by progress.
public enum AnalyticsUserProperty: String, Sendable {
    /// The highest stage number ever cleared on this install (0 = none).
    case furthestStageCleared = "furthest_stage_cleared"
    /// How many distinct stages this install has cleared.
    case stagesCleared = "stages_cleared"
    /// The difficulty the last run started on.
    case lastDifficulty = "last_difficulty"
}

public protocol AnalyticsSink: AnyObject, Sendable {
    func log(_ event: AnalyticsEvent)
    func setUserProperty(_ property: AnalyticsUserProperty, value: String?)
}

/// The sink in use. The app target installs Firebase's at launch when a
/// configuration is bundled; otherwise nothing is recorded.
@MainActor public enum GameAnalytics {
    public static var sink: AnalyticsSink?

    public static func log(_ event: AnalyticsEvent) { sink?.log(event) }

    public static func set(_ property: AnalyticsUserProperty, _ value: String?) {
        sink?.setUserProperty(property, value: value)
    }

    /// Progress as user properties, from the completed stage ids
    /// (`<theme>_<NN>_<name>`): the highest number cleared and the count.
    public static func recordProgress(completedStageIDs: some Sequence<String>) {
        let numbers = completedStageIDs.compactMap { id in
            id.split(separator: "_").compactMap { Int($0) }.first
        }
        set(.furthestStageCleared, String(numbers.max() ?? 0))
        set(.stagesCleared, String(numbers.count))
    }
}

/// A sink that remembers everything, for tests.
public final class RecordingAnalyticsSink: AnalyticsSink, @unchecked Sendable {
    public private(set) var events: [AnalyticsEvent] = []
    public private(set) var properties: [String: String?] = [:]
    public init() {}
    public func log(_ event: AnalyticsEvent) { events.append(event) }
    public func setUserProperty(_ property: AnalyticsUserProperty, value: String?) { properties[property.rawValue] = value }
}
