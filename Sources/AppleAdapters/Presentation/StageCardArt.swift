import CoreGraphics
import GameApplication

/// Card art for the select screen: a stage's own map, one pixel per cell.
///
/// The owner asked for a background behind every stage on that screen
/// (2026-10-03). Rather than twelve drawings, each card shows the map it
/// will load — so the cards are distinguishable by the thing that actually
/// differs between them, they cannot drift from the content, and a
/// thirteenth stage brings its own background with it.
///
/// The palette is sampled from the delivery's own art (mean colour of each
/// atlas face, measured 2026-10-03) so a card reads as the same world the
/// stage renders in; the three markers are UI colours, since a base and a
/// spawn are not terrain.
@MainActor enum StageCardArt {
    private static var cache: [String: CGImage] = [:]

    static func image(for map: StagePreview.Map, id: String) -> CGImage? {
        if let cached = cache[id] { return cached }
        guard let context = CGContext(data: nil, width: map.width, height: map.height,
                                      bitsPerComponent: 8, bytesPerRow: map.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.bindMemory(to: UInt8.self,
                                                    capacity: map.width * map.height * 4)
        else { return nil }
        let ground = groundColour(map.themeID)
        for y in 0..<map.height {
            for x in 0..<map.width {
                let (r, g, b) = colour(map[x, y], ground: ground)
                // A bitmap context's MEMORY is top-down even though its
                // drawing space is y-up: writing pixels straight into the
                // buffer needs no flip, and flipping here put the base at the
                // top of the card and the spawns at the bottom.
                let at = (y * map.width + x) * 4
                pixels[at] = r; pixels[at + 1] = g; pixels[at + 2] = b; pixels[at + 3] = 255
            }
        }
        guard let image = context.makeImage() else { return nil }
        cache[id] = image
        return image
    }

    /// Mean colour of each theme's nine ground tiles.
    private static func groundColour(_ themeID: String) -> (UInt8, UInt8, UInt8) {
        switch themeID {
        case "floodplain": (162, 171, 139)
        case "frozen_works": (191, 204, 207)
        case "iron_citadel": (155, 157, 153)
        default: (204, 185, 147)
        }
    }

    private static func colour(_ cell: StagePreview.Cell,
                               ground: (UInt8, UInt8, UInt8)) -> (UInt8, UInt8, UInt8) {
        switch cell {
        case .ground: ground
        case .brick: (167, 100, 63)
        case .whiteBrick: (157, 153, 144)
        case .steel: (98, 117, 127)
        case .whiteSteel: (186, 193, 200)
        case .water: (77, 113, 108)
        case .ice: (161, 197, 203)
        case .foliage: (81, 108, 69)
        // Markers, not terrain: gold for what you defend, teal for where you
        // start, rust for where they come from — the three things that tell
        // two maps apart at a glance.
        case .base: (214, 176, 70)
        case .playerSpawn: (90, 170, 160)
        case .enemySpawn: (176, 86, 62)
        }
    }
}
