import AppleAdapters
import FirebaseAnalytics
import FirebaseCore
import Foundation

/// Firebase Analytics as the app's sink (owner 2026-10-09). Firebase lives
/// here, in the app target, and nowhere else: the adapters only name the
/// events. Configured at launch when `GoogleService-Info.plist` is bundled;
/// without it the app runs with no analytics at all — never a crash and
/// never a half-configured SDK.
final class FirebaseAnalyticsSink: AnalyticsSink, @unchecked Sendable {
    /// Installs the sink if a Firebase configuration ships in the bundle.
    @MainActor static func installIfConfigured() {
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else { return }
        FirebaseApp.configure()
        GameAnalytics.sink = FirebaseAnalyticsSink()
    }

    func log(_ event: AnalyticsEvent) {
        var parameters: [String: Any] = [:]
        for (key, value) in event.parameters {
            switch value {
            case .int(let n): parameters[key] = n
            case .string(let s): parameters[key] = s
            }
        }
        Analytics.logEvent(event.name, parameters: parameters)
    }

    func setUserProperty(_ property: AnalyticsUserProperty, value: String?) {
        Analytics.setUserProperty(value, forName: property.rawValue)
    }
}
