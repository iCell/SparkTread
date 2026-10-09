import AppleAdapters
import SwiftUI

@main
struct GoldenEagleApp: App {
    init() {
        // Analytics first, so the root's launch-time progress properties
        // reach a configured sink (or none, when no plist is bundled).
        FirebaseAnalyticsSink.installIfConfigured()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
