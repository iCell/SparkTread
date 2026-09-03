import SwiftUI

/// Application entry point.
///
/// One of the two places allowed to wire concrete implementations together (plan §14.2);
/// the other is `Sources/AppleAdapters/Bootstrap/`. For M0 it only shows the diagnostic
/// scene — real composition arrives with M1.
@main
struct SparkTreadApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
        }
    }
}
