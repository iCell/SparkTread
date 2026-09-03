import SpriteKit
import SwiftUI

/// Hosts the bootstrap scene edge-to-edge (ADR-0004): the arena may extend
/// beneath system UI overlays; HUD and controls (none yet) stay safe-area-aware.
public struct BootstrapArenaView: View {
    @State private var scene = CompositionRoot.makeBootstrapScene()

    public init() {}

    public var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
            .background(Color.black)
            .persistentSystemOverlays(.hidden)
    }
}
