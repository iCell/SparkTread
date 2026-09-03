import SpriteKit
import SwiftUI

/// Swipeable review pages for the PixelProduction delivery, rendered by the
/// real SpriteKit pipeline on device. Set the SHOWCASE_PAGE launch environment
/// variable (0–4) to preselect a page for automated capture.
public struct PixelShowcaseView: View {
    @State private var page: Int
    @State private var battleScene = PixelShowcaseScene(size: showcaseSize, mode: .battle)
    @State private var rosterScene = PixelShowcaseScene(size: showcaseSize, mode: .roster)
    @State private var directionsScene = PixelShowcaseScene(size: showcaseSize, mode: .directions)
    @State private var itemsScene = PixelShowcaseScene(size: showcaseSize, mode: .items)

    private static let showcaseSize = CGSize(width: 844, height: 390)

    public init() {
        let preset = ProcessInfo.processInfo.environment["SHOWCASE_PAGE"].flatMap(Int.init) ?? 0
        _page = State(initialValue: min(max(preset, 0), 4))
    }

    public var body: some View {
        TabView(selection: $page) {
            MovementLabView().tag(0)
            SpriteView(scene: battleScene).ignoresSafeArea().tag(1)
            SpriteView(scene: rosterScene).ignoresSafeArea().tag(2)
            SpriteView(scene: directionsScene).ignoresSafeArea().tag(3)
            SpriteView(scene: itemsScene).ignoresSafeArea().tag(4)
        }
#if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .always))
#endif
        .ignoresSafeArea()
        .background(Color.black)
        .persistentSystemOverlays(.hidden)
    }
}
