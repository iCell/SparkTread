import SpriteKit
import SwiftUI

/// Hosts the SpriteKit scene full-bleed and landscape.
///
/// The view owns no gameplay state: it is a window onto the scene, and the scene is a
/// window onto simulation snapshots. Orientation is locked to landscape in the Info.plist
/// keys declared by `project.yml`, so no rotation handling belongs here.
struct GameView: View {
    /// Fixed presentation resolution. `.aspectFit` letterboxes it onto any device, which
    /// keeps the 48x27 arena fully visible without a scrolling camera.
    static let sceneSize = CGSize(width: 1_344, height: 756)

    @State private var scene: BootstrapScene = {
        let scene = BootstrapScene(size: GameView.sceneSize)
        scene.scaleMode = .aspectFit
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
    }
}
