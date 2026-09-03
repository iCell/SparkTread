import GameApplication
import SpriteKit

/// The only place (besides the app entry target) that wires concrete
/// implementations together (§14.2).
public enum CompositionRoot {
    @MainActor
    public static func makeBootstrapScene() -> SKScene {
        BootstrapScene(session: BootstrapSession())
    }
}
